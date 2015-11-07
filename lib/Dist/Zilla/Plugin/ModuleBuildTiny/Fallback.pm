use strict;
use warnings;
package Dist::Zilla::Plugin::ModuleBuildTiny::Fallback;
# ABSTRACT: Generate a Build.PL that uses Module::Build::Tiny, falling back to Module::Build as needed
# KEYWORDS: plugin installer Module::Build Build.PL toolchain legacy ancient backcompat
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.021';

use Moose;
with
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::BuildPL',
    'Dist::Zilla::Role::PrereqSource';

use MooseX::Types;
use MooseX::Types::Moose 'ArrayRef';
use Dist::Zilla::Plugin::ModuleBuild;
use Dist::Zilla::Plugin::ModuleBuildTiny;
use Moose::Util 'find_meta';
use List::Util 'first';
use Scalar::Util 'blessed';
use namespace::autoclean;

has mb_version => (
    is => 'ro', isa => 'Str',
    # <mst> 0.28 is IIRC when install_base changed incompatibly
    default => '0.28',
);

has mbt_version => (
    is => 'ro', isa => 'Str',
);

has _extra_args => (
    isa => 'HashRef',
    lazy => 1,
    default => sub { +{} },
    traits => ['Hash'],
    handles => { _extra_args => 'elements' },
);

has plugins => (
    isa => ArrayRef[role_type('Dist::Zilla::Role::BuildPL')],
    init_arg => undef,
    lazy => 1,
    default => sub {
        my $self = shift;
        my %args = (
            zilla => $self->zilla,
            $self->_extra_args,
        );
        [
            Dist::Zilla::Plugin::ModuleBuild->new(
                plugin_name => 'ModuleBuild, via ModuleBuildTiny::Fallback',
                %args,
                mb_version => $self->mb_version,
            ),
            Dist::Zilla::Plugin::ModuleBuildTiny->new(
                plugin_name => 'ModuleBuildTiny, via ModuleBuildTiny::Fallback',
                %args,
                $self->mbt_version ? ( version => $self->mbt_version ) : (),
            ),
        ]
    },
    traits => ['Array'],
    handles => { plugins => 'elements' },
);

