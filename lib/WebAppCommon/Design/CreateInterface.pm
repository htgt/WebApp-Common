package WebAppCommon::Design::CreateInterface;

use strict;
use warnings FATAL => 'all';

use Moose::Role;
use Data::UUID;
use JSON;
use Hash::MoreUtils qw( slice_def );
use WebAppCommon::Util::FarmJobRunner;
use DesignCreate::Constants qw( $PRIMER3_CONFIG_FILE );
use YAML::Any qw( LoadFile );

requires qw(
species
ensembl_util
check_params
create_design_attempt
user
assembly_id
build_id
base_design_dir
);

=head2 c_build_gene_data

Build up data about targeted gene to display to user.

=cut
sub c_build_gene_data {
    my ( $self, $gene ) = @_;
    my %data;

    my $canonical_transcript = $gene->canonical_transcript;
    $data{ensembl_id} = $gene->stable_id;
    if ( $self->species eq 'Human' ) {
        $data{gene_link} = 'http://www.ensembl.org/Homo_sapiens/Gene/Summary?g='
            . $gene->stable_id;
        $data{transcript_link} = 'http://www.ensembl.org/Homo_sapiens/Transcript/Summary?t='
            . $canonical_transcript->stable_id;

        $data{gene_id} = $self->ensembl_util->external_gene_id( $gene, 'HGNC' );
    }
    elsif ( $self->species eq 'Mouse' ) {
        $data{gene_link} = 'http://www.ensembl.org/Mus_musculus/Gene/Summary?g='
            . $gene->stable_id;
        $data{transcript_link} = 'http://www.ensembl.org/Mus_musculus/Transcript/Summary?t='
            . $canonical_transcript->stable_id;

        $data{gene_id} = $self->ensembl_util->external_gene_id( $gene, 'MGI' );
    }
    $data{marker_symbol} = $gene->external_name;
    $data{canonical_transcript} = $canonical_transcript->stable_id;

    $data{strand} = $gene->strand;
    $data{chr} = $gene->seq_region_name;

    return \%data;
}

=head2 c_build_gene_exon_data

Grab genes from given exon and build up a hash of
data to display

