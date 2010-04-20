#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Peu' ) || print "Bail out!
";
}

diag( "Testing Peu $Peu::VERSION, Perl $], $^X" );
