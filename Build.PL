use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Peu',
    license             => 'perl',
    dist_author         => q{Justin Davis <juster@cpan.org>},
    dist_version_from   => 'lib/Peu.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Peu-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
