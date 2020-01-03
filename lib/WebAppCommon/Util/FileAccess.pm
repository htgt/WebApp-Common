package WebAppCommon::Util::FileAccess;
use strict;
use warnings FATAL => 'all';
use File::Slurp;
use Moose;
use Path::Class::Dir;
use WebAppCommon::Util::RemoteFileAccess;

with 'MooseX::Log::Log4perl';

sub get_file_content {
    my ( $self, $path ) = @_;
    return if not -e $path;
    return read_file($path);
}

sub post_file_content {
    my ( $self, $path, $content ) = @_;
    return write_file($path, $content);
}

sub append_file_content {
    my ( $self, $path, $content ) = @_;
    return append_file($path, $content);
}

sub delete_file {
    my ( $self, $path ) = @_;
    return unlink $path;
}

sub make_dir {
    my ( $self, $path ) = @_;
    return mkdir $path;
}

sub delete_dir {
    my ( $self, $path ) = @_;
    my $dir = Path::Class::Dir->new($path);
    return $dir->rmtree;
}

sub check_file_existence {
    my ( $self, $path ) = @_;
    return -e $path;

sub construct {
    my ( $class, $args ) = @_;
    return $args->{server}
        ? WebAppCommon::Util::RemoteFileAccess->new($args)
        : WebAppCommon::Util::FileAccess->new($args);
}

1;