=cut
sub c_build_gene_exon_data {
    my ( $self, $gene, $gene_id, $exon_types ) = @_;

    my $canonical_transcript = $gene->canonical_transcript;
    my $exons = $exon_types eq 'canonical' ? $canonical_transcript->get_all_Exons : $gene->get_all_Exons;

    my %exon_data;
    for my $exon ( @{ $exons } ) {
        my %data;
        $data{id}          = $exon->stable_id;
        $data{size}        = $exon->length;
        $data{chr}         = $exon->seq_region_name;
        $data{start}       = $exon->start;
        $data{end}         = $exon->end;
        $data{start_phase} = $exon->phase;
        $data{end_phase}   = $exon->end_phase;
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

sub pspec_target_params_from_exons {
    return {
        gene_id           => { validate => 'non_empty_string' },
        ensembl_gene_id   => { validate => 'ensembl_gene_id', optional => 1 },
        five_prime_exon   => { validate => 'ensembl_exon_id' },
        three_prime_exon  => { validate => 'ensembl_exon_id', optional => 1 },
        target_from_exons => { optional => 1 },
    };
}

=head2 c_target_params_from_exons

Given target exons return target coordinates

=cut
sub c_target_params_from_exons {
    my ( $self ) = @_;
use Smart::Comments;
    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_target_params_from_exons );

    my %target_data;
    $target_data{gene_id} = $validated_params->{gene_id};
    $target_data{ensembl_gene_id} = $validated_params->{ensembl_gene_id};

    $self->log->info( 'Calculating target coordinates for exon(s)' );
    my $exon_adaptor = $self->ensembl_util->exon_adaptor;
    my $five_prime_exon = $exon_adaptor->fetch_by_stable_id( $validated_params->{five_prime_exon} );
    $target_data{chromosome} = $five_prime_exon->seq_region_name;
    $target_data{strand} = $five_prime_exon->strand;

    my $three_prime_exon;
    if ( $validated_params->{three_prime_exon} ) {
        $three_prime_exon = $exon_adaptor->fetch_by_stable_id( $validated_params->{three_prime_exon} );
    }
    # if there is no three prime exon then just specify target start and end
    # as the start and end of the five prime exon
    unless ( $three_prime_exon ) {
        $target_data{target_start} = $five_prime_exon->seq_region_start;
        $target_data{target_end} = $five_prime_exon->seq_region_end;
        return \%target_data;
    }

    if ( $target_data{strand} == 1 ) {
        $target_data{target_start} = $five_prime_exon->seq_region_start;
        $target_data{target_end}   = $three_prime_exon->seq_region_end;
    }
    else {
        $target_data{target_start} = $three_prime_exon->seq_region_start;
        $target_data{target_end}   = $five_prime_exon->seq_region_end;
    }

    return \%target_data;
}

=head2 c_primer3_default_config

The default primer3 parameters for:
melting temp
GC percentage
primer size

=cut
sub c_primer3_default_config {
    my ( $self ) = @_;
    return LoadFile( $PRIMER3_CONFIG_FILE );
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

sub pspec_common_gibson_params {
    return {
        gene_id      => { validate => 'non_empty_string' },
        target_type  => { validate => 'non_empty_string' },
        gibson_type  => { validate => 'non_empty_string' },
        # fields from the diagram
        '5F_length'    => { validate => 'integer' },
        '5F_offset'    => { validate => 'integer' },
        '3R_length'    => { validate => 'integer' },
        '3R_offset'    => { validate => 'integer' },
        # conditional
        '5R_EF_length' => { validate => 'integer', optional => 1 },
        '5R_EF_offset' => { validate => 'integer', optional => 1 },
        'ER_3F_length' => { validate => 'integer', optional => 1 },
        'ER_3F_offset' => { validate => 'integer', optional => 1 },
        # deletion
        '5R_length'    => { validate => 'integer', optional => 1 },
        '5R_offset'    => { validate => 'integer', optional => 1 },
        '3F_length'    => { validate => 'integer', optional => 1 },
        '3F_offset'    => { validate => 'integer', optional => 1 },
        # advanced options
        repeat_mask_classes => { validate => 'repeat_mask_class', optional => 1 },
        alt_designs         => { validate => 'boolean', optional => 1 },
        # primer3 config
        primer_min_size       => { validate => 'integer' },
        primer_max_size       => { validate => 'integer' },
        primer_opt_size       => { validate => 'integer' },
        primer_opt_gc_percent => { validate => 'integer' },
        primer_max_gc         => { validate => 'integer' },
        primer_min_gc         => { validate => 'integer' },
        primer_opt_tm         => { validate => 'integer' },
        primer_max_tm         => { validate => 'integer' },
        primer_min_tm         => { validate => 'integer' },
        #submit
        create_design => { optional => 0 }
    }
}

sub pspec_parse_and_validate_exon_target_gibson_params {
    my $self = shift;
    my $common_gibson_params = $self->pspec_common_gibson_params;
    return {
        five_prime_exon         => { validate => 'ensembl_exon_id' },
        three_prime_exon        => { validate => 'ensembl_exon_id', optional => 1 },
        ensembl_gene_id         => { validate => 'ensembl_gene_id' },
        exon_check_flank_length => { validate => 'integer', optional => 1 },
        %{ $common_gibson_params },
    };
}

=head2 c_parse_and_validate_exon_target_gibson_params

Check the parameters needed to create the gibson design are all present
and valid.

=cut
sub c_parse_and_validate_exon_target_gibson_params {
    my ( $self ) = @_;

    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_parse_and_validate_exon_target_gibson_params );

    $self->common_gibson_param_validation( $validated_params );

    $self->catalyst->stash( {
        gene_id => $validated_params->{gene_id},
        five_prime_exon => $validated_params->{five_prime_exon},
        three_prime_exon => $validated_params->{three_prime_exon},
    } );
    $self->log->info( 'Validated exon target gibson design parameters' );

    return $validated_params;
}

sub pspec_parse_and_validate_custom_target_gibson_params {
    my $self = shift;
    my $common_gibson_params = $self->pspec_common_gibson_params;
    return {
        target_start    => { validate => 'integer' },
        target_end      => { validate => 'integer' },
        chromosome      => { validate => 'existing_chromosome' },
        strand          => { validate => 'strand' },
        ensembl_gene_id => { validate => 'ensembl_gene_id', optional => 1 },
        %{ $common_gibson_params },
    };
}

=head2 c_parse_and_validate_exon_target_gibson_params

Check the parameters needed to create the gibson design are all present
and valid.

=cut
sub c_parse_and_validate_custom_target_gibson_params {
    my ( $self ) = @_;

    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_parse_and_validate_custom_target_gibson_params );

    $self->common_gibson_param_validation( $validated_params );

    $self->catalyst->stash( {
        gene_id      => $validated_params->{gene_id},
        target_start => $validated_params->{target_start},
        target_end   => $validated_params->{target_end},
        chromosome   => $validated_params->{chromosome},
        strand       => $validated_params->{strand},
    } );
    $self->log->info( 'Validated custom target gibson design parameters' );

    return $validated_params;
}

