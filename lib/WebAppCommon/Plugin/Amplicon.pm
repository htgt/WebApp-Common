package WebAppCommon::Plugin::Amplicon;

use strict;
use warnings FATAL => 'all';

use Moose::Role;
use Hash::MoreUtils qw( slice slice_def );
use namespace::autoclean;

sub pspec_create_amplicon {
    return {
        amplicon_type   => { validate => 'existing_amplicon_type' },
        seq             => { validate => 'dna_seq' },
        design_id       => { validate => 'existing_design_id' },
        locus           => { validate => 'hashref', optional => 1 },
    };
}

sub create_amplicon {
    my ( $self, $params ) = @_;

    my $validated_params = $self->check_params( $params, $self->pspec_create_amplicon );

    #Perform XOR design_id check when external plates schema is introduced

    my $amp_values = {
        amplicon_type   => $validated_params->{amplicon_type},
        seq             => $validated_params->{seq},
    };

    my $amplicon = $self->schema->resultset('Amplicon')->create(
        {
            slice_def( $amp_values,
                qw( amplicon_type seq )
            )
        }
    );

    $amplicon->create_related( design_amplicon => { design_id => $validated_params->{design_id} } );

    if ($validated_params->{locus}) {
        $amplicon->create_related( amplicon_loci => $validated_params->{locus} );
    }

    return $amplicon;
}

1;