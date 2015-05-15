package WebAppCommon::Util::FindGene;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Util::FindGene::VERSION = '0.035';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [
        qw(
            c_find_gene
            c_autocomplete_gene
          )
    ]
};

use Log::Log4perl qw( :easy );
use Const::Fast;
use Data::Dumper;

use WebAppCommon::Util::Solr;
my $solr = WebAppCommon::Util::Solr->new;

const my $MGI_ACCESSION_ID_RX => qr/^MGI:\d+$/;
const my $ENSEMBL_GENE_ID_RX  => qr/^ENS[A-Z]*G\d+$/;
const my $HGNC_GENE_ID_RX =>qr/^HGNC:\d+$/;

sub c_find_gene {
    my ( $params ) = @_;

    my $search_term = $params->{search_term};
    my $search_species = $params->{species};
    my $show_all = $params->{show_all};

    my $genes;

    if ( $search_term =~ $MGI_ACCESSION_ID_RX || $search_term =~ $HGNC_GENE_ID_RX ) {
        $genes = $solr->query( [ id => $search_term ], $show_all );
    }
    elsif ( $search_term =~ $ENSEMBL_GENE_ID_RX ) {
        $genes = $solr->query( [ ensembl_id => $search_term ], $show_all );
    }
    else {
        $genes = $solr->query( [ symbol => lc($search_term), species => $search_species ], $show_all );
    }

    if ( @{$genes} == 0 ) {
        return {
            gene_id     => $params->{search_term},
            gene_symbol => 'unknown',
            ensembl_id  => '',
            chromosome  => '',
        };
    }

    if ( @{$genes} > 1 ) {
        die "Retrieval of $search_species gene $search_term returned " . @{$genes} . " genes";
    }

    return normalize_solr_result( shift @{$genes} );
}

sub c_autocomplete_gene {
    my ( $params ) = @_;

    my $search_term = $params->{search_term};
    my $search_species = $params->{species};

    my $genes;

    if ( $search_term =~ $MGI_ACCESSION_ID_RX || $search_term =~ $HGNC_GENE_ID_RX ) {
        $genes = $solr->query( [ text => $search_term, species => $search_species ] );
    }
    elsif ( $search_term =~ $ENSEMBL_GENE_ID_RX ) {
        $genes = $solr->query( [ text => $search_term, species => $search_species ] );
    }
    else {
        $genes = $solr->query( [ text => lc($search_term), species => $search_species ] );
    }

    for (my $i = 0; $i < scalar @{$genes}; $i++ ) {
        ${$genes}[$i] = normalize_solr_result(${$genes}[$i])
    }
    return @{$genes};
}

sub normalize_solr_result {
    my ( $solr_result ) = @_;
    my %normalized = %{ $solr_result };

    $normalized{gene_id}     = delete $normalized{id} if $normalized{id};
    $normalized{gene_symbol} = delete $normalized{symbol} if $normalized{symbol};
    $normalized{ensembl_id}  = delete $normalized{ensembl_id} if $normalized{ensembl_id};

    return \%normalized;
}

1;

__END__
