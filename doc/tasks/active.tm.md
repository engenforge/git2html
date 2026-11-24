# Current Sprint

- [x] Fix single-word paragraphs such as "Body." rendering as an empty list item
    > **Completed:** 2026-11-23

    A markdown paragraph that is just `Body.` (or similar) renders as `<ol class="list-upper-alpha"><li></li></ol>` and the text is lost. Reproduced against the vendored lunamark with `fancy_lists = true`; `Body text.` renders correctly. Likely the fancy_lists enumerator pattern accepting a multi-character word. Fix in the vendored lunamark reader or constrain the option, and add a regression test in `test/markdown.test.lua`.
- [x] Replace raw `string.format` HTML construction with safe-by-default element helpers
    > **Completed:** 2026-11-23

    Introduce lightweight `el(tag, attrs, children)` and `raw(html)` helpers in `src/git2html.lua` that automatically `html_escape` plain string children and `attr_escape` attribute values by default, requiring explicit `raw(...)` opt-out for pre-rendered HTML (markdown, syntax highlighting, nested elements). Migrate table rows, breadcrumbs, navigation, and page templates so forgetting to escape git metadata or paths becomes structurally impossible.
- [x] Fix truncated `<img>` closing tag in vendored lunamark when only `width` or `height` is set
    > **Completed:** 2026-11-23

    In `vendor/lunamark/writer/html.lua` (`Html.image`), `w` or `h` evaluates to `nil` when omitted, which terminates the returned sequence table early and drops the closing ` />` (e.g. `![alt](pic.png){width="100"}` emits `<img src="pic.png" alt="alt" width="100"`). Default missing `w`/`h` to `""`, attribute-escape their values, and add a regression test in `test/markdown.test.lua` and `test/webveld.test.lua`.

- [x] Profile git2html on a large repository to establish a performance baseline +AI-G id:e2zzs
    > **Completed:** 2026-11-24

    Add temporary or reusable timing instrumentation to measure wall-clock time spent in each phase on a large repository (both deep commit history and many files/directories): `git.get_log`, `log.html` rendering, `git.get_bulk_metadata`, `git.ls_files`, `mkdir -p` / filesystem checks, `is_binary`, syntax highlighting, markdown rendering, and file I/O. Record baseline timings so each subsequent optimization can be measured objectively.

- [x] Eliminate O(N^2) string concatenation when building HTML tables +AI-G id:57ggw
    > **Completed:** 2026-11-24

    Replace repeated `rows = rows .. RI .. ...` and `log_rows = log_rows .. RI .. ...` string concatenation loops in `src/git2html.lua` (`generate_repo_site`, `generate_repo_tree`, and `walk_and_process`) with table accumulation (`rows[#rows + 1] = ...`) followed by a single `table.concat`. On repositories with tens of thousands of commits or large directories, repeated concatenation copies the growing string on every iteration. Verify byte-identical HTML output with `make test`.

- [x] Add POSIX filesystem C helpers to src/bundle_main.c to eliminate shell forks +AI-G id:wjaqe
    > **Completed:** 2026-11-24

    Following the existing `c_is_newer` pattern in `src/bundle_main.c`, implement lightweight C helpers backed by POSIX syscalls (`mkdir(2)`, `stat(2)`, `opendir(3)`/`readdir(3)`): `c_mkdir_p`, `c_is_dir`, `c_file_exists`, and `c_readdir`. Wire them into `src/git2html.lua` and `src/git_utils.lua` (keeping pure-Lua fallbacks for host-Lua execution) to replace shell-forking `os.execute("mkdir -p ...")`, per-link `test -d` in `rewrite_md_links`, `test -d`/`test -f` in `git.is_repo`, and `ls -1 -F` in `git.get_subdirs`. Ensure zero compiler warnings under `-Wall -Wextra` and full test coverage via `make test`.

