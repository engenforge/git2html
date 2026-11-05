git2html(1)

# NAME

git2html - generate static HTML from a git repository

# SYNOPSIS

*git2html* [-v] [-Q] [-p] [-c <clone-url-base>] [-r <release-url-base>] [-f <footer-file>] [-h <header-file>] [-l <lang>] [-t <theme>] <repo-path-or-url> <output-dir> [strip-path] [theme]

# DESCRIPTION

*git2html* generates a folder containing static HTML files and supporting
files that can be served by a web server. It provides a forge-like appearance
similar to Codeberg or Forgejo.

The utility can process a single repository or walk a directory tree to
automatically discover all repositories and create a multi-level index.

The generated site includes:
- A hierarchical file listing for the latest commit (HEAD).
- Individual file views with syntax highlighting.
- A git log view.
- A rendered README.md if present.

# OPTIONS

*-v*
	Increase verbosity. Prints incremental steps during generation.

*-Q*, *--quiet*
	Quiet mode. Suppresses all normal output, including the progress lines
	printed by default and the final completion message. Errors are still
	reported.

*-p*, *--prune*
	Remove files and empty directories in the destination that are not part
	of what is generated.

*-c* <clone-url-base>
	Show a "Git clone via ..." line above the file listing on each
	repository's Files page. git2html appends the repository's own path
	(and *.git*) to <clone-url-base> to build each repository's clone URL,
	e.g. *-c https://git.example.com* produces
	*https://git.example.com/myrepo.git* for a repository named *myrepo*.
	Omitted by default: git2html has no other way to know the URL its own
	output will be served from.

*-r* <release-url-base>
	Show a "Releases available at ..." line directly below the clone line
	on each repository's Files page. git2html appends */<repo-name>/archive/*
	to <release-url-base> to build the release folder URL, e.g.
	*-r https://git.example.com* produces
	*https://git.example.com/myrepo/archive/* for a repository named *myrepo*.
	Omitted by default.


*-f* <footer-file>
	Path to an HTML file to use as a custom footer on every page. The token
	*{{date}}* in this file will be replaced with the generation timestamp.

*-h* <header-file>
	Path to an HTML file to use as a custom header on every page, shown
	above the navigation bar. Supports the *{{date}}* token as *-f* does.

*-l* <lang>
	Language tag for the *lang* attribute on the *html* element, which the
	WebVeld specification requires (section 4.1). Defaults to *en*.

*-t* <theme>
	Select the theme without needing an empty *""* placeholder for
	*strip-path*. Takes precedence over the positional *[theme]* argument.
	See *ARGUMENTS* below for the accepted values.

# ARGUMENTS

*<repo-path-or-url>*
	The path to a local git repository or a public URL (http, https, git, ssh).

*<output-dir>*
	The directory where the static site will be generated.

*[strip-path]*
	An optional path to strip from the front of the repository path to determine
	the project name. For example, if the repo is at */git/user/project* and
	*strip-path* is */git/*, the project will be named *user/project*. This
	enables hierarchical breadcrumbs in the website header.

*[theme]*
	The name of a built-in theme (*auto*, *light*, *dark*, *monochrome*) or a
	path to a custom CSS file. Defaults to *auto*. One copy is written to the
	root of the output directory and linked relatively from every page.

	*auto* carries both a light and a dark palette and follows the reader's
	system preference via *@media (prefers-color-scheme)*; the other three are
	single-palette. All four implement the same class vocabulary, so a custom
	CSS file written against any of them styles every page.

# REPOSITORY DESCRIPTIONS

The one-line description shown for each repository in a discovery listing
comes from git's own per-repository description file: *.git/description* for
a regular repository, or *description* at the root of a bare one. This is the
same file *git init* creates with a placeholder text; git2html treats that
default placeholder as no description and shows *No description provided.*
in its place. Replace its contents with a real summary to have it appear:

	echo "A one-line summary" > myrepo/.git/description

# INCREMENTAL BUILDS

If an output file already exists in the destination and has a modification
timestamp newer than its corresponding source file, *git2html* skips
regenerating it. If the source file has been modified since the output was
last generated, the output file is rebuilt. Combined with *-p*, *git2html*
performs clean, fast incremental site generation.

# REPRODUCIBILITY

Output is a function of the repository, not of the clock. The generation date
shown in each page footer is the date of the repository's last commit, so
rebuilding unchanged input produces byte-identical output: *rsync*(1) transfers
only what really changed, and a rebuild is distinguishable from a change.

Set *SOURCE_DATE_EPOCH* to override the date, per the reproducible-builds
convention. Only if neither is available does the current time get used.

# BINARY FILES

A file containing a NUL byte in its first block is treated as binary. It is
copied into the output verbatim and given a landing page describing it and
linking to it, so an image referenced from a README resolves and any asset can
be downloaded. Text files are rendered with syntax highlighting as before.

# CONFORMANCE

The generated HTML conforms to the WebVeld specification. Pages carry no
scripts, no inline style attributes, and no cross-origin subresources, and
all links are relative so the output tree can be browsed from the filesystem
with a *file://* URL as well as served over HTTP.

Themes are plain CSS restricted to the WebVeld property subset. Note that
custom properties (CSS variables) are forbidden by section 6.7, so a theme
that varies only by colour must be generated by substitution at build time
rather than by overriding variables at run time.

# SEE ALSO

git(1)
