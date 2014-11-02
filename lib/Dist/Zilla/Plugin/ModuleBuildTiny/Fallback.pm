use strict;
use warnings;
package Dist::Zilla::Plugin::ModuleBuildTiny::Fallback;
# ABSTRACT: Build a Build.PL that uses Module::Build::Tiny, falling back to Module::Build as needed
# KEYWORDS: plugin installer Module::Build Build.PL toolchain legacy ancient backcompat
# vim: set ts=8 sw=4 tw=78 et :

use Moose;
use MooseX::Types;
use MooseX::Types::Moose 'ArrayRef';
with
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::BuildPL',
    'Dist::Zilla::Role::PrereqSource';

use Dist::Zilla::Plugin::ModuleBuild;
use Dist::Zilla::Plugin::ModuleBuildTiny;
use List::Util 'first';
use Scalar::Util 'blessed';
use namespace::autoclean;

has mb_version => (
    is  => 'ro', isa => 'Str',
    # <mst> 0.28 is IIRC when install_base changed incompatibly
    default => '0.28',
);

has mbt_version => (
    is  => 'ro', isa => 'Str',
);

has plugins => (
    isa => ArrayRef[role_type('Dist::Zilla::Role::BuildPL')],
    lazy => 1,
    default => sub {
        my $self = shift;
        my %args = (
            plugin_name => 'ModuleBuildTiny::Fallback',
            zilla => $self->zilla,
            $self->can('default_jobs') ? ( default_jobs => $self->default_jobs ) : (),
        );
        [
            Dist::Zilla::Plugin::ModuleBuild->new(%args, mb_version => $self->mb_version),
            Dist::Zilla::Plugin::ModuleBuildTiny->new(%args, $self->mbt_version ? ( version => $self->mbt_version ) : ()),
        ]
    },
    traits => ['Array'],
    handles => { plugins => 'elements' },
);

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        plugins => [
            map {
                my $plugin = $_;
                my $config = $plugin->dump_config;
                +{
                    class   => $plugin->meta->name,
                    name    => $plugin->plugin_name,
                    version => $plugin->VERSION,
                    (keys %$config ? (config => $config) : ()),
                }
            } $self->plugins
        ],
    };

    return $config;
};
sub before_build
{
    my $self = shift;

    my @plugins = grep { $_->isa(__PACKAGE__) } @{ $self->zilla->plugins };
    $self->log_fatal('two [ModuleBuildTiny::Fallback] plugins detected!') if @plugins > 1;
}

my %files;

sub gather_files
{
    my $self = shift;

    foreach my $plugin ($self->plugins)
    {
        if ($plugin->can('gather_files'))
        {
            # if a Build.PL was created, remove it from the file list and save it for later
            $plugin->gather_files;
            if (my $build_pl = first { $_->name eq 'Build.PL' } @{ $self->zilla->files })
            {
                $self->log_debug('setting aside Build.PL created by ' . blessed($plugin));
                $files{ blessed $plugin } = $build_pl;
                $self->zilla->prune_file($build_pl);
            }
        }
    }

    # put the Module::Build::Tiny file back in the file list in case other
    # plugins want to add to its content
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}) { push @{ $self->zilla->files }, $file }

    return;
}

sub register_prereqs
{
    my $self = shift;

    # we don't need MB's configure_requires because if Module::Build runs,
    # configure_requires wasn't being respected anyway
    my ($mb, $mbt) = $self->plugins;
    $mbt->register_prereqs;
}

