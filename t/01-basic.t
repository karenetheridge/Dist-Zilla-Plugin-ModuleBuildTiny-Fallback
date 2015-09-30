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
);

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
                    config => superhashof({
                        'Dist::Zilla::Plugin::ModuleBuildTiny::Fallback' => {
                            mb_version => '0.28',
                            plugins => [
                                superhashof({
                                    class => 'Dist::Zilla::Plugin::ModuleBuild',
                                    name => 'ModuleBuild, via ModuleBuildTiny::Fallback',
                                    version => Dist::Zilla::Plugin::ModuleBuild->VERSION,
                                }),
                                superhashof({
                                    class => 'Dist::Zilla::Plugin::ModuleBuildTiny',
                                    name => 'ModuleBuildTiny, via ModuleBuildTiny::Fallback',
                                    version => Dist::Zilla::Plugin::ModuleBuildTiny->VERSION,
                                }),
                            ],
                        },
                        # if new enough, we'll also see:
                        # 'Dist::Zilla::Role::TestRunner' => superhashof({})
                    }),
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
unlike($build_pl, qr/[^\S\n]\n/, 'no trailing whitespace in generated Build.PL');

my $preamble = join('', <*Dist::Zilla::Plugin::ModuleBuildTiny::Fallback::DATA>);
like($build_pl, qr/\Q$preamble\E/ms, 'preamble is found in Build.PL');

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

    my %configure_requires = %{ $tzil->distmeta->{prereqs}{configure}{requires} };
    foreach my $prereq (sort keys %configure_requires)
    {
        if ($prereq eq 'perl')
        {
            unlike(
                $configure_requires_content,
                qr/perl/m,
                '%configure_requires does not contain perl',
            );
        }
        else
        {
            like(
                $configure_requires_content,
                qr/$prereq\W+$configure_requires{$prereq}\W/m,
                "\%configure_requires contains $prereq => $configure_requires{$prereq}",
            );
        }
    }
}

like(
    $build_pl,
    qr/^    # use Module::Build::Tiny/m,
    'use Module::Build::Tiny statement commented out',
);

{
local $TODO = 'qr/...$/m does not work before perl 5.010' if "$]" < '5.010';
like(
    $build_pl,
    qr/^\Q    require Module::Build; Module::Build->VERSION(0.28);\E$/m,
    'use Module::Build statement replaced with require, with our overridden default',
);
}

unlike(
    $build_pl,
    qr/^use Module::Build/m,
    'no uncommented use statement remains',
);

unlike(
    $build_pl,
    qr/^\s*Build_PL/m,
    'unqualified Build_PL sub is not referenced',
);

like(
    $build_pl,
    qr/^\s*Module::Build::Tiny::Build_PL/m,
    '...and replaced by fully-namespaced call',
);

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
