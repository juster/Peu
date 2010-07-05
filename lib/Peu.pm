package Peu;

use warnings;
use strict;

our $VERSION = '0.01';

use English    qw(-no_match_vars);
use Carp       qw();

use Router::Simple;
use Peu::Req;
use Peu::Res;
use Peu::Ext::View;

$Carp::CarpInternal{ __PACKAGE__ } = 1;

# This defines global attribute handlers.  They affect every Peu web app.
my %USER_ATTRIBS;
sub ATTRIB
{
    my ($name, $handler_ref) = @_;

    Carp::croak( 'Invalid arguments to ATTRIB' )
        if ( ! $name || ref $name || ref $handler_ref ne 'CODE' );

    # Store where the attribute is defined for error reporting...
    $USER_ATTRIBS{ $name } = [ $handler_ref, [ caller ] ];
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
        # Check our standards HTTP attributes...
        if ( $attrib =~ / \A (ANY|GET|POST|UPDATE|DEL|DELETE)
                              [(] ([^)]+) [)] \z /xms ) {
            Carp::croak( 'You can only have one HTTP-method attribute' )
                if $results{ 'method' };

            $results{'method'} = $1;
            $results{'route'}  = $2;
            next ATTRIB_LOOP;
        }

        # If our user defined attributes don't match, attribute is
        # unknown.  This generally displays an error.
        unless ( $attrib =~ /$user_attrib_match/ ) {
            push @unknown_attribs, $attrib;
            next ATTRIB_LOOP;
        }

        # Call our custom attribute handler if our HTTP request type
        # attributes did not match...

        my $name       = $1;
        my $attrib_ref = $USER_ATTRIBS{ $name }; # $attrib is an aref
        my %newdata    = eval { $attrib_ref->[0]->( split /\s*,\s*/, $2 ) };

        Carp::croak( qq{Attribute for "$name" defined at } .
                     qq{$attrib_ref->[1][1]:$attrib_ref->[1][2] } .
                     qq{failed:\n$EVAL_ERROR} ) if $EVAL_ERROR;

        # Merge new data into userdata to be stored in the route...
        for my $newkey ( keys %newdata ) {
            $user_data->{ $newkey } = $newdata{ $newkey };
        }
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
        return *{ "${caller_pkg}::${name}" };
    };

    ######################################################################
    # CORE WEBAPP LOGIC
    #---------------------------------------------------------------------

    my $C_execute_route; # This is defined later on...
    my ($V_route_params, $V_response_obj, $V_request_obj) = {};

    # The default handler matches when nothing else does...
    my $default_handler = sub {
        [ 404,
          [ 'Content-Type' => 'text/html' ],
          [ <<END_HTML ],
<html>
<head><title>404 Not Found</title></head>
<body><h1>404 Not Found</h1></body>
</html>
END_HTML
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

        my $matchdata_ref = $V_router->match( $req_ref );
        $matchdata_ref  ||= { '_code' => $default_handler };

        my $result = $C_execute_route->( $matchdata_ref );

        # If the controller code returns a scalar, treat it like
        # the body text for the response...
        return $result if ref $result;
        $V_response_obj->body( $result );
        return $V_response_obj->as_aref;
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

    ######################################################################
    # COMMON EXTENSIONS
    #---------------------------------------------------------------------
    
    my %ext_methods = ( 'wrap'   => $EX_wrap,
                        'cfg'    => $EX_cfg,
                        'liason' => $liason,
                        'attrib' => \&ATTRIB, );

    Peu::Ext::View->new( \%ext_methods )->run();

    return;
}

1; # End of Peu

__END__

=head1 NAME

Peu - A little perl web framework.

=head1 SYNOPSIS

  # Example .psgi file:
  use Peu;

  # If you return just text, it is made the response body.
  sub fooyou :ANY(/api/{version}/{arg}) {
      "Hello, I'm Peu!  You want version $Prm{version}?  $Prm{arg} you!"
  }
  
  # Maybe you want to change other things about the response, first?
  sub old :ANY(/api/1.3) {
      $Res->code( 500 );
      $Res->content-type( 'text/plain' );
      '500 Error';
  }
  
  sub raw :ANY(/psgi) {
      # You can also return a raw PSGI response array-ref.
      return [ '404',
               [ Content-Type => 'text/plain' ],
               [ '<h1>404 Error!</h1>' ],
              ];
  }

  # Want templates? use the :VIEW attribute ...
  
  sub fumanchu :GET(/fu/:variable) :VIEW(fumanchu) {
      # return undef     ^^^^^^^^
      # passes the route parameters as a hashref to the template (fumanchu)
  }
  
  sub fuwhat :GET(/say/what/) :VIEW(fumanchu) {
      # or you can return explicit hash references to templates...
      { 'variable' => 'what?' };
  }

  FIN # <--- this must be at the end of your .psgi file!

  __DATA__
  
  __fumanchu__
  This is the Fu-Manchu template system, based on Mustache.
  It is very incomplete, all it can do it interpolate variables
  by wrapping them in "mustaches": {{variable}}

=head1 DESCRIPTION

Peu is a micro web framework that runs on top of L<Plack>.  It started
off as a Dancer DSL clone but now looks more like Bottle.  Like
Catalyst, Peu uses subroutine attributes to determines routes.  Unlike
Catalyst, the routes are explicit (more like RoR I imagine).

Peu does some funky things like use global variables for passing
around the HTTP request and response objects.  Micro web frameworks
all seem kind of funky anyways and should embrace the funk!

The goal of Peu is to be as minimal as possible.  The only outside
dependencies are L<Plack> and L<Router::Simple>.

=head1 ROUTES

The basic building block of all Peu webapps is, of course, the route.
A route is just a chunk of logic that matches an HTTP request.  HTTP
requests (from clients) can ask for just about any I<URI>.  By
matching a given I<URI> path, a Peu route can easily extract
parameters from the path or request, prepare a response, and send data
to the view.

Peu I<currently> uses L<Router::Simple> so the syntax of the routes is
the same as plain vanilla L<Router::Simple>.  Routes are defined as
subroutine attributes.  Attributes have the appearance of subroutine
calls.  A parenthesis with the route inside directly follow the
attribute.

The attribute names are in all capitals and match the different type
of HTTP requests.  Except for I<ANY> which matches, you guessed it,
any type of HTTP request.  Sound familiar?

=head2 Route Match Syntax

See L<Router::Simple> for basically the same info.  Routes basically just
match stuff in-between the C</>'s in I<URIs>:

=over 4

=item Literals

  /foo/bar

This just matches I<yourapp.com/foo/bar>.  Yawn.

=item C<{} :>

  /:foo/:bar   ( match: /hello/world, /how/areyou )
  /{foo}/{bar}

This matches any I<URI> with two I<components> separated by a C</>.
The C<:> and C<{}> notation are equivalent.  The C<:> looks abit nicer
I think.  The parameters I<"foo"> and I<"bar"> are passed to the
matching route's code inside a hash.

=item C<*>

  /foo/*          ( match: /foo/bar, /foo/barbaz, /foo/bar/etc/etc )
  /foo/*.pl/runme ( match: /foo/bar/baz/cgi.pl/runme, /foo/cgi.pl/runme )

=back

* matches anything, including forward-slashes (C</>).  It is greedy
because it is equivalent to the C<(.+)> regexp.

=item 

=head2 Route Parameters

=head3 Named Parameters

Named route parameters are available to the matching code via the
C<%Prm> package variable.  The key matches the name of the parameter
specified by the route syntax.  The value is the string used by the
actual URI.

=head3 Unnamed Parameters

Unnamed parameters are those I<URI> components which are matched using
a C<*> pattern matcher.  They are available as an arrayref stored in
C<$Prm{'splat'}> but this will change in the future.

=head2 Package Variables

A few package variables are created inside the caller's (that's you!)
namespace.  This is so they can be used inside any of the router
response blocks.

=head1 REQUESTS

The usual HTTP I<POST> and I<GET> parameters are still available.  You
can access them easily using the well known I<CGI.pm> C<param()>
method.

The C<param()> method is available on the L<Peu::Req> object,
which is sneakily stored in the C<$Req> package variable when you load
I<Peu>.  All the other relevant information about the request is
available in the object.

BTW: The L<Peu::Req> object is really just a wafer-thin wrapper around
the L<Plack::Request> object.  It's also shorter to type.  Great
success!

=head1 RESPONSES



=head1 IMPORT SUMMARY

The following variables subroutines and variables are imported into
the calling namespace when you execute C<use Peu;>:

=head2 Subroutines

There aren't very many of these bad-boys imported.

=over 4

=item C<ATTRIB>

  ATTRIB 'NAME' => sub { my ($argstr, $store_ref) = @_; ... };

This handy doo-dad lets you define new attributes that you can use
in your C<sub> route definition.

=over 4

=item Parameters:

=over 4

=item 


=over 4

=item $Res

A Peu::Res (same as L<Plack::Response>) object.  This represents
the response YOU are going to give to the client.

=item $Req

A Peu::Req (same as L<Plack::Request>) object.

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

