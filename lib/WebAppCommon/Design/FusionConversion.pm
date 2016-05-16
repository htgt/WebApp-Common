package WebAppCommon::Design::FusionConversion;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Design::FusionConversion::VERSION = '0.057';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ 'modify_fusion_oligos' ]
};

use Moose::Role;
use Bio::SeqIO;
use Bio::EnsEMBL::Registry;

sub modify_fusion_oligos {
    my ($self, $oligos) = @_;
    my @oligos_arr = @{$oligos};
    my $slice;

    my $oligo_slice = {
        '1U5'   => sub { return $_[0] - (25 + $_[2]), $_[1] }, #0
        '-1D3'  => sub { return $_[0] - (25 + $_[2]), $_[1]}, #0
        '1D3'   => sub { return $_[0], $_[1] + (25 + $_[2]) }, #1
        '-1U5'  => sub { return $_[0], $_[1] + (25 + $_[2]) }, #1
    };
    foreach my $oligo (@oligos_arr) {
        my @loci_array = @{$oligo->{loci}};
        foreach my $loci (@loci_array) {
            if ($oligo->{type} eq 'D3' || $oligo->{type} eq 'U5') {
                my $diff = 25 - ($loci->{chr_end} - $loci->{chr_start} + 1);
                my ($start_loc, $end_loc) = $oligo_slice->{$self->chr_strand . $oligo->{type}}->($loci->{chr_start}, $loci->{chr_end}, $diff);
                $slice = $self->slice_adaptor->fetch_by_region(
                    'chromosome',
                    $self->chr_name,
                    $start_loc,
                    $end_loc,
                    1,
                );

                $loci->{chr_start} = $start_loc;
                $loci->{chr_end} = $end_loc;
                $oligo->{seq} = $slice->seq;
            }
        }
    }
    return @oligos_arr;
}

1;
