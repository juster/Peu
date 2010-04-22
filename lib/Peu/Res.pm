package Peu::Res;

use warnings;
use strict;
use base qw(Plack::Response);

use Carp qw();

sub as_aref
{
    my $self = shift;
    return $self->finalize;
}

1;

__END__
