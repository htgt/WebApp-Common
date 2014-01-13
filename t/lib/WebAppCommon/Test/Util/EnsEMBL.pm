package WebAppCommon::Test::Util::EnsEMBL;

use strict;
use warnings FATAL => 'all';

use Test::Most;
use base qw( WebAppCommon::Test::Class );

BEGIN {
    __PACKAGE__->mk_classdata( 'class' => 'WebAppCommon::Util::EnsEMBL' );
}

sub startup : Tests(startup => 5) {
    my $test = shift;

    my $class = $test->class;
    use_ok $class;
    can_ok $class, 'new';
    ok my $o = $class->new( species => 'mouse' ), 'constructor works';
    isa_ok $o, $class;

    is $o->species, 'mouse', 'species is mouse';

    $test->{o} = $o;
};

sub adaptors : Test(13) {
    my $test = shift;

    ok my $o = $test->{o}, 'can grab test object';

    note( 'Check all adaptors are present' );

    can_ok $o, 'gene_adaptor';
    isa_ok $o->gene_adaptor, 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

    can_ok $o, 'exon_adaptor';
    isa_ok $o->exon_adaptor, 'Bio::EnsEMBL::DBSQL::ExonAdaptor';

    can_ok $o, 'transcript_adaptor';
    isa_ok $o->transcript_adaptor, 'Bio::EnsEMBL::DBSQL::TranscriptAdaptor';

    can_ok $o, 'slice_adaptor';
    isa_ok $o->slice_adaptor, 'Bio::EnsEMBL::DBSQL::SliceAdaptor';

    can_ok $o, 'db_adaptor';
    isa_ok $o->db_adaptor, 'Bio::EnsEMBL::DBSQL::DBAdaptor';

    can_ok $o, 'repeat_feature_adaptor';
    isa_ok $o->repeat_feature_adaptor, 'Bio::EnsEMBL::DBSQL::RepeatFeatureAdaptor';

}

sub get_best_transcript : Tests(4) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $gene = $o->gene_adaptor->fetch_by_stable_id( 'ENSMUSG00000024617' ), 'can fetch gene';
    isa_ok $gene, 'Bio::EnsEMBL::Gene';
    is $o->get_best_transcript( $gene )->stable_id, 'ENSMUST00000025519', 'transcript is correct';
}

sub get_exon_rank : Tests(5) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $transcript = $o->transcript_adaptor->fetch_by_stable_id('ENSMUST00000025519'),
        'can fetch transcript';
    isa_ok $transcript, 'Bio::EnsEMBL::Transcript';
    is $o->get_exon_rank( $transcript, 'ENSMUSE00001248376' ), 1, 'first exon rank correct';
    is $o->get_exon_rank( $transcript, 'ENSMUSE00000572374' ), 5, 'fifth exon rank correct';
}

sub get_gene_from_exon_id : Tests(2) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    is $o->get_gene_from_exon_id('ENSMUSE00000572374')->stable_id, 'ENSMUSG00000024617',
        'gene is correct';
}

sub get_ensembl_gene : Tests(16) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $marker_symbol_gene = $o->get_ensembl_gene( 'Cbx1' ), 'can find gene by marker symbol';
    isa_ok $marker_symbol_gene, 'Bio::EnsEMBL::Gene';
    is $marker_symbol_gene->stable_id, 'ENSMUSG00000018666', '.. gene object has correct ensembl stable id';

    ok my $mgi_gene = $o->get_ensembl_gene( 'MGI:97490' ), 'can find gene by MGI gene id';
    isa_ok $mgi_gene, 'Bio::EnsEMBL::Gene';
    is $mgi_gene->stable_id, 'ENSMUSG00000027168', '.. gene object has correct ensembl stable id';

    ok my $human_o = $test->class->new( species => 'human' ), 'grab object with species set as human';
    ok my $hgnc_gene = $human_o->get_ensembl_gene( 'HGNC:1551' ), 'can find gene by HGNC gene id';
    isa_ok $hgnc_gene, 'Bio::EnsEMBL::Gene';
    is $hgnc_gene->stable_id, 'ENSG00000108468', '.. gene object has correct ensembl stable id';

    ok my $ensembl_gene = $human_o->get_ensembl_gene( 'ENSG00000139618'), 'can find gene by ensembl gene id';
    isa_ok $ensembl_gene, 'Bio::EnsEMBL::Gene';
    is $ensembl_gene->stable_id, 'ENSG00000139618', '.. gene object has correct ensembl stable id';

    throws_ok{
        $o->get_ensembl_gene( 'xxxxxxxxx' )
    } qr/Unable to find gene x+ in EnsEMBL/
        , 'throws error for unknown gene';

    throws_ok{
        $o->get_ensembl_gene( 'cb' )
    } qr/Found multiple EnsEMBL genes with marker symbol id cb/
        , 'throws error for multiple matching genes';
}

sub external_gene_id : Tests(8) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $mouse_gene = $o->gene_adaptor->fetch_by_stable_id('ENSMUSG00000018666'), 'can fetch gene';
    ok my $mouse_gene_id = $o->external_gene_id( $mouse_gene, 'MGI' ),
        'can grab MGI id from ensembl gene object';
    is $mouse_gene_id, 'MGI:105369';

    ok my $human_o = $test->class->new( species => 'human' ), 'grab object with species set as human';
    ok my $human_gene = $human_o->gene_adaptor->fetch_by_stable_id( 'ENSG00000108468' ), 'can fetch gene';
    ok my $human_gene_id = $human_o->external_gene_id( $human_gene, 'HGNC' ),
        'can grab HGNC id from ensembl gene object';
    is $human_gene_id, 'HGNC:1551';

}

1;

__END__
