use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaConfig => ],
                [ 'ModuleBuildTiny::Fallback' ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
is(
    exception { $tzil->build },
    undef,
    'build proceeds normally',
) or diag 'saw log messages: ', explain $tzil->log_messages;

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        prereqs => superhashof({
            configure => {
                requires => {
                    'Module::Build::Tiny' => ignore,
                },
            },
        }),
        x_Dist_Zilla => superhashof({
            plugins => supersetof(
                {
                    class => 'Dist::Zilla::Plugin::ModuleBuildTiny::Fallback',
                    config => {
                        'Dist::Zilla::Plugin::ModuleBuildTiny::Fallback' => {
                            plugins => [
                                {
                                    class => 'Dist::Zilla::Plugin::ModuleBuild',
                                    config => superhashof({}),
                                    name => 'ModuleBuildTiny::Fallback',
                                    version => ignore,
                                },
                                {
                                    class => 'Dist::Zilla::Plugin::ModuleBuildTiny',
                                    config => superhashof({}),
                                    name => 'ModuleBuildTiny::Fallback',
                                    version => ignore,
                                },
                            ],
                        },
                        'Dist::Zilla::Role::TestRunner' => superhashof({}),
                    },
                    name => 'ModuleBuildTiny::Fallback',
                    version => ignore,
                },
            ),
        }),
    }),
    'all prereqs are in place; configs are properly included in metadata',
)
or diag 'got metadata: ', explain $tzil->distmeta;

my $build_pl = $tzil->slurp_file('build/Build.PL');
unlike($build_pl, qr/[^\S\n]\n/m, 'no trailing whitespace in generated CONTRIBUTING');

like(
    $build_pl,
    qr/^# This Build.PL for DZT-Sample was generated by\n# Dist::Zilla::Plugin::ModuleBuildTiny::Fallback (<self>|[\d.]+)$/m,
    'header is present',
);

like(
    $build_pl,
    qr/^if \(eval 'use Module::Build::Tiny [\d.]+\; 1'\)/m,
    'use Module::Build::Tiny statement replaced with eval use',
);

like(
    $build_pl,
    qr/^    # use Module::Build::Tiny/m,
    'use Module::Build::Tiny statement commented out',
);

like(
    $build_pl,
    qr/^\Q    require Module::Build; Module::Build->VERSION(0.28);\E$/m,
    'use Module::Build statement replaced with require, with our overridden default',
);

unlike(
    $build_pl,
    qr/^use Module::Build/m,
    'no uncommented use statement remains',
);

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
