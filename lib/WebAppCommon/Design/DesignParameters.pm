package WebAppCommon::Design::DesignParameters;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Design::DesignParameters::VERSION = '0.074';
}
## use critic


use strict;
use warnings FATAL => 'all';
use WebAppCommon::Util::EnsEMBL;
use DesignCreate::CmdRole::OligoPairRegionsGibsonDel;
use Log::Log4perl qw( :easy );
use Data::Dumper;

use Sub::Exporter -setup => {
    exports => [
        qw(
            c_get_design_region_coords
            c_get_target_coords
            c_get_target_coords_from_exons
         )
    ]
};

# Specify the elements of any new design type here
# as viewed on the positive strand
# e.g. gibson-deletion : 5F----5R----target----3F----3R
my $DESIGN_ELEMENTS = {
    'gibson-deletion' => {
        'before_target' => [ qw(5F 5R) ],
        'after_target'  => [ qw(3F 3R) ],
    },
    'gibson-conditional' => {
        'before_target' => [ qw(5F 5R_EF) ],
        'after_target'  => [ qw(ER_3F 3R) ],
    },
    'fusion-deletion' => {
        'before_target' => [ qw(f5F U5) ],
        'after_target'  => [ qw(D3 f3R) ],
    },
};

sub c_get_design_region_coords{
	my ($params) = @_;

    my $design_params = {};

    my $target_coords = c_get_target_coords($params);
    my $region_coords = get_design_param_coordinates($target_coords,$params);

    $region_coords->{strand} = $target_coords->{strand};

    return $region_coords;
}

sub c_get_target_coords{
	my ($params, $ensembl_util) = @_;

    my $target_coords;
    if($params->{five_prime_exon}){
        $target_coords = c_get_target_coords_from_exons($params);
    }
    else{
    	# custom target params
    }

    return $target_coords;
}

sub c_get_target_coords_from_exons{
	my ($params, $ensembl_util) = @_;

	$ensembl_util ||= WebAppCommon::Util::EnsEMBL->new( species => $params->{species} );

	my %target_data;

    my $exon_adaptor = $ensembl_util->exon_adaptor;
    my $five_prime_exon = $exon_adaptor->fetch_by_stable_id( $params->{five_prime_exon} );
    $target_data{chr_name} = $five_prime_exon->seq_region_name;
    $target_data{strand} = $five_prime_exon->strand;

    my $three_prime_exon;
    if ( $params->{three_prime_exon} ) {
        $three_prime_exon = $exon_adaptor->fetch_by_stable_id( $params->{three_prime_exon} );
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

# FIXME: should try to reuse code from DesignCreate::CmdRole::OligoPairRegionsGibsonDel rather than
# reimplementing it here
sub get_design_param_coordinates{
    my ($target_coords, $params) = @_;

    my $design_type = $params->{design_type};

    my $elements_before_target = $DESIGN_ELEMENTS->{$design_type}->{'before_target'}; #e.g. (5F 5R);
    my $elements_after_target = $DESIGN_ELEMENTS->{$design_type}->{'after_target'}; #e.g. (3F 3R);

    my @region_list = (@$elements_before_target, 'target', @$elements_after_target);

    my $design_params = {
        region_list  => \@region_list,
        target_start => $target_coords->{target_start},
        target_end   => $target_coords->{target_end},
    };

    if($target_coords->{strand} == 1){
      my $previous_coord = 'target_start';
      foreach my $element (reverse @$elements_before_target){
          $design_params->{$element.'_end'}   = $design_params->{$previous_coord} - $params->{'region_offset_'.$element};
          $design_params->{$element.'_start'} = $design_params->{$element.'_end'} - $params->{'region_length_'.$element};

          $previous_coord = $element.'_start';
          $design_params->{'start'} = $design_params->{$element.'_start'};
      }
      $previous_coord = 'target_end';
      foreach my $element (@$elements_after_target){
          $design_params->{$element.'_start'} = $design_params->{$previous_coord}   + $params->{'region_offset_'.$element};
          $design_params->{$element.'_end'}   = $design_params->{$element.'_start'} + $params->{'region_length_'.$element};

          $previous_coord = $element.'_end';
          $design_params->{'end'} = $design_params->{$element.'_end'};
      }
    }
    else{
      my $previous_coord = 'target_start';
      foreach my $element (@$elements_after_target){
          $design_params->{$element.'_end'} = $design_params->{$previous_coord} - $params->{'region_offset_'.$element};
          $design_params->{$element.'_start'} = $design_params->{$element.'_end'} - $params->{'region_length_'.$element};

          $previous_coord = $element.'_start';
          $design_params->{'start'} = $design_params->{$element.'_start'};
      }
      $previous_coord = 'target_end';
      foreach my $element (reverse @$elements_before_target){
          $design_params->{$element.'_start'} = $design_params->{$previous_coord} + $params->{'region_offset_'.$element};
          $design_params->{$element.'_end'} = $design_params->{$element.'_start'} + $params->{'region_length_'.$element};

          $previous_coord = $element.'_end';
          $design_params->{'end'} = $design_params->{$element.'_end'};
      }
    }
    return $design_params;
}
1;
