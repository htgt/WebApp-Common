package WebAppCommon::FormValidator;
## no critic(RequireUseStrict,RequireUseWarnings)
{
    $WebAppCommon::FormValidator::VERSION = '0.016';
}
## use critic


=head1 NAME

WebAppCommon::FormValidator

=head1 DESCRIPTION

Framework to check the parameters passed to a subroutine.

=cut

use warnings FATAL => 'all';

use Moose;
use Data::FormValidator;
use WebAppCommon::FormValidator::Constraint;
use Hash::MoreUtils qw( slice_def );
use Log::Log4perl qw( :easy );
use Data::Dump qw( pp );
use namespace::autoclean;

has model => (
    is       => 'ro',
    required => 1,
    handles  => [ 'schema' ]
);

has cached_constraint_methods => (
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        has_cached_constraint_method    => 'exists',
        get_cached_constraint_method    => 'get',
        set_cached_constraint_method    => 'set',
        delete_cached_constraint_method => 'delete',
    }
);

has constraints => (
    is         => 'ro',
    isa        => 'WebAppCommon::FormValidator::Constraint',
    lazy_build => 1,
);

sub _build_constraints {
    my $self = shift;
    return WebAppCommon::FormValidator::Constraint->new( model => $self->model );
}

sub init_constraint_method {
    my ( $self, $constraint_name ) = @_;

    my $constraint = $self->constraints->$constraint_name();

    return sub {
        my $dfv = shift;
        $dfv->name_this($constraint_name);
        my $val = $dfv->get_current_constraint_value();
        return $constraint->($val);
    };
}

sub constraint_method {
    my ( $self, $constraint_name ) = @_;

    unless ( $self->has_cached_constraint_method($constraint_name) ) {
        $self->set_cached_constraint_method( $constraint_name => $self->init_constraint_method($constraint_name) );
    }

    return $self->get_cached_constraint_method($constraint_name);
}

sub post_filter {
    my ( $self, $method, $value ) = @_;

    if ( defined $value ) {
        return $self->model->$method($value);
    }
    else {
        return;
    }
}

sub check_params {
    my ( $self, $params, $spec, %opts ) = @_;

    $params ||= {};

    if ( $opts{ignore_unknown} ) {
        $params = { slice_def $params, keys %{$spec} };
    }

    my $results = Data::FormValidator->check( $params, $self->dfv_profile($spec) );

    if ( !$results->success ) {
    	DEBUG "Invalid parameters seen in ".( caller(2) )[3];
        $self->throw( $params, $results );
    }

    if ( $results->has_unknown && !$opts{ignore_unknown} ) {
    	DEBUG "Invalid parameters seen in ".( caller(2) )[3];
        $self->throw( $params, $results );
    }

    my $validated_params = $results->valid;

    while ( my ( $field, $f_spec ) = each %{$spec} ) {
        next unless $validated_params->{$field};

        if ( $f_spec->{post_filter} ) {
            $validated_params->{$field} = $self->post_filter( $f_spec->{post_filter}, $validated_params->{$field} );
        }
        if ( $f_spec->{rename} ) {
            $validated_params->{ $f_spec->{rename} } = delete $validated_params->{$field};
        }
    }

    return $validated_params;
}

sub dfv_profile {
    my ( $self, $spec ) = @_;

    my ( @required, @optional, %constraint_methods, %field_filters, %defaults );

    my $dependencies      = delete $spec->{DEPENDENCIES};
    my $dependency_groups = delete $spec->{DEPENDENCY_GROUPS};
    my $require_some      = delete $spec->{REQUIRE_SOME};

    while ( my ( $field, $f_spec ) = each %{$spec} ) {
        if ( $f_spec->{optional} ) {
            push @optional, $field;
        }
        else {
            push @required, $field;
        }
        if ( $f_spec->{validate} ) {
            $constraint_methods{$field} = $self->constraint_method( $f_spec->{validate} );
        }
        if ( $f_spec->{filter} ) {
            $field_filters{$field} = $f_spec->{filter} || [];
        }
        if ( defined $f_spec->{default} ) {
            $defaults{$field} = $f_spec->{default};
        }
        if ( not( defined $f_spec->{trim} ) or $f_spec->{trim} ) {
            push @{ $field_filters{$field} }, 'trim';
        }
    }

    return {
        required           => \@required,
        optional           => \@optional,
        defaults           => \%defaults,
        field_filters      => \%field_filters,
        constraint_methods => \%constraint_methods,
        dependencies       => $dependencies,
        dependency_groups  => $dependency_groups,
        require_some       => $require_some,
    };
}

=head2 clear_cached_constraint_method

If you want to delete a cached constraint method use this function.

=cut
sub clear_cached_constraint_method {
    my ( $self, $constraint_name ) = @_;

    if ( $self->has_cached_constraint_method($constraint_name) ) {
        $self->delete_cached_constraint_method($constraint_name);
    }

    return;
}

# copied from LIMS2::Exception::Validatio
# it would be better to override this in a child class
sub throw {
    my ( $self, $params, $results ) = @_;

    my $str = 'Parameter validation failed';

    if ( defined $results ) {
        my @errors;

        if ( $results->has_missing ) {
            for my $f ( $results->missing ) {
                push @errors, "$f, is missing";
            }
        }

        if ( $results->has_invalid ) {
            for my $f ( $results->invalid ) {
                push @errors, "$f, is invalid: " . join q{,}, @{ $results->invalid( $f ) };
            }
        }

        if ( $results->has_unknown ) {
            for my $f ( $results->unknown ) {
                push @errors, "$f, is unknown";
            }
        }

        $str = join "\n\t", $str, @errors;
    }
    if ( defined $params ) {
        $str .= "\n\n" . pp( $params );
    }

    die( $str );
}

__PACKAGE__->meta->make_immutable;

1;

__END__