around BUILDARGS => sub
{
    my $orig = shift;
    my $self = shift;

    my $args = $self->$orig(@_);

    my %extra_args = %$args;
    delete @extra_args{qw(version mb_version mbt_version zilla plugin_name)};

    return +{
        %$args,
        _extra_args => \%extra_args,
    };
};

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        mb_version => $self->mb_version,
        $self->mbt_version ? ( mbt_version => $self->mbt_version ) : (),
        plugins => [
            map {
                my $plugin = $_;
                my $config = $plugin->dump_config;
                +{
                    class   => find_meta($plugin)->name,
                    name    => $plugin->plugin_name,
                    version => $plugin->VERSION,
                    (keys %$config ? (config => $config) : ()),
                }
            } $self->plugins
        ],
        blessed($self) ne __PACKAGE__ ? ( version => $VERSION ) : (),
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
            # if a Build.PL was created, save it and cache its content
            $plugin->gather_files;
            if (my $build_pl = first { $_->name eq 'Build.PL' } @{ $self->zilla->files })
            {
                $self->log_debug('setting aside Build.PL created by ' . blessed($plugin));
                $files{ blessed $plugin }{file} = $build_pl;
                $files{ blessed $plugin }{content} = $build_pl->content;

                # we leave the MBT version in place; we will fold our content
                # into this object later
                $self->zilla->prune_file($build_pl) if blessed($plugin) eq 'Dist::Zilla::Plugin::ModuleBuild';
            }
        }
    }

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
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}{file})
    {
        $self->zilla->prune_file($file);

        $self->log('something else changed the content of the Module::Build::Tiny version of Build.PL -- maybe you should switch back to [ModuleBuildTiny]?')
            if $file->content ne $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}{content};
    }

    # let [ModuleBuild] create (or update) the Build.PL file and its content
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuild'}{file}) { push @{ $self->zilla->files }, $file }

    $self->log_debug('generating Build.PL content from [ModuleBuild]');
    $mb->setup_installer;

    # find the file object, save its content, and delete it from the file list
    my $mb_build_pl = $files{'Dist::Zilla::Plugin::ModuleBuild'}{file}
        || first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
    $self->zilla->prune_file($mb_build_pl);
    my $mb_content = $mb_build_pl->content;

    # comment out the 'use' line; save the required version
    $mb_content =~ s/This (?:Build.PL|file) /This section /m;
    $mb_content =~ s/^use (Module::Build) ([\d.]+);/require $1; $1->VERSION($2);/m;
    $mb_content =~ s/^(?!$)/    /mg;

    # now let [ModuleBuildTiny] create (or update) the Build.PL file and its content
    if (my $file = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}{file}) { push @{ $self->zilla->files }, $file }
    $self->log_debug('generating Build.PL content from [ModuleBuildTiny]');
    $mbt->setup_installer;

    # find the file object, and fold [ModuleBuild]'s content into it
    my $mbt_build_pl = $files{'Dist::Zilla::Plugin::ModuleBuildTiny'}{file}
        || first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
    my $mbt_content = $mbt_build_pl->content;

    # extract everything added to the head of the file, to put back on top
    # when we are done -- we presume this is content or code meant to stay on top
    $mbt_content =~ s/\A(.*)(\Q# This Build.PL for ${\ $self->zilla->name }\E)/$2/s;
    my $preamble = $1;

    # comment out the 'use' line; adjust preamble comments
    $mbt_content =~ s/^(use Module::Build::Tiny [\d.]+;)$/# $1/m;
    $mbt_content =~ s/This (?:Build.PL|file) /This section /;
    $mbt_content =~ s/^(?!$)/    /mg;

    # ensure MBT interface is still usable
    $mbt_content =~ s/(Build_PL)/Module::Build::Tiny::$1/;

    my $message = join('', <DATA>);

    my $configure_requires = $self->zilla->prereqs->as_string_hash->{configure}{requires};
    delete $configure_requires->{perl};

    # prereq specifications don't always provide exact versions - we just weed
    # those out for now, as this shouldn't occur that frequently.
    delete @{$configure_requires}{ grep { not version::is_strict($configure_requires->{$_}) } keys %$configure_requires };

    $mbt_build_pl->content(
        ( defined $preamble ? $preamble : '' )
        . <<"FALLBACK1"
# This Build.PL for ${\ $self->zilla->name } was generated by
# ${\ ref $self } ${ \($self->VERSION) }
use strict;
use warnings;

my %configure_requires = (
FALLBACK1
    . join('', map {
            "    '$_' => '$configure_requires->{$_}',\n"
        } sort keys %$configure_requires)
    . <<'FALLBACK2'
);

my @missing = grep {
    ! eval "require $_; $_->VERSION($configure_requires{$_}); 1"
} keys %configure_requires;

if (not @missing)
{
FALLBACK2
    . $mbt_content . "}\n"
    . <<'FALLBACK3'
else
{
    if (not $ENV{PERL_MB_FALLBACK_SILENCE_WARNING})
    {
        warn <<'EOW';
FALLBACK3
    . $message . <<'FALLBACK4'
EOW
        sleep 10 if -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT));
    }

FALLBACK4
    .  $mb_content . "}\n"
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

=for stopwords cpanminus

=for comment This section was inserted from the DATA section at build time

=begin :verbatim

{{ $DATA }}

=end :verbatim

=for stopwords ModuleBuild

This plugin internally calls both the
L<[ModuleBuildTiny]|Dist::Zilla::Plugin::ModuleBuildTiny>
and L<[ModuleBuild]|Dist::Zilla::Plugin::ModuleBuild> plugins to fetch their
normal F<Build.PL> file contents, combining them together into the final
F<Build.PL> for the distribution.

You are warned if anything else added content into F<Build.PL> (e.g. some
additional build-time dependency checks), as that code will not run in the
fallback case. It is up to you to decide whether it is still a good idea to use
this plugin in this situation.

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