- [x] Add single-pass C HTML and attribute escaping helpers to src/bundle_main.c +AI-G id:v98aq
    > **Completed:** 2026-11-24

    Implement `c_html_escape` and `c_attr_escape` in `src/bundle_main.c` using `luaL_Buffer`, fast-pathing strings that contain no escapable characters (`&`, `<`, `>`, `"`) by returning the original Lua string with zero allocation. Wire them into `html_escape` and `attr_escape` in `src/git2html.lua` (with pure-Lua fallbacks) to replace the 3-4 sequential `string.gsub` passes executed across every table cell, link, and attribute. Verify zero compiler warnings and identical escaping behavior with `make test`.

- [x] Replace per-directory git ls-tree calls with a single recursive git ls-tree -r -z per repository +AI-D id:pvz4s
    > **Completed:** 2026-11-24

    Refactor `git.ls_files` in `src/git_utils.lua` and `generate_repo_tree` in `src/git2html.lua` to invoke `git -C <repo> ls-tree -r -z HEAD` once per repository and build an in-memory directory tree, instead of spawning a separate `git ls-tree` process for every subdirectory. Using `-z` also avoids git path-quoting issues for filenames containing spaces or non-ASCII characters. Add/update unit and integration tests and verify with `make test`.

- [x] Stop git.get_bulk_metadata early once all HEAD files are resolved and use -z output +AI-D id:jy0hs
    > **Completed:** 2026-11-24

    Pass the set of current `HEAD` file paths (from `ls-tree -r -z`) into `git.get_bulk_metadata` in `src/git_utils.lua`. Switch `git log --name-only` to `-z` so filenames match `ls-tree` paths reliably (avoiding cache misses that trigger the slow per-file `git log -1` fallback in `git.ls_files`), track how many `HEAD` files still need metadata, and close the `git log` pipe early as soon as all current files have been seen rather than walking the entire remaining history. Verify with `make test`.

- [x] Skip unnecessary I/O and git history walks on incremental rebuilds +AI-D id:ykxeg
    > **Completed:** 2026-11-24

    In `src/git2html.lua` (`generate_repo_tree`), avoid calling `is_binary(source)` (which opens and reads 8 KiB of every file) before checking `is_newer(html_target, source)` on unchanged files. Additionally, evaluate caching or stamping the rendered `HEAD` commit hash (and relevant CLI/theme inputs) per repository so unchanged repositories in multi-repo runs can skip `git.get_log`, `git.get_bulk_metadata`, and `log.html` regeneration altogether. Add regression tests covering incremental rebuilds and `--prune`.

- [x] Move syntax-highlight token-to-HTML serialization to C (c_tokens_to_html) +AI-D id:txzs7
    > **Completed:** 2026-11-24

    LPeg lexing in `vendor/lpeg` already runs in C, but `vendor/syntaxhighlight/init.lua` allocates intermediate tables and strings per token (`tag_tokens`, `merge_adjacent`) and runs 5 sequential `string.gsub` passes per token in `escape_text`. Implement `c_tokens_to_html(source, tokens, class_map, class_prefix, bare)` in `src/bundle_main.c` to merge adjacent identical token types by advancing `end_pos` and HTML-escape directly into a `luaL_Buffer` in a single pass, calling it from `vendor/syntaxhighlight/init.lua` when available. Verify byte-identical highlighted output across `make test`.

- [x] Evaluate and implement multi-core parallelism for repository or file rendering in C +AI-D id:w4m3h
    > **Completed:** 2026-11-24

    After completing the single-threaded Lua and C optimizations, re-profile on large repositories to determine whether rendering is still CPU-bound. If significant headroom remains, implement worker parallelism in `src/bundle_main.c` (e.g. `fork()` per repository or `pthread`s with independent `lua_State` instances) so multi-repo runs or large file trees scale across CPU cores while preserving deterministic output, progress logging, and clean error/exit handling.

