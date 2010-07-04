package Peu;

use warnings;
use strict;

our $VERSION = '0.01';

use Router::Simple;
use Peu::Req;
use Peu::Res;

use English    qw(-no_match_vars);
use Carp       qw();

$Carp::CarpInternal{ __PACKAGE__ } = 1;

# This defines global attribute handlers.  They affect every Peu web app.
my %USER_ATTRIBS;
sub ATTRIB
{
    my ($name, $handler_ref) = @_;

    Carp::croak( 'Invalid arguments to ATTRIB' )
        if ( ! $name || ref $name || ref $handler_ref ne 'CODE' );

    $USER_ATTRIBS{ $name } = $handler_ref;
}

#---HELPER FUNCTION---
# Pass it a reference to the attributes list.  Removes recognized
# attributes from the list and returns the value to use for the
# http_method argument to $router->connect
sub _extract_route_attribs
{
    my ($attribs_ref) = @_;

    my ( @unknown_attribs, %results );

    my $user_attrib_match =
        sprintf '\A(%s)(?:[(]([^)]+)[)]\z)?', join q{|}, keys %USER_ATTRIBS;
    my $user_data = $results{'data'} = {};

    ATTRIB_LOOP:
    while ( my $attrib = shift @$attribs_ref ) {
        unless ( $attrib =~ / \A (ANY|GET|POST|UPDATE|DEL|DELETE|VIEW)
                              [(] ([^)]+) [)] \z /xms ) {

            # Call our custom attribute handler if our HTTP request type
            # attributes did not match...
            if ( $attrib =~ /$user_attrib_match/ ) {
                my $name = $1;
                eval { $USER_ATTRIBS{ $name }->( $2, $user_data ) };
                next ATTRIB_LOOP unless $@;
                Carp::croak( "Attribute handler for $name failed: $@" );
            }

            push @unknown_attribs, $attrib;
            next ATTRIB_LOOP;
        }

        Carp::croak( 'You can only have one HTTP-method attribute' )
            if $results{ 'method' };

        $results{'method'} = $1;
        $results{'route'}  = $2;
    }

    @$attribs_ref = @unknown_attribs;

    return %results;
}

sub import
{
    my $caller_pkg = caller 0;
    my $V_router   = Router::Simple->new();

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

    ######################################################################
    # CORE WEBAPP LOGIC
    #---------------------------------------------------------------------

    my $C_execute_route; # This is defined later on...
    my ($V_response_obj, $V_request_obj, $V_route_params);

    # DEFAULT handlers match when nothing else does...
    my $default_handler = sub { [ 404,
                                  [ 'Content-Type' => 'text/html' ],
                                  [ '<h1>404 Not found</h1>' ],
                                 ];
                            };

    # Declare package variables in the caller package..
    $liason->( 'Res' => \$V_response_obj ); 
    $liason->( 'Req' => \$V_request_obj  );
    $liason->( 'Prm' => $V_route_params );

    # my ( %empty_hash, $empty_scalar );
    # $liason->( 'Res' => \$empty_scalar ); # response object
    # $liason->( 'Req' => \$empty_scalar ); # request object
    # $liason->( 'Prm' => \%empty_hash   ); # route parameters

    my $psgi_app = sub {
        my $req_ref = shift;

        # If PATH_INFO is blank we can never match it to a route...
        $req_ref->{PATH_INFO} ||= q{/};

        # Create a default response object...
        $V_response_obj = Peu::Res->new();
        $V_response_obj->status( 200 );
        $V_response_obj->content_type( 'text/html' );

        # Create a request object for this new request...
        $V_request_obj = Peu::Req->new( $req_ref );

        my $match_ref = $V_router->match( $req_ref );
        $match_ref ||= $default_handler;

        $C_execute_route->( $match_ref );
    };

    my $to_app = sub { $psgi_app };
    $liason->( 'to_app' => $to_app );
    $liason->( 'FIN'    => $to_app );

    ######################################################################
    # HTTP RESPONSES
    #---------------------------------------------------------------------

    # We can wrap this closure in order to add extra functionality...
    $C_execute_route = sub {
        my $route_data = shift;

        # Store route parameters in the caller package.
        # (Also keep a copy to share between closures)
        # Do not copy internal use keys which begin with _
        $V_route_params = +{ map  { ( $_ => $route_data->{$_} ) }
                           grep { ! /^_/ } keys %$route_data };
        $liason->( 'Prm' => $V_route_params );

        # Catch errors and use error handlers later...
        my $result = eval { $route_data->{'_code'}->() };
        die if $EVAL_ERROR;
        return $result;
    };

    my $EX_wrap = sub {
        my $wrapper = shift;

        my $old = $C_execute_route;
        $C_execute_route = sub {
            $wrapper->( $old, @_ );
        };
    };
    $liason->( 'WRAP' => $EX_wrap );

    # Treat non-reference data like response body text...
    $EX_wrap->( sub {
                    my $next = shift;
                    my $result = $next->( @_ );

                    return $result if ( ref $result );

                    $V_response_obj->body( $result );
                    return $V_response_obj->as_aref;
                } );

    # We use attributes for specifying routes...
    # MODIFY_CODE_ATTRIBUTES is called when a sub is defined with attributes
    $liason->( 'MODIFY_CODE_ATTRIBUTES' => sub {
                   my ($pkg, $coderef, @attribs) = @_;
                   my %resp = _extract_route_attribs( \@attribs );

                   # Return any attributes we don't recognize...
                   return @attribs if @attribs;

                   $V_router->connect
                       ( $resp{'route'},
                         { %{$resp{'data'}}, '_code' => $coderef },
                         ( $resp{'method'} eq 'ANY'
                           ? () : { method => $resp{'method'} } ),
                        );

                   return qw//;
               } );

    ######################################################################
    # MISCELLANIOUS KEYWORDS
    #---------------------------------------------------------------------

    # The "mid" keyword enables Plack middleware.
    my $EX_mid = sub {
        my $class_name = 'Plack::Middleware::' . ucfirst shift;
        eval "require $class_name";
        Carp::croak( "MID failed to load $class_name: $@" )
            if $@;
        $psgi_app = $class_name->wrap( $psgi_app, @_ );
    };
    $liason->( 'MID' => $EX_mid );

    my %config_keywords;
    my $EX_cfg = sub {
        my $name = shift;

        Carp::croak "$name is not a valid config key"
            unless exists $config_keywords{ $name };

        my $cfgset_ref = $config_keywords{ $name };
        Carp::croak "$name was already set and cannot be changed"
            unless defined $cfgset_ref;

        $cfgset_ref->( @_ );
        undef $config_keywords{ $name };
        return;
    };
    $liason->( 'CFG' => $EX_cfg );

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

