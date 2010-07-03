package Peu;

use warnings;
use strict;

our $VERSION = '0.01';

use Router::Simple;
use Peu::Req;
use Peu::Res;
use English    qw(-no_match_vars);
use Carp       qw();

sub import
{
    my $caller_pkg = caller 0;
    my $router     = Router::Simple->new();

#     local $Carp::Internal{ (__PACKAGE__) } = 1;

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
            $_->() foreach @{ $match_ref->{ '_befores' } };

            # Store route parameters in the caller package...
            # Do not copy internal use keys which begin with _
            my %params = map { ( $_ => $match_ref->{$_} ) }
                grep { ! /^_/ } keys %$match_ref;
            $liason->( 'Prm' => \%params );
            
            # Catch errors and use error handlers later...
            my $result = eval { $usercode_ref->() };

#             return [ 500,
#                      [ 'Content-Type' => 'text/html' ],
#                      [ '500 Internal Server Error' ],
#                     ] 

            die if $EVAL_ERROR;

            # Acknowledge raw PSGI responses as well...
            return $result if ref $result eq 'ARRAY';
            
            my $res = ${ *{ $liason->( 'Res' ) }{SCALAR} };
            $res->body( $result ) if $result;
            return $res->as_aref;
        }
    };
    
    # These get added to later and are checked when a match occurs.
    my @before_filters;
    my @error_handlers;

    my $make_match_data = sub {
        my $code_ref = shift;

        Carp::croak( 'Invalid argument: must be a code reference' )
            unless ref $code_ref eq 'CODE';
        
        return { '_befores' => [ @before_filters ],
                 '_errors'  => [ @error_handlers ],
                 '_code'    => $resp_curry->( $code_ref ),
                };
    };

    # Sort of copied from Router::Simple::Cookbook
    # Define an HTTP_METHOD keyword...
    my $def_method_keyword = sub {
        my $http_method = uc shift;

        $liason->( $http_method, sub {
                       my $route    = shift;
                       my $code_ref = shift;
            
                       $router->connect
                           ( $route,
                             $make_match_data->( $code_ref ),
                             ( $http_method eq 'ANY' ? ()
                               : { method => $http_method } ),
                            );
                   });
    };

    $def_method_keyword->( $_ ) foreach qw/ ANY GET DEL POST DELETE UPDATE /;

    # DEFAULT handlers match when nothing else does...
    my $default_handler;

    $default_handler =
        $make_match_data->( sub { [ 404,
                                    [ 'Content-Type' => 'text/html' ],
                                    [ '404 Not found' ],
                                   ];
                              } );

    $liason->( 'SLURP' => sub {
                   my ($path) = @_;
                   
                   local $/;
                   open my $file, q{<}, $path
                       or Carp::croak( "open on $path: $!" );
                   return <$file>;
               });

    # Declare package variables in the caller package..
    my ( %empty_hash, $empty_scalar );
    $liason->( 'Res' => \$empty_scalar );
    $liason->( 'Req' => \$empty_scalar );
    $liason->( 'Prm' => \%empty_hash   );
    $liason->( 'Rtr' => \$router       );

    my $psgi_app = sub {
        my $req_ref = shift;

        # If PATH_INFO is blank we can never match it to a route...
        $req_ref->{PATH_INFO} ||= q{/};

        # Create a default response object...
        my $response = Peu::Res->new();
        $response->status( 200 );
        $response->content_type( 'text/html' );

        $liason->( 'Res' => \$response ); 
        $liason->( 'Req' => \Peu::Req->new( $req_ref ) );
        $liason->( 'Prm' => {} );

        my $match_ref = $router->match( $req_ref );
        $match_ref ||= $default_handler;

        my $responder_ref = $match_ref->{ '_code' };
        $responder_ref->( $match_ref );
    };

    # to_app is called by Plack and returns a coderef of the app
    $liason->( 'to_app' => sub { $psgi_app } );

    # The "mid" keyword enables Plack middleware.
    my $mid_keyword = sub {
        my $name = ucfirst shift;

        my $class_name = "Plack::Middleware::$name";
        eval "require $class_name";
        Carp::croak( "MID could not find a class called $class_name" )
            if $@;
        $psgi_app = $class_name->wrap( $psgi_app, @_ );
    };
    $liason->( 'MID' => $mid_keyword );

    my %config_keywords = ( );
    $liason->( 'CFG' => sub {
                   my $name = shift;

                   Carp::croak "$name is not a valid config key"
                       unless exists $config_keywords{ $name };

                   my $cfgset_ref = $config_keywords{ $name };
                   Carp::croak "$name was already set and cannot be changed"
                       unless defined $cfgset_ref;

                   $cfgset_ref->( @_ );
                   undef $config_keywords{ $name };
                   return;
               },
              );

    return;
}

1; # End of Peu

__END__

=head1 NAME

Peu - A little web framework.

=head1 SYNOPSIS

  use Peu;

  ANY "/api/{version}/{arg}" => {
    "Hello, I'm Peu!  You want version $Prm{version}?  $Prm{arg} you!"
  }
  
  POST "/api/1.3" => {
    $Res->code( 500 );
    $Res->content-type( 'text/plain' );
    '500 Error';
  }

=head1 DESCRIPTION

This is a micro framework that is even smaller than micro... it's peu!
Peu means "little" in French.  It's another DSL framework with less
features in about 200 lines of code.

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

A few package variables are created inside the caller's (that's you!)
namespace.  This is so they can be used inside any of the router
response blocks.

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

=head1 AUTHOR

Justin Davis C<< <juster at cpan dot org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Justin Davis.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

