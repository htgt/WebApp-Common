package WebAppCommon::Util::Sanitize;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::Util::Sanitize::VERSION = '0.071';
}
## use critic


use strict;
use warnings FATAL => 'all';

use Sub::Exporter -setup => {
    exports => [ qw( sanitize_like_expr ) ]
};

=head2 sanitize_like_expr

Sanitize input for SQL 'like' statement. Need to escape backslashes
first, then underscores and percent signs.

=cut

sub sanitize_like_expr {
    my ( $expr ) = @_;

    for ( $expr ) {
        s/\\/\\\\/g; s/_/\\_/g;
        s/\%/\\%/g;
    }

    return $expr;
}

1;
