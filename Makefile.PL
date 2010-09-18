use inc::Module::Install;

name     'Peu';
all_from 'lib/Peu.pm';
requires 'parent' => 0;
requires 'Carp'   => 0;
requires 'Plack'  => 0;

WriteAll;