=head2 common_gibson_param_validation

Common code for gibson design parameter validation
and setup of gibson design.

=cut
sub common_gibson_param_validation {
    my ( $self, $vp  ) = @_;

    # additional Primer3 parameter validation
    my $errors;
    # primer size can not be greater than 35 bases
    for my $name ( qw( primer_min_size  primer_opt_size  primer_max_size ) ) {
        if ( $vp->{$name} > 35 ) {
            $errors .= "$name can not be greater than 35\n";
        }
    }

    # gc content is a percentage, so should be between 0 and 100
    for my $name ( qw( primer_min_gc  primer_opt_gc_percent  primer_max_gc ) ) {
        if ( $vp->{$name} > 100 || $vp->{$name} < 0 ) {
            $errors .= "$name is a percentage gc content, must be between 0 and 100\n";
        }
    }

    # standardise value to make following easier to code, delete afterwards
    $vp->{primer_opt_gc} = $vp->{primer_opt_gc_percent};

    # for the tm, size and gc values following should always be true:
    # min < opt < max
    for my $type ( qw( gc size tm ) ) {
        my $min = $vp->{'primer_min_' . $type};
        my $opt = $vp->{'primer_opt_' . $type};
        my $max = $vp->{'primer_max_' . $type};
        if ( $min > $opt ) {
            $errors .= "Primer minimum $type value ($min) can not be greater than optimum $type value ($opt)\n";
        }

        if ( $min > $max ) {
            $errors .= "Primer minumum $type value ($min) can not be greater than maximum $type value ($max)\n";
        }

        if ( $opt > $max ) {
            $errors .= "Primer optimum $type value ($opt) can not be greater than maximum $type value ($max)\n";
        }
    }
    delete $vp->{primer_opt_gc};

    if ( $errors ) {
        $self->throw_validation_error( $errors );
    }

    my $uuid = Data::UUID->new->create_str;
    $vp->{uuid}        = $uuid;
    $vp->{output_dir}  = $self->base_design_dir->subdir( $uuid );
    $vp->{species}     = $self->species;
    $vp->{build_id}    = $self->build_id;
    $vp->{assembly_id} = $self->assembly_id;
    $vp->{user}        = $self->user;
    #create dir
    $vp->{output_dir}->mkpath();

    return $vp;
}

=head2 c_initiate_design_attempt

create design attempt record with status pending

=cut
sub c_initiate_design_attempt {
    my ( $self, $params ) = @_;

    # create design attempt record
    my $design_parameters = encode_json(
        {   dir => $params->{output_dir}->stringify,
            slice_def $params,
            qw( uuid gene_id exon_id ensembl_gene_id assembly_id build_id ),
        }
    );

    my $design_attempt = $self->create_design_attempt(
        {
            gene_id           => $params->{gene_id},
            status            => 'pending',
            created_by        => $self->user,
            species           => $self->species,
            design_parameters => $design_parameters,
        }
    );
    $params->{da_id} = $design_attempt->id;
    $self->log->info( 'Create design attempt: ' . $design_attempt->id );

    return $design_attempt;
}

=head2 c_generate_gibson_design_cmd

generate the gibson design create command with all its parameters

