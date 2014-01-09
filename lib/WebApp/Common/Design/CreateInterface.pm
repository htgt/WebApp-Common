package WebApp::Common::Design::CreateInterface;

use strict;
use warnings FATAL => 'all';

use Moose::Role;
use LIMS2::Exception;
use List::MoreUtils qw( uniq );

requires qw(
schema
species
ensembl_util
check_params
create_design_attempt
create_design_target
);

=head2 get_ensembl_gene

Grab a ensembl gene object.
First need to work out format of gene name user has supplied

=cut
## no critic(BuiltinFunctions::ProhibitComplexMappings)
sub get_ensembl_gene {
    my ( $self, $gene_name ) = @_;

    my $ga = $self->ensembl_util->gene_adaptor( $self->species );

    my $gene;
    if ( $gene_name =~ /ENS(MUS)?G\d+/ ) {
        $gene = $ga->fetch_by_stable_id( $gene_name );
    }
    elsif ( $gene_name =~ /HGNC:(\d+)/ ) {
        $gene = $self->_fetch_by_external_name( $ga, $1, 'HGNC' );
    }
    elsif ( $gene_name =~ /MGI:\d+/  ) {
        $gene = $self->_fetch_by_external_name( $ga, $gene_name, 'MGI' );
    }
    else {
        #assume its a marker symbol
        $gene = $self->_fetch_by_external_name( $ga, $gene_name );
    }

    return $gene;
}

## use critic

=head2 _fetch_by_external_name

Wrapper around fetching ensembl gene given external gene name.

=cut
sub _fetch_by_external_name {
    my ( $self, $ga, $gene_name, $type ) = @_;

    my @genes = @{ $ga->fetch_all_by_external_name($gene_name, $type) };
    unless( @genes ) {
        LIMS2::Exception->throw("Unable to find gene $gene_name in EnsEMBL" );
    }

    if ( scalar(@genes) > 1 ) {
        $self->log->debug("Found multiple EnsEMBL genes for $gene_name");
        my @stable_ids = map{ $_->stable_id } @genes;
        $type ||= 'marker symbol';

        LIMS2::Exception->throw( "Found multiple EnsEMBL genes with $type id $gene_name,"
                . " try using one of the following EnsEMBL gene ids: "
                . join( ', ', @stable_ids ) );
    }
    else {
        return shift @genes;
    }

    return;
}

=head2 build_gene_data

Build up data about targeted gene to display to user.

=cut
sub build_gene_data {
    my ( $self, $gene ) = @_;
    my %data;

    my $canonical_transcript = $gene->canonical_transcript;
    $data{ensembl_id} = $gene->stable_id;
    if ( $self->species eq 'Human' ) {
        $data{gene_link} = 'http://www.ensembl.org/Homo_sapiens/Gene/Summary?g='
            . $gene->stable_id;
        $data{transcript_link} = 'http://www.ensembl.org/Homo_sapiens/Transcript/Summary?t='
            . $canonical_transcript->stable_id;

        $data{gene_id} = $self->external_gene_id( $gene, 'HGNC' );
    }
    elsif ( $self->species eq 'Mouse' ) {
        $data{gene_link} = 'http://www.ensembl.org/Mus_musculus/Gene/Summary?g='
            . $gene->stable_id;
        $data{transcript_link} = 'http://www.ensembl.org/Mus_musculus/Transcript/Summary?t='
            . $canonical_transcript->stable_id;

        $data{gene_id} = $self->external_gene_id( $gene, 'MGI' );
    }
    $data{marker_symbol} = $gene->external_name;
    $data{canonical_transcript} = $canonical_transcript->stable_id;

    $data{strand} = $gene->strand;
    $data{chr} = $gene->seq_region_name;

    return \%data;
}

=head2 external_gene_id

Work out external gene id:
Human = HGNC
Mouse = MGI

If I have multiple ids pick the first one.
If I can not find a id go back to marker symbol.

=cut
sub external_gene_id {
    my ( $self, $gene, $type ) = @_;

    my @dbentries = @{ $gene->get_all_DBEntries( $type ) };
    my @ids = uniq map{ $_->primary_id } @dbentries;

    if ( @ids ) {
        my $id = shift @ids;
        $id = 'HGNC:' . $id if $type eq 'HGNC';
        return $id;
    }
    else {
        # return marker symbol
        return $gene->external_name;
    }

    return;
}

=head2 build_gene_exon_data

Grab genes from given exon and build up a hash of
data to display

=cut
sub build_gene_exon_data {
    my ( $self, $gene, $gene_id, $exon_types ) = @_;

    my $canonical_transcript = $gene->canonical_transcript;
    my $exons = $exon_types eq 'canonical' ? $canonical_transcript->get_all_Exons : $gene->get_all_Exons;

    my %exon_data;
    for my $exon ( @{ $exons } ) {
        my %data;
        $data{id} = $exon->stable_id;
        $data{size} = $exon->length;
        $data{chr} = $exon->seq_region_name;
        $data{start} = $exon->start;
        $data{end} = $exon->end;
        $data{start_phase} = $exon->phase;
        $data{end_phase} = $exon->end_phase;
        #TODO this may not be expected data sp12 Tue 03 Dec 2013 11:16:27 GMT
        #     not clear what constitutive means to Ensembl
        $data{constitutive} = $exon->is_constitutive ? 'yes' : 'no';

        $exon_data{ $exon->stable_id } = \%data;
    }
    $self->exon_ranks( \%exon_data, $canonical_transcript );

    if ( $gene->strand == 1 ) {
        return [ sort { $a->{start} <=> $b->{start} } values %exon_data ];
    }
    else {
        return [ sort { $b->{start} <=> $a->{start} } values %exon_data ];
    }

    return;
}

=head2 exon_ranks

Get rank of exons on canonical transcript.
If exon not on canonical transcript rank is left blank for now.

=cut
sub exon_ranks {
    my ( $self, $exons, $canonical_transcript ) = @_;

    my $rank = 1;
    for my $current_exon ( @{ $canonical_transcript->get_all_Exons } ) {
        my $current_id = $current_exon->stable_id;
        if ( exists $exons->{ $current_id } ) {
            $exons->{ $current_id }{rank} = $rank;
        }
        $rank++;
    }

    return;
}

1;

__END__
