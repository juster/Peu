package Peu::Ext;

use warnings;
use strict;

use Carp qw();

sub new
{
    my $class = shift;
    my ($closures_ref) = @_;

    bless { 'closures' => $closures_ref }, $class;
}

sub run
{
    die sprintf q{Abtract method 'run' should be defined in %s class},
        ref shift;
}

sub _def_method
{
    my ($class, $name) = @_;

    no strict 'refs';
    *{ "${class}::$name" } = sub {
        my $self  = shift;
        my $ret = eval { $self->{'closures'}{$name}->( @_ ) };
        Carp::confess( qq{Peu::Ext method "$name" failed: $@} ) if $@;
        return $ret;
    };
}

BEGIN {
    __PACKAGE__->_def_method( $_ ) for qw/ liason wrap mid attrib /;
}


1;

__END__
