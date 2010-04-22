package Peu;

use warnings;
use strict;

our $VERSION = '0.01';

use Router::Simple;
use Peu::Resp;
use English    qw(-no_match_vars);
use Carp       qw();

sub import
{
    my $caller_pkg = caller(0);
    my $router     = Router::Simple->new();

    # These get added to later and are checked when a match occurs.
    my @before_filters;
    my @error_handlers;

    # Get or set globs in the caller package...
    my $liason = sub {
        my ($name, $ref) = @_;
        no strict 'refs';
        if ( defined $ref ) {
            return *{ "${caller_pkg}::${name}" } = $ref;
        }
        else {
            return *{ "${caller_pkg}::${name}" };
        }
    };

    # This curries the coderef passed to the http method keyword.
    my $resp_curry = sub {
        my ($usercode_ref) = @_;

        return sub {
            my $match_ref = shift;
            $_->() foreach @{ delete $match_ref->{ '_befores' } };

            # Store route parameters in the caller package...
            $liason->( 'Prm' => $match_ref );
            
            # Catch errors and use error handlers later...
            my $body = eval { $usercode_ref->() };

#             return [ 500,
#                      [ 'Content-Type' => 'text/html' ],
#                      [ '500 Internal Server Error' ],
#                     ] 

            die if $EVAL_ERROR;
            
            $res = *{ $liason->( 'Res' ) }{SCALAR};
            $res->body( $body ) if $body;
            return $res->as_aref;
        }
    };

    # Sort of copied from Router::Simple::Cookbook
    # Define an HTTP_METHOD keyword...
    my $def_method_keyword = sub {
        my ($http_method) = @_;

        $liason->( $http_method, sub {
                       my $route    = shift;
                       my $code_ref = shift;
            
                       $router->connect
                           ( $route,
                             { '_befores' => [ @before_filters ],
                               '_errors'  => [ @error_handlers ],
                               '_code'    => $resp_curry->($code_ref),
                              },
                             ( $http_method eq 'any' ? ()
                               : { method => uc $http_method } ),
                            );
                   });
    };

    $def_method_keyword->( $_ ) foreach qw/ ANY GET DEL POST UPDATE /;

    # Create a default response...
    my $response = Peu::Res->new();
    $response->status( 200 );
    $response->content_type( 'text/html' );

    # Declare package variables in the caller package..
    $liason->( 'Res' => \$response );
    $liason->( 'Rtr' => \$router );
    $liason->( 'Req' => do { my $anon_scalar; \$anon_scalar } );
    $liason->( 'Prm' => {} );

    my $psgi_app = sub {
        my $req_ref = shift;

        require Peu::Req;
        $liason->( 'Req', \Peu::Req->new( $req_ref ) );

        my $match_ref = $router->match( $req_ref )
            or return [ 404,
                        [ 'Content-Type' => 'text/html' ],
                        [ '404 Not found' ],
                       ];

        ( delete $match_ref->{ '_code' } )->( $match_ref );
    }

    # to_app is called by the .psgi file and returns a coderef of the app
    $liason->( 'to_app' => sub { $psgi_app } );

    # The "mid" keyword enables Plack middleware.
    my $mid_keyword = sub {
        my $name = ucfirst shift;

        my $class_name = "Plack::Middlware::$name";
        local $Carp::Internal{ (__PACKAGE__) } = 1;
        $app = $class_name->wrap( $app, @_ );
    };
    $liason->( 'MID' => $mid_keyword );

    my %config_keywords = ( 'static' => sub { $mid_keyword->( 'static' ) } );
    $liason->( 'CFG' => sub {
                   my $name = shift;

                   Carp::croak "$name is not a valid config key"
                       unless exists $config_keywords{ $name };

                   my $cfgset_ref = $config_keywords{ $name };
                   Carp::croak "$name was already set and cannot be changed"
                       unless defined $cfgset_ref;

                   $cfgset_ref->( @_ );
                   return;
               },
              );

    return;
}

1; # End of Peu

__END__

=head1 NAME

makerPeu - Un peu web "framework".

=head1 VERSION

0.01

=head1 SYNOPSIS

  use Peu;

  any "/api/{version}/{arg}" => {
    "Hello, I'm Peu!  You want version $Prm{version}?  $Prm{arg} you!"
  }
  
  post "/api/1.3" => {
    $Res->code( 500 );
    $Res->content-type( 'text/plain' );
    '500 Error';
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

=item $Res - A Peu::Res (same as L<Plack::Response>) object.

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

