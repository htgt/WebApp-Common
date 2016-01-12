package WebAppCommon::Design::CreateInterface;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Design::CreateInterface::VERSION = '0.050';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Moose::Role;
use Data::UUID;
use JSON;
use Hash::MoreUtils qw( slice_def );
use WebAppCommon::Util::FarmJobRunner;
use DesignCreate::Constants qw( $PRIMER3_CONFIG_FILE );
use YAML::Any qw( LoadFile );
use String::ShellQuote;

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
    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_target_params_from_exons );

    my %target_data;
    $target_data{gene_id} = $validated_params->{gene_id};
    $target_data{ensembl_gene_id} = $validated_params->{ensembl_gene_id};

    $self->log->info( 'Calculating target coordinates for exon(s)' );
    my $exon_adaptor = $self->ensembl_util->exon_adaptor;
    my $five_prime_exon = $exon_adaptor->fetch_by_stable_id( $validated_params->{five_prime_exon} );
    $target_data{chr_name} = $five_prime_exon->seq_region_name;
    $target_data{chr_strand} = $five_prime_exon->strand;

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

=head2 c_exon_target_data

Gather data required to target exon if user enters ensemble exon id
to target directly.

=cut
sub c_exon_target_data {
    my ( $self, $exon_id ) = @_;

    my $gene = $self->ensembl_util->get_gene_from_exon_id( $exon_id );
    die "Could not get gene for $exon_id" unless $gene;

    my $gene_type_id = $self->species eq 'Human' ? 'HGNC'
                     : $self->species eq 'Mouse' ? 'MGI'
                     :                              undef;
    return {
        gene_id         => $self->ensembl_util->external_gene_id( $gene, $gene_type_id ),
        ensembl_gene_id => $gene->stable_id,
        marker_symbol   => $gene->external_name,
    }
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

sub pspec_common_design_params {
    return {
        gene_id     => { validate => 'non_empty_string' },
        target_type => { validate => 'non_empty_string' },
        design_type => { validate => 'non_empty_string' },
        # fields from the diagram
        region_length_5F => { validate => 'integer' },
        region_offset_5F => { validate => 'integer' },
        region_length_3R => { validate => 'integer' },
        region_offset_3R => { validate => 'integer' },
        # conditional
        region_length_5R_EF => { validate => 'integer', optional => 1 },
        region_offset_5R_EF => { validate => 'integer', optional => 1 },
        region_length_ER_3F => { validate => 'integer', optional => 1 },
        region_offset_ER_3F => { validate => 'integer', optional => 1 },
        # deletion
        region_length_5R => { validate => 'integer', optional => 1 },
        region_offset_5R => { validate => 'integer', optional => 1 },
        region_length_3F => { validate => 'integer', optional => 1 },
        region_offset_3F => { validate => 'integer', optional => 1 },


        # advanced options
        repeat_mask_class       => { validate => 'repeat_mask_class', optional => 1 },
        alt_designs             => { validate => 'boolean', optional => 1 },
        max_primer_genomic_hits => { validate => 'integer', optional => 1 },
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

sub pspec_fusion_design_params {
    return {
        gene_id     => { validate => 'non_empty_string' },
        target_type => { validate => 'non_empty_string' },
        design_type => { validate => 'non_empty_string' },
        # fusion
        region_length_U5 => { validate => 'integer', optional => 1 },
        region_offset_U5 => { validate => 'integer', optional => 1 },
        region_length_D3 => { validate => 'integer', optional => 1 },
        region_offset_D3 => { validate => 'integer', optional => 1 },
        region_length_f5F => { validate => 'integer', optional => 1 },
        region_offset_f5F => { validate => 'integer', optional => 1 },
        region_length_f3R => { validate => 'integer', optional => 1 },
        region_offset_f3R => { validate => 'integer', optional => 1 },
        # advanced options
        repeat_mask_class       => { validate => 'repeat_mask_class', optional => 1 },
        alt_designs             => { validate => 'boolean', optional => 1 },
        max_primer_genomic_hits => { validate => 'integer', optional => 1 },
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

sub pspec_parse_and_validate_exon_target_design_params {
    my $self = shift;
    my $common_gibson_params;
    if ($self->catalyst->stash->{design_type} eq 'fusion-deletion') {
        $common_gibson_params = $self->pspec_fusion_design_params;
    } else {
        $common_gibson_params = $self->pspec_common_design_params;
    }
    return {
        five_prime_exon         => { validate => 'ensembl_exon_id' },
        three_prime_exon        => { validate => 'ensembl_exon_id', optional => 1 },
        ensembl_gene_id         => { validate => 'ensembl_gene_id', optional => 1 },
        exon_check_flank_length => { validate => 'integer', optional => 1 },
        %{ $common_gibson_params },
    };
}

=head2 c_parse_and_validate_exon_target_design_params

Check the parameters needed to create the gibson design are all present
and valid.

=cut
sub c_parse_and_validate_exon_target_design_params {
    my ( $self ) = @_;

    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_parse_and_validate_exon_target_design_params );

    $self->common_design_param_validation( $validated_params );

    $self->catalyst->stash( {
        gene_id          => $validated_params->{gene_id},
        five_prime_exon  => $validated_params->{five_prime_exon},
        three_prime_exon => $validated_params->{three_prime_exon},
    } );
    $self->log->info( 'Validated exon target gibson design parameters' );

    return $validated_params;
}

sub pspec_parse_and_validate_custom_target_design_params {
    my $self = shift;
    my $common_design_params;
    if ($self->catalyst->stash->{design_type}  eq 'fusion-deletion') {
        $common_design_params = $self->pspec_fusion_design_params;
    } else {
        $common_design_params = $self->pspec_common_design_params;
    }
    return {
        target_start    => { validate => 'integer' },
        target_end      => { validate => 'integer' },
        chr_name        => { validate => 'existing_chromosome' },
        chr_strand      => { validate => 'strand' },
        ensembl_gene_id => { validate => 'ensembl_gene_id', optional => 1 },
        %{ $common_design_params },
    };
}

=head2 c_parse_and_validate_custom_target_design_params

Check the parameters needed to create the gibson design are all present
and valid.

=cut
sub c_parse_and_validate_custom_target_design_params {
    my ( $self ) = @_;

    my $validated_params = $self->check_params(
        $self->catalyst->request->params, $self->pspec_parse_and_validate_custom_target_design_params );

    $self->common_design_param_validation( $validated_params );

    $self->catalyst->stash( {
        gene_id      => $validated_params->{gene_id},
        target_start => $validated_params->{target_start},
        target_end   => $validated_params->{target_end},
        chromosome   => $validated_params->{chromosome},
        strand       => $validated_params->{strand},
    } );
    $self->log->info( 'Validated custom target design parameters' );

    return $validated_params;
}

=head2 common_gibson_param_validation

Common code for gibson design parameter validation
and setup of gibson design.

=cut
sub common_design_param_validation {
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
            $errors .= "Primer minimum $type value ($min) can not be greater than maximum $type value ($max)\n";
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
    #$vp->{output_dir}->mkpath();

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
            'command-name' => $self->calculate_design_cmd( $params ),
            slice_def $params,
            grep { $_ ne 'output_dir' } keys %{ $params }
        }
    );
    #repeat_mask_class

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

=head2 c_generate_design_cmd

generate the gibson design create command with all its parameters

=cut
sub c_generate_design_cmd {
    my ( $self, $params ) = @_;

    # common gibson design parameters
    my @design_cmd_parameters = (
        '--debug',
        #required parameters
        '--created-by',  shell_quote( $params->{user} ),
        '--target-gene', shell_quote( $params->{gene_id} ),
        '--species',     $params->{species},
        '--dir',         $params->{output_dir}->subdir('workdir')->stringify,
        '--da-id',       $params->{da_id},

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

    my $design_cmd = $self->calculate_design_cmd( $params );
    # gibson design type specific parameters
    if ( $params->{design_type} eq 'gibson-conditional' ) {
        push @design_cmd_parameters, (
            '--region-length-5r-ef', $params->{region_length_5R_EF},
            '--region-offset-5r-ef', $params->{region_offset_5R_EF},
            '--region-length-er-3f', $params->{region_length_ER_3F},
            '--region-offset-er-3f', $params->{region_offset_ER_3F},
            '--region-length-5f',    $params->{region_length_5F},
            '--region-offset-5f',    $params->{region_offset_5F},
            '--region-length-3r',    $params->{region_length_3R},
            '--region-offset-3r',    $params->{region_offset_3R},
        );
    }
    elsif ( $params->{design_type} eq 'gibson-deletion' ) {
        push @design_cmd_parameters, (
            '--region-length-5r',   $params->{region_length_5R},
            '--region-offset-5r',   $params->{region_offset_5R},
            '--region-length-3f',   $params->{region_length_3F},
            '--region-offset-3f',   $params->{region_offset_3F},
            '--region-length-5f',   $params->{region_length_5F},
            '--region-offset-5f',   $params->{region_offset_5F},
            '--region-length-3r',   $params->{region_length_3R},
            '--region-offset-3r',   $params->{region_offset_3R},
        );
    }
    #fusion added
    elsif ( $params->{design_type} eq 'fusion-deletion' ) {
        push @design_cmd_parameters, (
            '--region-length-f5f',  $params->{region_length_f5F},
            '--region-offset-f5f',  $params->{region_offset_f5F},
            '--region-length-d3',   $params->{region_length_D3},
            '--region-offset-d3',   $params->{region_offset_D3},
            '--region-length-u5',   $params->{region_length_U5},
            '--region-offset-u5',   $params->{region_offset_U5},
            '--region-length-f3r',  $params->{region_length_f3R},
            '--region-offset-f3r',  $params->{region_offset_f3R},
        );
    }
    else {
        die( 'Unknown design type: ' . $params->{design_type} );
    }

    # target type specific parameters
    if ( $params->{target_type} eq 'exon' ) {
        push @design_cmd_parameters, (
            '--five-prime-exon' , $params->{five_prime_exon},
        );
        if( $params->{three_prime_exon} ) {
            push @design_cmd_parameters, (
                '--three-prime-exon', $params->{three_prime_exon},
            );
        }
    }
    elsif ( $params->{target_type} eq 'location' ) {
        push @design_cmd_parameters, (
            '--target-start', $params->{target_start},
            '--target-end'  , $params->{target_end},
            '--chromosome'  , $params->{chr_name},
            '--strand'      , $params->{chr_strand},
        );
    }
    else {
        die( 'Unknown design target type: ' . $params->{target_type} );
    }

    # put command name in front of other parameters
    unshift @design_cmd_parameters, (
        'design-create',
        $design_cmd,
    );

    if ( $params->{repeat_mask_class} ) {
        if ( ref( $params->{repeat_mask_class} ) eq 'ARRAY' ) {
            for my $class ( @{ $params->{repeat_mask_class} } ) {
                push @design_cmd_parameters, '--repeat-mask-class ' . $class;
            }
        }
        else {
            push @design_cmd_parameters, '--repeat-mask-class ' . $params->{repeat_mask_class};
        }
    }

    if ( $params->{alt_designs} ) {
        push @design_cmd_parameters, '--alt-designs';
    }

    if ( $params->{exon_check_flank_length} ) {
        push @design_cmd_parameters,
            '--exon-check-flank-length ' . $params->{exon_check_flank_length};
    }

    if ( $params->{max_primer_genomic_hits} ) {
        push @design_cmd_parameters,
            '--num-genomic-hits ' . $params->{max_primer_genomic_hits};
    }
    $self->log->debug('Design create command: ' . join(' ', @design_cmd_parameters ) );

    return \@design_cmd_parameters;
}

=head2 calculate_design_cmd

Calculate the cmd needed to generate the gibson design.

=cut
sub calculate_design_cmd {
    my ( $self, $params ) = @_;
    my $design_cmd;
    if ( $params->{design_type} eq 'gibson-conditional' ) {
        $design_cmd = 'gibson-design';
    }
    elsif ( $params->{design_type} eq 'gibson-deletion' ) {
        $design_cmd = 'gibson-deletion-design';
    }
    #fusion addition
    elsif ( $params->{design_type} eq 'fusion-deletion' ) {
        $design_cmd = 'fusion-deletion-design';
    }
    #End of 
    else {
        die( 'Unknown gibson design type: ' . $params->{design_type} );
    }

    if ( $params->{target_type} eq 'exon' ) {
        $design_cmd .= '-exon';
    }
    elsif ( $params->{target_type} eq 'location' ) {
        $design_cmd .= '-location';
    }
    else {
        die( 'Unknown gibson target type: ' . $params->{target_type} );
    }

    return $design_cmd;
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

    $self->log->info( "Successfully submitted design create job $job_id with run id $params->{uuid}" );

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

# TODO remove ( move to the Validated object itself, in LIMS2 and WGE )
=head2 c_format_validation_errors

Format LIMS2::Exception::Validation / WGE::Expection::Validation errors
to display clear message to users about which of the parameters they
entered failed the validation tests.

=cut
sub c_format_validation_errors {
    my ( $self, $err ) = @_;
    my $errors;
    my $params = $err->params;
    my $validation_results = $err->results;
    if ( defined $validation_results ) {
        if ( $validation_results->has_missing ) {
            $errors .= "Missing following required parameters:\n";
            for my $m ( $validation_results->missing ) {
                $errors .= "  * $m\n" ;
            }
            $errors .= "\n";
        }

        if ( $validation_results->has_invalid ) {
            $errors .= "Following parameters are invalid:\n";
            for my $f ( $validation_results->invalid ) {
                my $cur_val = exists $params->{$f} ? $params->{$f} : '';
                $errors .= "  * $f = $cur_val " . '( failed '
                        . join( q{,}, @{ $validation_results->invalid($f) } ) . " check )\n";
            }
        }
    }
    else {
        $errors = "Error with parameters:\n" . $err->message;
    }

    return $errors;
}

=head2 c_redo_design_attempt

Setup parameters to redo a design from the data gathered from a previous design attempt.

=cut
sub c_redo_design_attempt {
    my ( $self, $da ) = @_;
    my %redo_data;

    my $da_data = $da->as_hash( { json_as_hash => 1 } );
    my $params = $da_data->{design_parameters};
    die('No design parameters set') unless keys %{ $params };

    my $command_name = $params->{'command-name'};
    die('No command name set') unless $command_name;

    if ( $command_name =~ /location/ ) {
        $self->_redo_location_target_params( \%redo_data, $params );
    }
    elsif ( $command_name =~ /exon/ ) {
        $self->_redo_exon_target_params( \%redo_data, $params );
    }
    else {
        die( "Can not work out design target type for cmd: $command_name" );
    }
    if ( $command_name eq 'gibson-deletion-design-exon' || $command_name eq 'gibson-deletion-design-location' ) {
        $self->_redo_gibson_deletion_params( \%redo_data, $params );
    }
    elsif ( $command_name eq 'gibson-design-exon' || $command_name eq 'gibson-design-location' ) {
        $self->_redo_gibson_conditional_params( \%redo_data, $params );
    }
    #fusion added
    elsif ( $command_name eq 'fusion-deletion-design-exon' || $command_name eq 'fusion-deletion-design-location' ) {
        $self->_redo_fusion_deletion_params( \%redo_data, $params );
    }
    #End of
    else {
        die( "Can not work out gibson design type from cmd: $command_name" );
    }

    $self->_redo_common_design_params( \%redo_data, $params, $da_data );

    $self->catalyst->stash( %redo_data );
    return $redo_data{target_type};
}

=head2 _redo_location_target_params

Store redo parameters specific to gibson designs that have a custom location target.

=cut
sub _redo_location_target_params {
    my ( $self, $redo_data, $params  ) = @_;

    my @not_set;
    for my $name ( qw( target_start target_end chr_name chr_strand ) ) {
        push @not_set, $name unless $params->{$name};
    }
    die ('Following parameters not set: ' . join(',', @not_set)) if @not_set;

    $redo_data->{target_type}  = 'location';
    $redo_data->{target_start} = $params->{target_start};
    $redo_data->{target_end}   = $params->{target_end};
    $redo_data->{chr_name}     = $params->{chr_name};
    $redo_data->{chr_strand}   = $params->{chr_strand};

    return;
}

=head2 _redo_exon_target_params

Store redo parameters specific to gibson designs that target exon(s).

=cut
sub _redo_exon_target_params {
    my ( $self, $redo_data, $params ) = @_;

    die ('No exon target set') unless $params->{five_prime_exon};
    $redo_data->{target_type}      = 'exon';
    $redo_data->{five_prime_exon}  = $params->{five_prime_exon};
    $redo_data->{three_prime_exon} = $params->{three_prime_exon} if exists $params->{three_prime_exon};
    $redo_data->{exon_check_flank_length} = $params->{exon_check_flank_length}
        if exists $params->{exon_check_flank_length};

    return;
}

=head2 _redo_gibson_deletion_params

Store redo parameters specific to deletion gibson designs.

=cut
sub _redo_gibson_deletion_params {
    my ( $self, $redo_data, $params ) = @_;

    $redo_data->{gibson_type} = 'deletion';
    for my $name ( qw( region_length_5R region_offset_5R region_length_3F region_offset_3F ) ) {
        $redo_data->{$name} = $params->{$name} if exists $params->{$name};
    }

    return;
}

=head2 _redo_gibson_conditional_params

Store redo parameters specific to conditional gibson designs.

=cut
sub _redo_gibson_conditional_params {
    my ( $self, $redo_data, $params ) = @_;

    $redo_data->{gibson_type} = 'conditional';
    for my $name ( qw( region_length_5R_EF region_offset_5R_EF region_length_ER_3F region_offset_ER_3F ) ) {
        $redo_data->{$name} = $params->{$name} if exists $params->{$name};
    }

    return;
}

#fusion added
sub _redo_fusion_deletion_params {
    my ( $self, $redo_data, $params ) = @_;

    $redo_data->{gibson_type} = 'fusion-deletion';
    for my $name ( qw( region_length_U5 region_offset_U5 region_length_D3 region_offset_D3 ) ) {
        $redo_data->{$name} = $params->{$name} if exists $params->{$name};
    }

    return;
}
#End of
=head2 _redo_common_gibson_params

Store redo parameters specific common to all gibson designs.

=cut
sub _redo_common_design_params {
    my ( $self, $redo_data, $params, $da_data ) = @_;

    die ('No gene_id set for design attempt') unless $da_data->{gene_id};

    $redo_data->{gene_id} = $da_data->{gene_id};
    $redo_data->{fail} = $da_data->{fail} if $da_data->{fail};

    # common region parameters
    for my $name ( qw( region_length_5F region_offset_5F region_length_3R region_offset_3R ) ) {
        $redo_data->{$name} = $params->{$name} if exists $params->{$name};
    }

    $redo_data->{repeat_mask_class} = $params->{repeat_mask_class} if exists $params->{repeat_mask_class};
    $redo_data->{max_primer_genomic_hits} = $params->{max_primer_genomic_hits}
        if exists $params->{max_primer_genomic_hits};

    # Primer3 parameters
    for my $name (
        qw( primer_min_size primer_max_size primer_opt_size primer_opt_gc_percent
        primer_max_gc primer_min_gc primer_opt_tm primer_max_tm primer_min_tm )
    )
    {
        $redo_data->{$name} = $params->{$name} if exists $params->{$name};
    }

    return;
}


1;

__END__