=cut
sub c_generate_gibson_design_cmd {
    my ( $self, $params ) = @_;

    # common gibson design parameters
    my @gibson_cmd_parameters = (
        '--debug',
        #required parameters
        '--created-by',  $params->{user},
        '--target-gene', $params->{gene_id},
        '--species',     $params->{species},
        '--dir',         $params->{output_dir}->subdir('workdir')->stringify,
        '--da-id',       $params->{da_id},
        #user specified params
        '--region-length-5f',    $params->{'5F_length'},
        '--region-offset-5f',    $params->{'5F_offset'},
        '--region-length-3r',    $params->{'3R_length'},
        '--region-offset-3r',    $params->{'3R_offset'},
        #primer3 config params
        '--primer-min-size',       $params->{primer_min_size},
        '--primer-max-size',       $params->{primer_max_size},
        '--primer-opt-size',       $params->{primer_opt_size},
        '--primer-opt-gc-percent', $params->{primer_opt_gc_percent},
        '--primer-max-gc',         $params->{primer_max_gc},
        '--primer-min-gc',         $params->{primer_min_gc},
        '--primer-opt-tm',         $params->{primer_opt_tm},
        '--primer-max-tm',         $params->{primer_max_tm},
        '--primer-min-tm',         $params->{primer_min_tm},
        '--persist',
    );

    my $gibson_cmd;
    # gibson design type specific parameters
    if ( $params->{gibson_type} eq 'conditional' ) {
        $gibson_cmd = 'gibson-design';
        push @gibson_cmd_parameters, (
            '--region-length-5r-ef', $params->{'5R_EF_length'},
            '--region-offset-5r-ef', $params->{'5R_EF_offset'},
            '--region-length-er-3f', $params->{'ER_3F_length'},
            '--region-offset-er-3f', $params->{'ER_3F_offset'},
        );
    }
    elsif ( $params->{gibson_type} eq 'deletion' ) {
        $gibson_cmd = 'gibson-deletion-design';
        push @gibson_cmd_parameters, (
            '--region-length-5r', $params->{'5R_length'},
            '--region-offset-5r', $params->{'5R_offset'},
            '--region-length-3f', $params->{'3F_length'},
            '--region-offset-3f', $params->{'3F_offset'},
        );
    }
    else {
        die( 'Unknown gibson design type: ' . $params->{gibson_type} );
    }

    # target type specific parameters
    if ( $params->{target_type} eq 'exon' ) {
        $gibson_cmd .= '-exon';
        push @gibson_cmd_parameters, (
            '--five-prime-exon' , $params->{five_prime_exon},
        );
        if( $params->{three_prime_exon} ) {
            push @gibson_cmd_parameters, (
                '--three-prime-exon', $params->{three_prime_exon},
            );
        }
    }
    elsif ( $params->{target_type} eq 'location' ) {
        $gibson_cmd .= '-location';
        push @gibson_cmd_parameters, (
            '--target-start', $params->{target_start},
            '--target-end'  , $params->{target_end},
            '--chromosome'  , $params->{chromosome},
            '--strand'      , $params->{strand},
        );
    }
    else {
        die( 'Unknown gibson target type: ' . $params->{target_type} );
    }

    # put command name in front of other parameters
    unshift @gibson_cmd_parameters, (
        'design-create',
        $gibson_cmd,
    );

    if ( $params->{repeat_mask_classes} ) {
        if ( ref( $params->{repeat_mask_classes} ) eq 'ARRAY' ) {
            for my $class ( @{ $params->{repeat_mask_classes} } ) {
                push @gibson_cmd_parameters, '--repeat-mask-class ' . $class;
            }
        }
        else {
            push @gibson_cmd_parameters, '--repeat-mask-class ' . $params->{repeat_mask_classes};
        }
    }

    if ( $params->{alt_designs} ) {
        push @gibson_cmd_parameters, '--alt-designs';
    }

    if ( $params->{exon_check_flank_length} ) {
        push @gibson_cmd_parameters,
            '--exon-check-flank-length ' . $params->{exon_check_flank_length};
    }

    $self->log->debug('Design create command: ' . join(' ', @gibson_cmd_parameters ) );

    return \@gibson_cmd_parameters;
}

=head2 c_run_design_create_cmd

Bsub the design create command in farm3

=cut
sub c_run_design_create_cmd {
    my ( $self, $cmd, $params ) = @_;

    my %farm_job_params = (
        default_memory     => 2500,
        default_processors => 2,
    );
    $farm_job_params{bsub_wrapper} = $ENV{FARM3_BSUB_WRAPPER} if exists $ENV{FARM3_BSUB_WRAPPER};
    my $runner = WebAppCommon::Util::FarmJobRunner->new( %farm_job_params );

    my $job_id = $runner->submit(
        out_file => $params->{ output_dir }->file( "design_creation.out" ),
        err_file => $params->{ output_dir }->file( "design_creation.err" ),
        cmd      => $cmd,
    );

    $self->log->info( "Successfully submitted gibson design create job $job_id with run id $params->{uuid}" );

    return $job_id;
}

=head2 throw_validation_error

Method to throw validation error, should be overridden in
the consuming object.

=cut
sub throw_validation_error {
    my ( $self, $errors  ) = @_;

    die( $errors );
}

1;

__END__
