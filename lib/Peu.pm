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

1;

#EOF
