use strict;
use warnings;

use Test::More 0.88;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;

use Test::Requires { 'Dist::Zilla::Plugin::CheckBin' => '0.004' };

my $tzil = Builder->from_config(
    { dist_root => 'does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ 'ModuleBuildTiny::Fallback' ],
                [ CheckBin => { command => 'ls' } ],
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

my $build_pl = $tzil->slurp_file('build/Build.PL');
unlike($build_pl, qr/[^\S\n]\n/, 'no trailing whitespace in generated Build.PL');

SKIP: {
    skip 'older [ModuleBuildTiny] did not create Build.PL beforehand, so other plugins do not have a chance to insert content first', 2
        if not eval { Dist::Zilla::Plugin::ModuleBuildTiny->VERSION(0.008); 1 };
    cmp_deeply(
        $tzil->log_messages,
        superbagof(
            re(qr/\Q[ModuleBuildTiny::Fallback] something else changed the content of the Module::Build::Tiny version of Build.PL -- maybe you should switch back to [ModuleBuildTiny]?\E \(.*ModuleBuildTiny, via ModuleBuildTiny::Fallback/),
        ),
        'build warned that some extra content was added to Build.PL, possibly making this plugin inadvisable',
    );

    like(
        $build_pl,
    qr/^\s+# This section for DZT-Sample was generated by Dist::Zilla::Plugin::ModuleBuildTiny [\d.]+\.
    use strict;
    use warnings;

    # inserted by Dist::Zilla::Plugin::CheckBin [\d.]+
    use Devel::CheckBin;
    check_bin\('ls'\);$/m,
        'additional Build.PL content is in the Module::Build::Tiny section',
    );
}

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
