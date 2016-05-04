package WebAppCommon::Design::DesignParameters;

use strict;
use warnings FATAL => 'all';
use WebAppCommon::Util::EnsEMBL;
use DesignCreate::CmdRole::OligoPairRegionsGibsonDel;

use Sub::Exporter -setup => {
    exports => [
        qw(
            c_get_default_design_params
            c_get_target_coords
            c_get_target_coords_from_exons
         )
    ]
};

my $DEFAULTS = {
  region_length_5F    => 500,
  region_length_5R    => 100,
  region_length_3F    => 100,
  region_length_3R    => 500,
  region_length_5R_EF => 200,
  region_length_ER_3F => 200,
  region_length_U5    => 100,
  region_length_D3    => 100,
  region_length_f5F   => 500,
  region_length_f3R   => 500,
  region_offset_5F    => 1000,
  region_offset_3R    => 1000,
  region_offset_5R    => 1,
  region_offset_3F    => 1,
  region_offset_5R_EF => 200,
  region_offset_ER_3F => 100,
  region_offset_U5    => 1,
  region_offset_D3    => 1,
  region_offset_f5F   => 1000,
  region_offset_f3R   => 1000,
};

sub c_get_default_design_params{
	my ($params) = @_;

    my $design_params = {};

    my $target_coords = c_get_target_coords($params);
    my $default_params = gibson_design_params($target_coords);

    $default_params->{strand} = $target_coords->{strand};

    return $default_params;
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
sub gibson_design_params{
    my ($target_coords) = @_;

    my $design_params = {
        target_start => $target_coords->{target_start},
        target_end   => $target_coords->{target_end},
    };

    if($target_coords->{strand} == 1){
        # 5F ----- 5R ----- target_start
    	$design_params->{'5R_end'}   = $design_params->{'target_start'} - $DEFAULTS->{'region_offset_5R'};
    	$design_params->{'5R_start'} = $design_params->{'5R_end'}       - $DEFAULTS->{'region_length_5R'};
    	$design_params->{'5F_end'}   = $design_params->{'5R_start'}     - $DEFAULTS->{'region_offset_5F'};
    	$design_params->{'5F_start'} = $design_params->{'5F_end'}       - $DEFAULTS->{'region_length_5F'};

    	# target_end ----- 3F ----- 3R
    	$design_params->{'3F_start'} = $design_params->{'target_end'}   + $DEFAULTS->{'region_offset_3F'};
    	$design_params->{'3F_end'}   = $design_params->{'3F_start'}     + $DEFAULTS->{'region_length_3F'};
    	$design_params->{'3R_start'} = $design_params->{'3F_end'}       + $DEFAULTS->{'region_offset_3R'};
    	$design_params->{'3R_end'}   = $design_params->{'3R_start'}     + $DEFAULTS->{'region_length_3R'};
    }
    else{
    	# 3R ----- 3F ----- target_start
        $design_params->{'3F_end'}   = $design_params->{'target_start'}   - $DEFAULTS->{'region_offset_3F'};
        $design_params->{'3F_start'} = $design_params->{'3F_end'}       - $DEFAULTS->{'region_length_3F'};
        $design_params->{'3R_end'}   = $design_params->{'3F_start'}     - $DEFAULTS->{'region_offset_3R'};
        $design_params->{'3R_start'} = $design_params->{'3R_end'}       - $DEFAULTS->{'region_length_3R'};

    	# target_end ----- 5R ----- 5F
    	$design_params->{'5R_start'} = $design_params->{'target_end'} + $DEFAULTS->{'region_offset_5R'};
    	$design_params->{'5R_end'}   = $design_params->{'5R_start'}     + $DEFAULTS->{'region_length_5R'};
    	$design_params->{'5F_start'} = $design_params->{'5R_end'}       + $DEFAULTS->{'region_offset_5F'};
    	$design_params->{'5F_end'}   = $design_params->{'5F_start'}     + $DEFAULTS->{'region_length_5F'};
    }
    return $design_params;
}
1;
