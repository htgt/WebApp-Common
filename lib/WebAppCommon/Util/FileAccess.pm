package WebAppCommon::Util::FileAccess;
use strict;
use warnings FATAL => 'all';
use File::Slurp;
use File::Temp;
use Moose;
use Net::SCP;

with 'MooseX::Log::Log4perl';

has server => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has scp => (
    is       => 'ro',
    isa      => 'Net::SCP',
    lazy_build => 1,
);

sub _build_scp {
    my $self = shift;
    return Net::SCP->new($self->server);
}

sub get_file_content {
    my ( $self, $path ) = @_;
    my $dest = tmpnam();
    $self->scp->get($path, $dest);
    my $content = read_file($dest);
    unlink $dest;
    return $content;
}

sub post_file_content {
    my ( $self, $path, $content ) = @_;
    my $src = tmpnam();
    write_file($src, $content);
    $self->scp->put($src, $path);
    $self->log->debug("posting file content to $path");
    unlink $src;
    return;
}

sub make_dir {
    my ( $self, $path ) = @_;
    $self->log->debug("posting directory to $path");
    $self->scp->mkdir($path);
}

1;


