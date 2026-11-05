# git2html

A utility to generate static HTML from a git repository, suitable for serving with any web server.

## Version
0.1.0

## Getting the Source

The project website is [git.engenforge.com/git2html](https://git.engenforge.com/git2html), and the primary repository is:

```sh
git clone https://git.engenforge.com/git2html.git
```

The repository is mirrored at:
- `https://gitlab.com/engenforge/git2html.git`
- `https://github.com/engenforge/git2html.git`

Release tarballs and `SHA256SUMS` are published at:
- Primary: `https://get.engenforge.com/git2html/0.1.0/`
- Mirrors:
  - `https://gitlab.com/engenforge/git2html/-/releases`
  - `https://github.com/engenforge/git2html/releases`

## Features
- Browse files from the latest commit.
- View git log.
- Convert README.md to formatted HTML.
- Syntax highlighting for source code.
- Forge-like appearance (Codeberg/Forgejo style).
- Output conforms to the [WebVeld specification](https://webveld.org).
- Reproducible: rebuilding unchanged input produces byte-identical output.
- Binary files are published verbatim; WebVeld-compatible files like PNG and JPEG are displayed directly, while other binary files receive a download landing page.

## Requirements

`git2html` builds to a single static binary with no run-time dependency on
Lua, lpeg, or any of its other vendored libraries -- everything is compiled
in (see `src/bundle_main.c`). At run time it only needs:
- `git`

### User build dependencies
To build and install from source, users only need:
- a C compiler: `musl-gcc` (recommended on glibc distributions) or `gcc` (used directly on Alpine Linux or as fallback)
- `make`
- a Lua interpreter, any version (used only by the build's bundling step;
  not needed to run the resulting binary)

Pre-generated man pages are tracked in git under `doc/man/`, so `scdoc` is
not required for users to build or install.

### Developer dependencies
Developers working on `git2html` or running the test suite additionally need:
- `git` (for creating test repository fixtures)
- `pkg-config` and Lua development headers matching the system Lua interpreter
  (to compile `vendor/lpeg.so` against the active Lua ABI for `make test`)
- `scdoc >= 1.11.5` (optional: needed to rebuild `doc/man/git2html.1` via `make man` and
  run the man page validation tests; tests skip if absent or older than 1.11.5)
- `webveld-validate` (optional: needed to run the WebVeld specification
  conformance tests; tests skip if absent)

You can verify your environment anytime with `make check-user-deps` or `make check-dev-deps`.

## Building

```sh
make        # builds build/git2html and the man page
make test   # runs the test suite against src/git2html.lua directly
make install PREFIX=/usr/local
```

## Usage
`git2html [-v] [-Q] [-c clone-url-base] [-r release-url-base] [-f footer-file] [-h header-file] [-l lang] [-t theme] <repo-path-or-url> <output-dir> [strip-path] [theme]`

By default git2html prints one progress line per repository and per directory. `-Q` (or `--quiet`) suppresses all normal output, including the final completion message; errors are still reported. `-v` adds per-file detail.

`-t` selects the theme directly, without needing an empty `""` placeholder for `strip-path` to reach the positional `[theme]` argument.

`-h` is a custom HTML header shown above the navigation bar on every page, the same way `-f` provides a custom footer. Both support a `{{date}}` token that's replaced with the generation timestamp.

`-c` shows a "Git clone via ..." line above the file listing on each repository's Files page. git2html has no way to know the URL its own output will be served from, so this is opt-in: give it the base URL (e.g. `-c https://git.example.com`) and it appends each repository's own path plus `.git` to build that repository's clone URL.

`-r` shows a "Releases available at ..." line directly below the clone line on each repository's Files page. Give it the base URL (e.g. `-r https://git.example.com`) and it appends `/<repo-name>/archive/` to build the release folder URL. Omitted by default.


## Repository descriptions

The one-line description shown for each repository in a discovery listing comes from git's own per-repository description file: `.git/description` for a regular repository, or `description` at the root of a bare one. `git init` creates it with a placeholder; git2html treats that default as no description and shows "No description provided." instead. Replace its contents with a real summary:

```sh
echo "A one-line summary" > myrepo/.git/description
```

## Themes

Four themes ship with the tool: `auto` (the default; light and dark, following
the reader's system preference), `light`, `dark`, and `monochrome`. Any path
ending in `.css` is used directly instead, which is how a site shares one style sheet
between its own pages and its repository pages:

```bash
git2html repos/ out/git "" ./theme/style.css
```

All four bundled themes implement the same class vocabulary, so a custom style
sheet written against any of them styles every page:

| Class | Applies to |
| :--- | :--- |
| `.site-container` | Page wrapper |
| `.skip` | Skip-to-content link, hidden until focused |
| `.masthead`, `.nav` | Header, navigation |
| `.page` | Main landmark (`id="content"`) |
| `.listing`, `.col-*` | File, directory and commit tables |
| `.readme` | Rendered markdown |
| `.colophon` | Footer |
| `.hl-*` | Syntax highlighting tokens |

The highlighter emits `hl-comment`, `hl-identifier`, `hl-keyword`, `hl-number`,
`hl-operator`, `hl-self`, `hl-string`, `hl-type` and `hl-variable`.
`hl-identifier` is ordinary code text and is left unstyled by design.

Note that WebVeld section 6.7 forbids CSS custom properties, so a theme that
differs from another only by colour cannot be expressed as a variable
override — generate the variant by substitution at build time.

## Installation
```bash
make
sudo make install
```