- [x] Add --no-index flag to skip generating the root index.html +AI-G
    > **Completed:** 2026-11-24

    Add a `--no-index` CLI option in `src/git2html.lua` that skips writing the root `<output-dir>/index.html` (in `generate_parent_indexes` and `walk_and_process`) while still generating each repository's own pages and `style.css`. This avoids wasted I/O and eliminates write races when external tools (such as `siteforge`) provide their own repository index. Document the flag in `doc/man/git2html.1.scd` (regenerate `doc/man/git2html.1` via `make man`) and add test coverage.

- [x] Support a repository manifest input with per-repo output path and theme +AI-D
    > **Completed:** 2026-11-24

    Extend `src/git2html.lua` to accept a list of `(repo_path, target_dir, [theme])` entries (e.g. via `--manifest <file>` or `-` for stdin) so callers like `siteforge` can render multiple repositories with custom placement and per-repo theme overrides in a single `git2html` invocation, leveraging native multi-core parallelism (`flush_render_jobs`). Ensure theme/stylesheet placement, `--prune` / `register_expected_dir` tracking, and error handling work cleanly across manifest entries. Document the format and CLI option in `doc/man/git2html.1.scd` (`make man`) and add integration tests.

- [x] Support site-root path substitution, --icon, and masthead/nav merging for custom headers +AI-D
    > **Completed:** 2026-11-24

    Eliminate the need for callers like `siteforge` to post-process every generated `.html` file by supporting native HTML chrome integration in `src/git2html.lua` (`page_shell`, `get_header`, `get_footer`):
    1. Support a site-root / path-to-root offset (e.g. `--root-offset` or substituting `@@PATHTOROOT@@` in custom `-h`/`-f` fragments using the page's relative path back to the site root).
    2. Add an `--icon <href>` option to emit `<link rel="icon" ...>` in `<head>` (resolving relative icon paths against the site root).
    3. Allow merging git2html's `<p class="nav">...</p>` into a placeholder (e.g. `<!-- @@REPONAV@@ -->`) inside a custom `-h` header and omitting the duplicate `<header class="masthead">` wrapper when merged.
    Document the new options/placeholders in `doc/man/git2html.1.scd` (`make man`) and add regression tests.

- [x] Emit bare inner links for `<!-- @@REPONAV@@ -->` to support single-row nav merging
    > **Completed:** 2026-11-24

    In `page_shell` (`src/git2html.lua`), replace `<!-- @@REPONAV@@ -->` with the bare inner links (`nav_html`) instead of wrapping them in `<p class="nav">...</p>`. This stays theme-agnostic while allowing callers (such as `siteforge`) to place `<span class="nav-trail"><!-- @@REPONAV@@ --></span>` directly inside their own `<p class="nav">` for a single-row bar without invalid nested `<p>` tags. Update `doc/man/git2html.1.scd` (`make man`) and update/add tests.

- [x] Add `--prune-targets` flag for per-target pruning in `--manifest` mode
    > **Completed:** 2026-11-24

    In `src/git2html.lua`, `-p`/`--prune` with `--manifest <file|-> <output-dir>` currently calls `clean_destination_tree(output_dir)`, which deletes sibling files in `output_dir` (such as `themes/`, `icon.png`, or `releases/`). Add a `--prune-targets` CLI option that prunes only each manifest entry's `<target-dir>` (`clean_destination_tree(entry.target_output)`) even when `[output-dir]` is provided, while preserving existing `-p`/`--prune` behavior. Document `--prune-targets` in `doc/man/git2html.1.scd` (`make man`), include it in CLI usage text, and add test coverage.

- [x] Include `--manifest` in CLI `--help` / usage output
    > **Completed:** 2026-11-24

    `git2html --help` currently falls through to the `< 2` arguments check in `src/git2html.lua` and prints only the `<repo-path-or-url> <output-dir>` usage line, omitting `--manifest <file|-> [output-dir]` (which is already documented in `git2html(1)`). Add explicit `--help` handling (exiting 0) and include both usage lines (standard and `--manifest`) in the output, with test coverage.
