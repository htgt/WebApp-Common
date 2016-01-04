package WebAppCommon::Design::FusionConversion;

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
    my $seq;

    my $oligo_slice = {
        '1U5'   => sub { return $_[0]-25, $_[0]-1, 1 },
        '-1D3'  => sub { return $_[1]+1, $_[1]+25, 1 },
        '1D3'   => sub { return $_[1]+1, $_[1]+25, 0 },
        '-1U5'  => sub { return $_[0]-25, $_[0]-1, 0 },
    };

    my $oligo_trim = {
        '1f5F'  => sub { return 0, 15 },
        '-1f5F' => sub { return $_[0]-15, $_[0] },
        '1f3R'  => sub { return $_[0]-15, $_[0] },
        '-1f3R' => sub { return 0, 15 },
    };

    my $oligo_rename = {
        'f5F'   => 'f5F',
        'U5'    => 'D3',
        'D3'    => 'f3R',
        'f3R'   => 'U5',
    };

    foreach my $oligo (@oligos_arr) {
        my @loci_array = @{$oligo->{loci}};
        foreach my $loci (@loci_array) {
            $oligo->{type} = $oligo_rename->{$oligo->{type}};
            if ($oligo->{type} eq 'D3' || $oligo->{type} eq 'U5') {
                my ($start_loc, $end_loc, $ident) = $oligo_slice->{$self->chr_strand . $oligo->{type}}->($loci->{chr_start}, $loci->{chr_end});

                $slice = $self->slice_adaptor->fetch_by_region(
                    'chromosome',
                    $self->chr_name,
                    $start_loc,
                    $end_loc,
                    $self->chr_strand,
                );

                if ($self->chr_strand == -1) {
                    $seq = Bio::Seq->new( -alphabet => 'dna', -seq => $oligo->{seq}, -verbose => -1 )->revcom;
                    $seq = $seq->seq;
                }
                else {
                    $seq = $oligo->{seq};
                }

                if ($ident == 0) {
                    $seq = $seq . $slice->seq;
                    if ($self->chr_strand == -1) {
                        $loci->{chr_start} = $start_loc;
                    }
                    else {
                        $loci->{chr_end} = $end_loc;
                    }
                }
                else {
                    $seq = $slice->seq . $seq;
                    if ($self->chr_strand == -1) {
                        $loci->{chr_end} = $end_loc;
                    }
                    else {
                        $loci->{chr_start} = $start_loc;
                    }
                }
            }

            else {
                my $length = length $oligo->{seq};
                my ($start_loc, $end_loc) = $oligo_trim->{$self->chr_strand . $oligo->{type}}->($length);
                $seq = substr($oligo->{seq}, $start_loc, $end_loc);
                if ($start_loc == 0) {
                    $loci->{chr_end} = $loci->{chr_start} + 14;
                }
                else {
                    $loci->{chr_start} = $loci->{chr_end} - 14;
                }
                if ($self->chr_strand == -1) {
                     $seq = Bio::Seq->new( -alphabet => 'dna', -seq => $seq, -verbose => -1 )->revcom;
                     $seq = $seq->seq;
                }
            }

            $oligo->{seq} = $seq;
        }
    }
    return @oligos_arr;
}

1;
