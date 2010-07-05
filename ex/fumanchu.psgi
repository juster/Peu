#-*- Mode: cperl -*-
use Peu;

my $foo = 'foolish';

sub test :ANY(/) :VIEW(fubar)
{
    return { 'foo' => $foo, 'bar' => 'barouque' };
}

sub foobar :ANY(/{foo}/{bar}) :VIEW(fubar) {}

FIN

__DATA__
__fubar__
<h1>This is a test, this is only a test, do not be alarmed.</h1>
<h2>Foo is {{foo}} and bar is {{bar}}.</h2>
