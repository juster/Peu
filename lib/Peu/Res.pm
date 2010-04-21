package Peu::Res;

use warnings;
use strict;
use base qw(Plack::Response);

use Carp qw();

sub new
{
    my $class = shift;

    my ($status, $headers, $body);

    if ( @_ == 1 ) {
        $body = shift;
        $status = 200;
        $headers = [ 'Content-Type' => 'text/html' ];
    }
    # TODO: 2 arguments?
    elsif ( @_ == 3 ) {
        ($status, $headers, $body) = @_;
    }
    else {
        Carp::croak 'Invalid arguments';
    }

    # TODO: arguments in any order?

    $class->SUPER::new( $status, $headers, $body );
}

sub as_aref
{
    my $self = shift;
    return $self->finalize;
}

1;

__END__
