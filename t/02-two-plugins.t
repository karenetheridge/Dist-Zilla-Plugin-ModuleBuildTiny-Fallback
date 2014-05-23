use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaJSON => ],
                [ 'ModuleBuildTiny::Fallback' => 'Foo' ],
                [ 'ModuleBuildTiny::Fallback' => 'Bar' ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
like(
    exception { $tzil->build },
    qr/two \[ModuleBuildTiny::Fallback\] plugins detected!/,
    'got right exception',
) or diag 'saw log messages: ', explain $tzil->log_messages;

done_testing;
