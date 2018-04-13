package WebAppCommon::Testing::JS;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Testing::JS::VERSION = '0.070';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Selenium::Firefox;
use feature qw(say);
use Path::Class;
use Log::Log4perl qw( :easy );

use Sub::Exporter -setup => {
    exports => [
        qw(
             setup
             find_by
             cycle_windows
             close_additional_windows
             scroll_window
          )
    ],
};

sub setup {
    my $driver = Selenium::Firefox->new(marionette_enabled => 0);

    unless ($driver) {
        say "Driver uninitialised";
        return;
    }
    $driver->get('t87-dev.internal.sanger.ac.uk:' . $ENV{LIMS2_WEBAPP_SERVER_PORT});
    say $driver->get_title();
    $driver->set_implicit_wait_timeout(10);
    $driver->maximize_window;

    return $driver;
}

sub find_by {
    my ($driver, $type, $value) = @_;
    #Specify which type you'll be using
    #Types include: class, class_name, css, id, link, link_text, name, partial_link_text, tag_name, xpath

    $type = 'find_element_by_' . $type;
    my $elem = $driver->$type($value);
    $driver->mouse_move_to_location(element => $elem);
    $driver->click;

    return 1;
}

sub cycle_windows {
    my ($driver) = @_;

    my $focus = $driver->get_current_window_handle;
    my @handles = @{ $driver->get_window_handles };
    my $next;
    for (my $inc = 0; $inc < scalar @handles; $inc++) {
        if ($focus eq $handles[$inc] && $inc < scalar @handles) {
            $next = $inc + 1;
        }
        elsif ($focus eq $handles[$inc] && $inc == scalar @handles) {
            $next = 0;
        }
    }

    $driver->switch_to_window($handles[$next]);

    return 1;
}

sub close_additional_windows {
    my ($driver) = @_;

    my $focus = $driver->get_current_window_handle;
    my @handles = @{ $driver->get_window_handles };
    for (my $inc = 0; $inc < scalar @handles; $inc++) {
        if ($focus ne $handles[$inc]) {
            $driver->switch_to_window($handles[$inc]);
            $driver->close();
        }
    }
    $driver->switch_to_window($focus);

    return 1;
}

sub scroll_window {
    my ($driver, $pixels) = @_;

    ## no critic (ProhibitImplicitNewLines)
    my $scroll = q{
        var value = arguments[0];
        window.scrollBy(0,value);
        return;
    };
    ## use critic
    $driver->execute_script($scroll, $pixels);

    return 1;
}

1;
