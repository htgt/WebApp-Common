package WebAppCommon::Util::Solr;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Util::Solr::VERSION = '0.046';
}
## use critic


use Moose;
use MooseX::Types::URI qw( Uri );
use LWP::UserAgent;
use Hash::MoreUtils qw( slice );
use URI;
use JSON;
use namespace::autoclean;
use Try::Tiny;

has solr_uri => (
    is      => 'ro',
    isa     => Uri,
    coerce  => 1,
    default => sub { URI->new($ENV{SOLR_URL} || 'http://htgt3.internal.sanger.ac.uk:8983/solr/select') }
);

has solr_rows => (
    is      => 'ro',
    isa     => 'Int',
    default => 25
);

has solr_max_rows => (
    is      => 'ro',
    isa     => 'Int',
    default => 500
);

# user agent used to get url
has ua => (
    is         => 'ro',
    isa        => 'LWP::UserAgent',
    lazy_build => 1,
    handles    => [ 'get' ]
);

sub _build_ua {
    my $ua = LWP::UserAgent->new();
    $ua->timeout(1);

    return $ua;
}

sub query {
    my ( $self, $search_term, $show_all ) = @_;

    # build the search string
    my $search_str = $self->build_search_str( $search_term );

    # what to get back from the search
    my @attrs = ('id', 'symbol', 'ensembl_id', 'chromosome');

    my @results;
    my ( $start, $num_found ) = ( 0, 0 );
    while( $start <= $num_found ) {
        my $result = $self->do_solr_query( $search_str, $start );
        $num_found = $result->{response}{numFound};
        if ( $num_found > $self->solr_max_rows ) {
            die "Too many results ($num_found) returned for '$search_str'";
        }
        push @results, map { +{ slice $_, @attrs } } @{ $result->{response}{docs} };
        $start += $self->solr_rows;
    }
    return \@results;
}

sub do_solr_query {
    my ( $self, $search_str, $start ) = @_;

    $self->solr_uri->query_form( q => $search_str, wt => 'json', rows => $self->solr_rows, start => $start );
    my $uri = $self->solr_uri;

    my $response = $self->get($self->solr_uri);

    unless ( $response->is_success ) {
        die "Solr search for '$search_str' failed: " . $response->message;
    }

    return decode_json( $response->content );
}

sub build_search_str {
    my ( $self, $search_term ) = @_;
    my $reftype = ref $search_term;

    if ( $reftype && $reftype eq ref []) {
        if ( scalar @$search_term == 2 ) {
            return $search_term->[0] . ':' . $self->quote_str( $search_term->[1] );
        }
        elsif ( scalar @$search_term == 4 ) {
            if ($search_term->[0] eq 'text') {
                $search_term->[1] =~ s/\w*:/*/;
                return $search_term->[1] . '* AND ' .
                $search_term->[2] . ':' . $self->quote_str( $search_term->[3] );
            } else {
                return $search_term->[0] . ':' . $self->quote_str( $search_term->[1] ) .
                ' AND ' . $search_term->[2] . ':' . $self->quote_str( $search_term->[3] );
            }
        }
        die "Cannot build search string from $reftype";
    }

    die "No search_term provided";
}

sub quote_str {
    my ( $self, $str ) = @_;

    $str =~ s/"/\"/g;

    return sprintf '"%s"', $str;
}

__PACKAGE__->meta->make_immutable;

1;
