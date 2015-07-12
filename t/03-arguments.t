use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;

my $tzil = Builder->from_config(
    { dist_root => 'does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaConfig => ],
                [ 'ModuleBuildTiny::Fallback' => {
                        mb_version => '0.001',
                        mbt_version => '0.002',
                        default_jobs => 5,
                        minimum_perl => '5.010',
                        mb_class => 'Foo::Bar',
                    } ],
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
);

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        prereqs => superhashof({
            configure => {
                requires => {
                    'Module::Build::Tiny' => '0.002',   # from mbt_version -> version
                },
            },
        }),
        x_Dist_Zilla => superhashof({
            plugins => supersetof(
                {
                    class => 'Dist::Zilla::Plugin::ModuleBuildTiny::Fallback',
                    config => superhashof({
                        'Dist::Zilla::Plugin::ModuleBuildTiny::Fallback' => {
                            mb_version => '0.001',
                            mbt_version => '0.002',
                            plugins => [
                                superhashof({
                                    class => 'Dist::Zilla::Plugin::ModuleBuild',
                                    name => 'ModuleBuild, via ModuleBuildTiny::Fallback',
                                    version => Dist::Zilla::Plugin::ModuleBuild->VERSION,
                                    Dist::Zilla::Plugin::ModuleBuild->can('default_jobs')
                                        ? ( config => { 'Dist::Zilla::Role::TestRunner' => superhashof({ default_jobs => 5 }) } )
                                        : ()
                                }),
                                superhashof({
                                    class => 'Dist::Zilla::Plugin::ModuleBuildTiny',
                                    name => 'ModuleBuildTiny, via ModuleBuildTiny::Fallback',
                                    version => Dist::Zilla::Plugin::ModuleBuildTiny->VERSION,
                                    Dist::Zilla::Plugin::ModuleBuildTiny->can('default_jobs')
                                        ? ( config => { 'Dist::Zilla::Role::TestRunner' => superhashof({ default_jobs => 5 }) } )
                                        : ()
                                }),
                            ],
                        },
                        Dist::Zilla::Plugin::ModuleBuildTiny::Fallback->can('default_jobs')
                            ? ( 'Dist::Zilla::Role::TestRunner' => superhashof({ default_jobs => 5 }) )
                            : ()
                    }),
                    name => 'ModuleBuildTiny::Fallback',
                    version => ignore,
                }
            ),
        }),
    }),
    'all prereqs are in place',
)
    or diag 'got metadata: ', explain $tzil->distmeta;

my ($mb, $mbt) = $tzil->plugin_named('ModuleBuildTiny::Fallback')->plugins;
is($mb->mb_version, '0.001', '[ModuleBuild] was passed the "mb_version" argument as "mb_version"');
is($mb->mb_class, 'Foo::Bar', '[ModuleBuild] was passed the "mb_class" argument');
is($mbt->version, '0.002', '[ModuleBuildTiny] was passed the "mbt_version" argument as "version"');
SKIP: {
    if ($mbt->can('minimum_perl'))
    {
        is($mbt->minimum_perl, '5.010', '[ModuleBuildTiny] was passed the "minimum_perl" argument');
    }
    else
    {
        skip '[ModuleBuildTiny] is too old to know "minimum_perl"', 1;
    }
}

my $build_pl = $tzil->slurp_file('build/Build.PL');
unlike($build_pl, qr/[^\S\n]\n/m, 'no trailing whitespace in generated CONTRIBUTING');

like(
    $build_pl,
    qr/^# This Build.PL for DZT-Sample was generated by\n# Dist::Zilla::Plugin::ModuleBuildTiny::Fallback [\d.]+\n^use strict;\n^use warnings;\n/m,
    'header is present',
);

SKIP:
{
    ok($build_pl =~ /^my %configure_requires = \($/mg, 'found start of %configure_requires declaration')
        or skip 'failed to test %configure_requires section', 2;
    my $start = pos($build_pl);

    ok($build_pl =~ /\);$/mg, 'found end of %configure_requires declaration')
        or skip 'failed to test %configure_requires section', 1;
    my $end = pos($build_pl);

    my $configure_requires_content = substr($build_pl, $start, $end - $start - 2);
    like(
        $build_pl,
        qr/['"]Module::Build::Tiny['"].*0\.002/,
        'correct version of Module::Build::Tiny is checked for',
    );
}

like(
    $build_pl,
    qr/^    # use Module::Build::Tiny/m,
    'use Module::Build::Tiny statement commented out',
);

like(
    $build_pl,
    qr/^    require Module::Build; Module::Build->VERSION\(0\.001\);$/m,
    'use Module::Build statement replaced with require',
);

unlike(
    $build_pl,
    qr/^[^#]+use\s+Module::Build/m,
    'no uncommented use statement remains',
);

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
