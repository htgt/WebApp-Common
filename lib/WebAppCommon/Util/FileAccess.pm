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
    my $success = $self->scp->get($path, $dest);
    $self->log->debug($self->scp->{errstr}) if !$success;
    my $want_array = wantarray;
    if ( -e $dest ) {
        my $content = read_file($dest, array_ref => $want_array);
        unlink $dest;
        return $want_array ? @{$content} : $content;
    }
    else {
        return undef;
    }
}

sub post_file_content {
    my ( $self, $path, $content ) = @_;
    $self->log->debug("posting file content to $path");
    my $src = tmpnam();
    write_file($src, $content);
    my $success = $self->scp->put($src, $path);
    $self->log->debug($self->scp->{errstr}) if !$success;
    unlink $src;
    return !$success;
}

sub append_file_content {
    my ( $self, $path, $content ) = @_;
    my $existing = $self->get_file_content($path) // q//;
    return $self->post_file_content($path, $existing . $content);
}

sub make_dir {
    my ( $self, $path ) = @_;
    $self->log->debug("posting directory to $path");
    my $success = $self->scp->mkdir($path);
    $self->log->debug($self->scp->{errstr}) if !$success;
    return !$success;
}

1;