sub setup_installer
{
    my $self = shift;

    my ($mb, $mbt) = $self->plugins;

    # remove the MBT file that we left in since gather_files
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}) { $self->zilla->prune_file($file) }

    # let [ModuleBuild] create (or update) the Build.PL file and its content
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuild'}) { push @{ $self->zilla->files }, $file }

    $self->log_debug('generating Build.PL content from [ModuleBuild]');
    $mb->setup_installer;

    # find the file object, save its content, and delete it from the file list
    my $mb_build_pl = $files{'Dist::Zilla::Plugin::ModuleBuild'}
        || first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
    $self->zilla->prune_file($mb_build_pl);
    my $mb_content = $mb_build_pl->content;

    # comment out the 'use' line; save the required version
    $mb_content =~ s/This (?:Build.PL|file) /This section /m;
    $mb_content =~ s/^use (Module::Build) ([\d.]+);/require $1; $1->VERSION($2);/m;
    $mb_content =~ s/^(?!$)/    /mg;

    # now let [ModuleBuildTiny] create (or update) the Build.PL file and its content
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}) { push @{ $self->zilla->files }, $file }
    $self->log_debug('generating Build.PL content from [ModuleBuildTiny]');
    $mbt->setup_installer;

    # find the file object, and fold [ModuleBuild]'s content into it
    my $mbt_build_pl = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}
        || first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
    my $mbt_content = $mbt_build_pl->content;

    # comment out the 'use' line; save the required version
    $mbt_content =~ s/^(use Module::Build::Tiny ([\d.]+);)$/# $1/m;
    my $mbt_version = $2;
    $mbt_content =~ s/This (?:Build.PL|file) /This section /m;
    $mbt_content =~ s/^(?!$)/    /mg;

    my $message = join('', <DATA>);

    $mbt_build_pl->content(
        <<"FALLBACK",
# This Build.PL for ${\ $self->zilla->name } was generated by
# ${\ ref $self } ${ \($self->VERSION || '<self>') }
use strict;
use warnings;

if (eval 'use Module::Build::Tiny $mbt_version; 1')
{
    print "Congratulations, your toolchain understands 'configure_requires'!\\n\\n";

$mbt_content}
else
{
    \$ENV{PERL_MB_FALLBACK_SILENCE_WARNING} or warn <<'EOW';
$message
EOW
    sleep 10 if -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT));

$mb_content}
FALLBACK
    );

    return;
}

__PACKAGE__->meta->make_immutable;

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [ModuleBuildTiny::Fallback]

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that provides a F<Build.PL> in your
distribution that attempts to use L<Module::Build::Tiny> when available,
falling back to L<Module::Build> when it is missing.

This is useful when your distribution is installing on an older perl (before
approximately 5.10.1) with a toolchain that has not been updated, where
C<configure_requires> metadata is not understood and respected -- or where
F<Build.PL> is being run manually without the user having read and understood
the contents of F<META.yml> or F<META.json>.

When the L<Module::Build> fallback code is run, an added preamble is printed:

=over 4

=for stopwords cpanminus

=for comment This section was inserted from the DATA section at build time

{{ $DATA }}

=back

=for stopwords ModuleBuild

This plugin internally calls both the
L<[ModuleBuildTiny]|Dist::Zilla::Plugin::ModuleBuildTiny>
and L<[ModuleBuild]|Dist::Zilla::Plugin::ModuleBuild> plugins to fetch their
normal F<Build.PL> file contents, combining them together into the final
F<Build.PL> for the distribution.

=for Pod::Coverage before_build gather_files register_prereqs setup_installer

=head1 CONFIGURATION OPTIONS

=head2 mb_version

Optional. Specifies the minimum version of L<Module::Build> needed for proper
fallback execution. Defaults to 0.28.

=head2 mbt_version

Optional.
Passed to L<[ModuleBuildTiny]|Dist::Zilla::Plugin::ModuleBuildTiny> as C<version>:
the minimum version of L<Module::Build::Tiny> to depend on (in
C<configure_requires> as well as a C<use> assertion in F<Build.PL>).

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-ModuleBuildTiny-Fallback>
(or L<bug-Dist-Zilla-Plugin-ModuleBuildTiny-Fallback@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-ModuleBuildTiny-Fallback@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 ACKNOWLEDGEMENTS

=for stopwords Rabbitson ribasushi mst

Peter Rabbitson (ribasushi), for inspiration, and Matt Trout (mst), for not stopping me.

=head1 SEE ALSO

=for :list
* L<Dist::Zilla::Plugin::MakeMaker::Fallback> (which can happily run alongside this plugin)
* L<Dist::Zilla::Plugin::ModuleBuildTiny>
* L<Dist::Zilla::Plugin::ModuleBuild>

=cut

__DATA__
*** WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING ***

If you're seeing this warning, your toolchain is really, really old* and you'll
almost certainly have problems installing CPAN modules from this century. But
never fear, dear user, for we have the technology to fix this!

If you're using CPAN.pm to install things, then you can upgrade it using:

    cpan CPAN

If you're using CPANPLUS to install things, then you can upgrade it using:

    cpanp CPANPLUS

If you're using cpanminus, you shouldn't be seeing this message in the first
place, so please file an issue on github.

This public service announcement was brought to you by the Perl Toolchain
Gang, the irc.perl.org #toolchain IRC channel, and the number 42.

----

* Alternatively, you are running this file manually, in which case you need
to learn to first fulfill all configure requires prerequisites listed in
META.yml or META.json -- or use a cpan client to install this distribution.

You can also silence this warning for future installations by setting the
PERL_MB_FALLBACK_SILENCE_WARNING environment variable, but please don't do
that until you fix your toolchain as described above.
