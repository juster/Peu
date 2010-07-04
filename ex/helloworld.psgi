#!/usr/bin/perl

use Peu;

sub hello  :ANY(/) :VIEW(hello) {}

sub war    :ANY(/war)
{
    $Prm{ 'name' }  = 'war';
    $Prm{ 'value' } = 'good for absolutely nothing';
    return;
}

sub keyval :ANY(/{name}/{value}) :VIEW(keyval) {}
# Return undef to pass our parameters directly to our view.

FIN;

__DATA__
__hello__
<h1>Hello, Plack!  My name is Peu!</h1>

__keyval__
<h1>I guess this means {{name}} = {{value}}</h1>
