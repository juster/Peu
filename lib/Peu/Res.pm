package Peu::Res;

use warnings;
use strict;
use parent qw(Plack::Response);

sub as_aref
{
    my $self = shift;
    return $self->finalize;
}

1;

__END__
