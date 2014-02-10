package WebAppCommon::FormValidator::Constraint;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::FormValidator::Constraint::VERSION = '0.007';
}
## use critic


=head1 NAME

WebApp::FormValidator::Constraint

=head1 DESCRIPTION

Common constraints that can be used to check parameters passed to subroutines in LIMS2 and WGE.

=cut

use warnings FATAL => 'all';

use Moose;
use DateTime::Format::ISO8601;
use Try::Tiny;
use URI;
use Text::CSV;
use Const::Fast;
use JSON qw( decode_json );
use Scalar::Util qw( openhandle );
use namespace::autoclean;

has model => (
    is       => 'ro',
    required => 1,
);

# See http://www.postgresql.org/docs/9.0/static/datatype-numeric.html
const my $MIN_INT => -2147483648;
const my $MAX_INT =>  2147483647;

sub in_set {
    my $self = shift;
    my @args = @_;

    my $values;

    if ( @args == 1 and ref $args[0] eq 'ARRAY' ) {
        $values = $args[0];
    }
    else {
        $values = \@args;
    }

    my %is_in_set = map { $_ => 1 } @{$values};

    return sub {
        $is_in_set{ shift() };
    };
}

sub in_resultset {
    my ( $self, $resultset_name, $column_name ) = @_;
    return $self->in_set( [ map { $_->$column_name } $self->model->schema->resultset($resultset_name)->all ] );
}

sub existing_row {
    my ( $self, $resultset_name, $column_name ) = @_;

    return sub {
        my $value = shift;
        $self->model->schema->resultset($resultset_name)->search_rs( { $column_name => $value } )->count > 0;
    };
}

sub regexp_matches {
    my $self = shift;
    my $match = shift;
    return sub {
        shift =~ m/$match/;
    };
}

sub date_time {
    my $self = shift;
    return sub {
        my $str = shift;
        try {
            DateTime::Format::ISO8601->parse_datetime($str);
        };
    };
}

sub strand {
    return shift->in_set( 1, -1 );
}

sub phase {
    return shift->in_set( 0, 1, 2, -1 );
}

sub boolean_string {
    return shift->in_set( 'true', 'false' );
}

sub boolean {
    return shift->in_set( 0, 1 );
}

sub user_name {
    return shift->regexp_matches(qr/^\w+[\w\@\.\-\:]+$/);
}

sub integer {
    my $self = shift;
    return sub {
        my $val = shift;
        return $val =~ qr/^\d+$/ && $val >= $MIN_INT && $val <= $MAX_INT;
    }
}

sub alphanumeric_string {
    return shift->regexp_matches(qr/^\w+$/);
}

sub non_empty_string {
    return shift->regexp_matches(qr/\S+/);
}

sub string_min_length_3 {
    return shift->regexp_matches(qr/\S{3}/);
}

sub mgi_accession_id {
    return shift->regexp_matches(qr/^MGI:\d+$/);
}

sub ensembl_gene_id {
    return shift->regexp_matches(qr/^ENS[A-Z]*G\d+$/);
}

sub ensembl_transcript_id {
    return shift->regexp_matches(qr/^ENSMUST\d+$/);
}

sub ensembl_exon_id {
    return shift->regexp_matches(qr/^ENS[A-Z]*E\d+$/);
}

sub existing_species {
    return shift->in_resultset( 'Species', 'id' );
}

sub existing_assembly {
    return shift->in_resultset( 'Assembly', 'id' );
}

sub existing_chromosome {
    return shift->in_resultset( 'Chromosome', 'name' );
}

sub existing_design_type {
    return shift->in_resultset( 'DesignType', 'id' );
}

sub existing_design_comment_category {
    return shift->in_resultset( 'DesignCommentCategory', 'name' );
}

sub existing_design_id {
    return shift->in_resultset( 'Design', 'id' );
}

sub existing_design_oligo_type {
    return shift->in_resultset( 'DesignOligoType', 'id' );
}

sub existing_genotyping_primer_type {
    return shift->in_resultset( 'GenotypingPrimerType', 'id' );
}

sub existing_user {
    return shift->in_resultset( 'User', 'name' );
}

sub existing_role {
    return shift->in_resultset( 'Role', 'name' );
}

sub existing_crispr_loci_type {
    return shift->in_resultset( 'CrisprLociType', 'id' );
}

sub existing_crispr_id {
    return shift->in_resultset( 'Crispr', 'id' );
}

sub existing_gene_type {
	return shift->in_resultset( 'GeneType', 'id' );
}

sub comma_separated_list {
    my $self = shift;
    my $csv = Text::CSV->new;
    return sub {
        my $str = shift;
        $csv->parse($str);
    }
}

sub uuid {
    return shift->regexp_matches(qr/^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$/);
}

sub software_version {
    return shift->regexp_matches(qr/^\d+(\.\d+)*(?:_\d+)?$/);
}

sub json {
    my $self = shift;
    return sub {
        my $str = shift;
        try {
            decode_json($str);
            return 1;
        };
    };
}

sub absolute_url {
    my $self = shift;
    return sub {
        my $str = shift;
        return 0 unless defined $str and length $str;
        my $uri = try { URI->new( $str ) } catch { undef };
        return $uri && $uri->scheme && $uri->host && $uri->path;
    }
}

sub hashref {
    my $self = shift;
    return sub {
        ref $_[0] eq ref {};
    }
}

sub file_handle {
    my $self = shift;
    return sub {
        my $val = shift;
        my $fh = openhandle( $val );
        return $fh ? 1 : 0;
    }
}

sub pass_or_fail {
    return shift->regexp_matches(qr/^(pass|fail)$/i);
}

# at least 6 non whitespace characters long
sub password_string {
    return shift->regexp_matches(qr/^\S{6,}$/);
}

sub repeat_mask_class {
    return shift->in_set( 'trf', 'dust' );
}

sub validated_by_annotation {
    return shift->in_set( 'yes', 'no', 'maybe', 'not done' );
}

sub dna_seq {
    return shift->regexp_matches(qr/^[ATGCN]+$/);
}
__PACKAGE__->meta->make_immutable;

1;

__END__

