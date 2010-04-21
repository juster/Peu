package Peu;

use warnings;
use strict;

our $VERSION = '0.01';

use Router::Simple;
use Peu::Request;
use English qw(-no_match_vars);

sub import
{
    my $caller_pkg = caller(0);
    my $router     = Router::Simple->new();

    # These get added to later and are checked when a match occurs.
    my @before_filters;
    my @error_handlers;

    my $response_maker = sub {
        my ($usercode_ref) = @_;

        sub {
            my $match_ref = shift;
            $_->() foreach @{ delete $match_ref->{ '_befores' } };

            # Store route parameters...
            *{ "${caller_pkg}::Prm" } = $match_ref;

            # Catch errors and use error handlers later...
            my @response = eval { $usercode_ref->() };
            return [ 500, 'text/plain', '500 Internal Server Error' ]
                if $EVAL_ERROR;
            return Peu::Response->new( @response );
        }
    };

    # Sort of copied from Router::Simple::Cookbook
    my $route_maker = sub {
        no strict 'refs';
        my ($http_method) = @_;
        *{ "${caller_pkg}::${http_method}" } = sub {
            my $route    = shift;
            my $code_ref = shift;
            
            $router->connect( $route,
                              { '_befores' => [ @before_filters ],
                                '_errors'  => [ @error_handlers ],
                                '_code'    => $response_maker->($code_ref),
                               },
                              ( $http_method eq 'any' ? ()
                                : { method => uc $http_method } ),
                             );
        }
    };

    {
        no strict 'refs';

        my $anon_scalar;
        *{ "${caller_pkg}::Req" } = \$anon_scalar;
        *{ "${caller_pkg}::Rtr" } = \$router;
        *{ "${caller_pkg}::Prm" } = {};

        *{ "${caller_pkg}::to_app" } = sub {
            sub {
                my $req_ref = shift;
                *{ "${caller_pkg}::Req" } = Peu::Req->new( $req_ref );

                my $match_ref = $router->match( $req_ref )
                    or return [ 404,
                                [ 'ContentType' => 'text/html' ],
                                [ '404 Not found' ],
                               ];

                ( delete $match_ref->{ '_code' } )->();
            }
        };

    }

    $route_maker->( $_ ) foreach qw/ any get post delete update /;
}

1; # End of Peu

__END__

=head1 NAME

Peu - Un peu web "framework".

=head1 VERSION

0.01

=head1 SYNOPSIS

  use Peu;

  any "/api/{version}/{arg}" => {
    "Hello, I'm Peu!  You want version $Prm{version}?  $Prm{arg} you!"
  }

=head1 DESCRIPTION

This is a micro framework that is even smaller than micro... it's peu!
Peu means "little" in French.  It's another DSL framework with less
features in about 100 lines of code.

=head1 WHY

I sort of started to use Plack to write a B<REALLY> simple application.
However Plack's docs kept saying "don't do that! we're for frameworks
only, stupid!".  So I made a super simple one that let me use
Route::Simple and Plack::Request.  Neato!

=head1 HOW

Well it's sort of like another Sinatra clone, but more like one that
is deformed and missing important bits.

=head2 any / get / post / delete / update

TODO

=head2 Package Variables

A few package variables are created into the importer's namespace.
This is so they can be used inside any of the router response blocks.

=over 4

=item $Req - A Peu::Req (same as L<Plack::Request>) object.

=item %Prm - Route parameters, if you have specified any.

=item $Rtr - A L<Router::Simple> object that's matching things.

=back

=head1 HUH

I will probably add more feature if I need them.  Or y'know just start
using L<Dancer>.

=head1 SEE ALSO

These are also the dependencies: L<Router::Simple> and L<Plack>.

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Justin Davis.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

