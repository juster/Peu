# -*- Mode: cperl -*-

use warnings;
use strict;

use Peu;

any '/' => sub {
    'Hello, Plack!  My name is Peu!';
};

to_app();
