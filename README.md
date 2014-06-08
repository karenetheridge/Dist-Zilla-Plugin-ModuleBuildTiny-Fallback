# NAME

Dist::Zilla::Plugin::ModuleBuildTiny::Fallback - Build a Build.PL that uses Module::Build::Tiny, falling back to Module::Build as needed

# VERSION

version 0.005

# SYNOPSIS

In your `dist.ini`:

    [ModuleBuildTiny::Fallback]

# DESCRIPTION

This is a [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) plugin that provides a `Build.PL` in your
distribution that attempts to use [Module::Build::Tiny](https://metacpan.org/pod/Module::Build::Tiny) when available,
falling back to [Module::Build](https://metacpan.org/pod/Module::Build) when it is missing.

This is useful when your distribution is installing on an older perl (before
approximately 5.10.1) with a toolchain that has not been updated, where
`configure_requires` metadata is not understood and respected -- or where
`Build.PL` is being run manually without the user having read and understood
the contents of `META.yml` or `META.json`.

When the [Module::Build](https://metacpan.org/pod/Module::Build) fallback code is run, an added preamble is printed:

> \*\*\* WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING \*\*\*
>
> If you're seeing this warning, your toolchain is really, really old\* and you'll
> almost certainly have problems installing CPAN modules from this century. But
> never fear, dear user, for we have the technology to fix this!
>
> If you're using CPAN.pm to install things, then you can upgrade it using:
>
>     cpan CPAN
>
> If you're using CPANPLUS to install things, then you can upgrade it using:
>
>     cpanp CPANPLUS
>
> If you're using cpanminus, you shouldn't be seeing this message in the first
> place, so please file an issue on github.
>
> This public service announcement was brought to you by the Perl Toolchain
> Gang, the irc.perl.org #toolchain IRC channel, and the number 42.
>
> \----
>
> \* Alternatively, you are running this file manually, in which case you need
> to learn to first fulfill all configure requires prerequisites listed in
> META.yml or META.json -- or use a cpan client to install this distribution.
>
> You can also silence this warning for future installations by setting the
> PERL\_MB\_FALLBACK\_SILENCE\_WARNING environment variable, but please don't do
> that until you fix your toolchain as described above.

This plugin internally calls both the
[\[ModuleBuildTiny\]](https://metacpan.org/pod/Dist::Zilla::Plugin::ModuleBuildTiny)
and [\[ModuleBuild\]](https://metacpan.org/pod/Dist::Zilla::Plugin::ModuleBuild) plugins to fetch their
normal `Build.PL` file contents, combining them together into the final
`Build.PL` for the distribution.

# CONFIGURATION OPTIONS

## mb\_version

Optional. Specifies the minimum version of [Module::Build](https://metacpan.org/pod/Module::Build) needed for proper
fallback execution. Defaults to 0.28.

## mbt\_version

Optional.
Passed to [\[ModuleBuildTiny\]](https://metacpan.org/pod/Dist::Zilla::Plugin::ModuleBuildTiny) as `version`:
the minimum version of [Module::Build::Tiny](https://metacpan.org/pod/Module::Build::Tiny) to depend on (in
`configure_requires` as well as a `use` assertion in `Build.PL`).

# SUPPORT

Bugs may be submitted through [the RT bug tracker](https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-ModuleBuildTiny-Fallback)
(or [bug-Dist-Zilla-Plugin-ModuleBuildTiny-Fallback@rt.cpan.org](mailto:bug-Dist-Zilla-Plugin-ModuleBuildTiny-Fallback@rt.cpan.org)).
I am also usually active on irc, as 'ether' at `irc.perl.org`.

# ACKNOWLEDGEMENTS

Peter Rabbitson (ribasushi), for inspiration, and Matt Trout (mst), for not stopping me.

# SEE ALSO

- [Dist::Zilla::Plugin::MakeMaker::Fallback](https://metacpan.org/pod/Dist::Zilla::Plugin::MakeMaker::Fallback) (which can happily run alongside this plugin)
- [Dist::Zilla::Plugin::ModuleBuildTiny](https://metacpan.org/pod/Dist::Zilla::Plugin::ModuleBuildTiny)
- [Dist::Zilla::Plugin::ModuleBuild](https://metacpan.org/pod/Dist::Zilla::Plugin::ModuleBuild)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
