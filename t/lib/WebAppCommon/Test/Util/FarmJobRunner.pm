package WebAppCommon::Test::Util::FarmJobRunner;

use strict;
use warnings FATAL => 'all';

use base qw( WebAppCommon::Test::Class );
use Test::Most;
use Const::Fast;

BEGIN {
    __PACKAGE__->mk_classdata( 'class' => 'WebAppCommon::Util::FarmJobRunner' );
}

const my $data => {
    queue   => "basement",
    memory  => "3000",
    wrapper => "custom_environment_setter.pl"
};

#TODO commented out some tests, will fix once farm3 hack is taken out sp12 Thu 19 Dec 2013 09:39:03 GMT

sub startup : Tests(startup => 4) {
    my $test = shift;

    $ENV{LIMS2_REST_CLIENT_CONFIG} = 'test';
    my $class = $test->class;
    use_ok $class;
    can_ok $class, 'new';
    ok my $o = $class->new( { dry_run => 1 } ), 'constructor works';
    isa_ok $o, $class;

    $test->{o} = $o;
};


sub construction : Tests(10) {
    my $test = shift;
    my $o = $test->{o};

    lives_ok { $o->default_queue( $data->{ queue } ) } "Set default queue";
    ok $o->default_queue eq $data->{ queue }, 'Check set queue matches';

    lives_ok { $o->default_memory( $data->{ memory } ) } "Set default memory";
    ok $o->default_memory eq $data->{ memory }, 'Check set memory matches';

    lives_ok { $o->bsub_wrapper( $data->{ wrapper } ) } "Set bsub wrapper";
    ok $o->bsub_wrapper eq $data->{ wrapper }, 'Check set wrapper matches';

    #check we can create a custom instance and the values are set.
    ok my $runner = $test->class->new( {
        default_queue  => "basement",
        default_memory => "3000",
        bsub_wrapper   => "custom_environment_setter.pl"
    } ), 'Create modified instance';

    ok $runner->default_queue eq $data->{ queue }, 'Check default queue matches';
    ok $runner->default_memory eq $data->{ memory }, 'Check default memory matches';
    ok $runner->bsub_wrapper eq $data->{ wrapper }, 'Check bsub wrapper matches';
}


sub _wrap_bsub : Tests( ) {
    my $test = shift;
    my $o = $test->{o};

    ok my ( $bsub, $cmd, @rest ) = $o->_wrap_bsub( "echo", "test" ), "Check wrap bsub runs";
}

sub _build_job_dependency : Tests(9) {
    my $test = shift;
    my $o = $test->{o};

    dies_ok { $o->_build_job_dependency() } "Empty param dies";
    dies_ok { $o->_build_job_dependency(2345) } "Non array ref param dies";
    ok ! $o->_build_job_dependency( [] ), "Check empty list is allowed";

    ok my ( $flag, $value ) = $o->_build_job_dependency( [124] ), "Check list with single entry";
    ok $flag eq "-w", "Check flag is correct";
    ok $value eq '"done(124)"', "Check value is correct";

    ok my ( $mflag, $mvalue ) = $o->_build_job_dependency( [124, 256] ), "Check list with multiple entries";
    ok $mflag eq "-w", "Check flag is correct";
    ok $mvalue eq '"done(124) && done(256)"', "Check value is correct";
}

sub _run_cmd : Tests(2) {
    my $test = shift;
    my $o = $test->{o};

    ok $o->_run_cmd( "echo", "test" ) eq "test\n", "Check output of run cmd";
    dies_ok { $o->_run_cmd( "not_a_real_command" ) } "Check death on invalid command";
}

sub submit : Tests(10) {
    my $test = shift;
    my $o = $test->{o};

    ok my $cmd = $o->submit(
        out_file => "test.out",
        cmd      => [ "echo", "test" ]
    ), "Submit runs with only required parameters";

    ok $cmd->[-1] =~ /-o test.out/, "Out file specified";
    ok $cmd->[-1] =~ /echo test/, "Command specified";

    ok my $new_cmd = $o->submit(
        out_file        => "test.out",
        cmd             => [ "echo", "test" ],
        err_file        => "test.err",
        queue           => "short",
        memory_required => 4000,
        dependencies    => 9999,
    ), "Submit with optional parameters works";

    #check all the stuff we specified is in the cmd string
    my $final_cmd = $new_cmd->[-1];
    ok $final_cmd =~ /-o test\.out/, "Out file specified";
    ok $final_cmd =~ /echo test/, "Command specified";
    ok $final_cmd =~ /-e test\.err/, "Error file specified";
    ok $final_cmd =~ /-q short/, "Queue specified";
    ok $final_cmd =~ /4000/, "Memory specified";
    ok $final_cmd =~ /-w "done\(9999\)"/, "Dependency specified";
}

1;

__END__
