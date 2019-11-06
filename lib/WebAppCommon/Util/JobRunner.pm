package WebAppCommon::Util::JobRunner;
use warnings FATAL => 'all';
use strict;
use Moose;
use MooseX::Params::Validate;
use MooseX::Types::Path::Class::MoreCoercions qw/File/;
use IPC::Run3;
use Path::Class;
use Redis;
use String::ShellQuote;
use Try::Tiny;

with 'MooseX::Log::Log4perl';

has default_queue => (
    is      => 'rw',
    isa     => 'Str',
    default => $ENV{BROOCE_DEFAULT_QUEUE} // 'normal',
);

has sub_wrapper => (
    is      => 'rw',
    isa     => File,
    coerce  => 1,
    default => sub { file($ENV{BROOCE_WRAPPER_SCRIPT}) },
);

has redis => (
    is         => 'ro',
    isa        => 'Redis',
    lazy_build => 1,
);

sub _build_redis {
    my %args = ();
    my $host = exists $ENV{REDIS_HOST} ? $ENV{REDIS_HOST} : 'localhost';
    my $port = exists $ENV{REDIS_PORT} ? $ENV{REDIS_PORT} : 6379;
    $args{server}   = "$host:$port";
    $args{password} = $ENV{REDIS_AUTH} if exists $ENV{REDIS_AUTH};
    return Redis->new(%args);
}

sub submit_pspec {
    my $self = shift;
    return (
        out_file        => { isa => File,  coerce   => 1, },
        err_file        => { isa => File,  coerce   => 1, },
        cmd             => { isa => 'ArrayRef', },
        group           => { isa => 'Str', optional => 1, },
        memory_required => { isa => 'Int', optional => 1, },
        queue           => {
            isa      => 'Str',
            optional => 1,
            default  => $self->default_queue,
        },
        wrapper => {
            isa      => 'Str',
            optional => 1,
            default  => $self->sub_wrapper,
        },

    );
}

sub submit {
    my $self = shift;
    my %args = validated_hash( \@_, $self->submit_pspec );

    my $id      = $self->redis->incr("jobid");
    my $outfile = $args{out_file}->stringify;
    my $errfile = $args{err_file}->stringify;
    $outfile =~ s/%J/$id/g;
    $errfile =~ s/%J/$id/g;
    my @cmd = map { s/%J/$id/g; $_; } @{ $args{cmd} };

    # push job info into redis
    $self->redis->mset(
        "cmd:$id" => shell_quote(@cmd),
        "out:$id" => $outfile,
        "err:$id" => $errfile,
    );

    # push job to queue
    my $wrapper = $args{wrapper}->stringify;
    my $queue   = "brooce:queue:$args{queue}:pending";
    $self->log->info("Adding $id to $queue");
    $self->redis->lpush( $queue, "$wrapper $id" );
    return $id;
}

sub kill_job {
    my ( $self, $id ) = @_;
    $self->log->info("Deleting job:'$id'");
    $self->redis->del( "cmd:$id", "out:$id", "err:$id" );
    return;
}

sub construct {
    my ( $class, $args ) = @_;
    return $args->{server}
        ? WebAppCommon::Util::FarmJobRunner->new($args)
        : WebAppCommon::Util::JobRunner->new($args);
}

1;
