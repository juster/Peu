#!/usr/bin/perl

package PMTidy;

use warnings;
use strict;

use Peu;

any '/pmtidy-1.3.pl' => sub {
    my $code = $Req->param( 'code' );
    'Hello, World!'
};

post '/api/{version}/{tag}' => sub {
    my $code = $Req->param( 'code' );
};

print STDERR $Rtr->as_string;
print "$_\n" foreach keys %PMTidy::;
