package WebAppCommon::Test::Util::EnsEMBL;

use strict;
use warnings FATAL => 'all';

use Test::Most;
use base qw( WebAppCommon::Test::Class );

BEGIN {
    __PACKAGE__->mk_classdata( 'class' => 'WebAppCommon::Util::EnsEMBL' );
}

sub startup : Test(startup => 5) {
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

sub get_best_transcript : Test(4) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $gene = $o->gene_adaptor->fetch_by_stable_id( 'ENSMUSG00000024617' ), 'can fetch gene';
    isa_ok $gene, 'Bio::EnsEMBL::Gene';
    is $o->get_best_transcript( $gene )->stable_id, 'ENSMUST00000025519', 'transcript is correct';
}

sub get_exon_rank : Test(5) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    ok my $transcript = $o->transcript_adaptor->fetch_by_stable_id('ENSMUST00000025519'),
        'can fetch transcript';
    isa_ok $transcript, 'Bio::EnsEMBL::Transcript';
    is $o->get_exon_rank( $transcript, 'ENSMUSE00001248376' ), 1, 'first exon rank correct';
    is $o->get_exon_rank( $transcript, 'ENSMUSE00000572374' ), 5, 'fifth exon rank correct';
}

sub get_gene_from_exon_id : Test(2) {
    my $test = shift;
    ok my $o = $test->{o}, 'can grab test object';

    is $o->get_gene_from_exon_id('ENSMUSE00000572374')->stable_id, 'ENSMUSG00000024617',
        'gene is correct';
}

1;

__END__
