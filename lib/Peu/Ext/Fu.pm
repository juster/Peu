package Peu::Ext::Fu;

use warnings;
use strict;

use Peu::Tmp qw();
our @ISA = qw(Peu::Tmp);

sub to_file
{
    my ($self, $name) = @_;

    return "$name.fu";
}

sub render
{
    my ($self, $text, $params_ref) = @_;

    $text =~ s[ {{ ([^}]+) }} ]
              [ $params_ref->{ $1 } ]gexms;

    return $text;
}

1;

__END__
