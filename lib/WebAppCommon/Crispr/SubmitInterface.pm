package WebAppCommon::Crispr::SubmitInterface;

use strict;
use warnings FATAL => 'all';

use Moose::Role;
use WebAppCommon::Util::FarmJobRunner;

#we don't actually require anything yet but probably will soon,
#requires qw( species );

=head2 c_run_crispr_search_cmd

Bsub the crispr create command in farm3

=cut
sub c_run_crispr_search_cmd {
    my ( $self, $cmd, $params ) = @_;

    #this should be changed to be more like the design one,
    #i.e. the folder creation should be done here with a uuid or something
    #

    my %farm_job_params = (
        default_memory => 4000,
    );
    $farm_job_params{bsub_wrapper} = $ENV{FARM3_BSUB_WRAPPER} if exists $ENV{FARM3_BSUB_WRAPPER};
    my $runner = WebAppCommon::Util::FarmJobRunner->new( %farm_job_params );

    my $job_id = $runner->submit(
        out_file => $params->{ output_dir }->file( "paired_crisprs_" . $params->{id} . ".out" ),
        err_file => $params->{ output_dir }->file( "paired_crisprs_" . $params->{id} . ".err" ),
        cmd      => $cmd,
    );

    $self->log->info( "Successfully submitted paired crispr search job $job_id" );

    return $job_id;
}

1;

__END__
