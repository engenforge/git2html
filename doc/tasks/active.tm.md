# Current Sprint

- [x] Fix single-word paragraphs such as "Body." rendering as an empty list item
    > **Completed:** 2026-11-23

    A markdown paragraph that is just `Body.` (or similar) renders as `<ol class="list-upper-alpha"><li></li></ol>` and the text is lost. Reproduced against the vendored lunamark with `fancy_lists = true`; `Body text.` renders correctly. Likely the fancy_lists enumerator pattern accepting a multi-character word. Fix in the vendored lunamark reader or constrain the option, and add a regression test in `test/markdown.test.lua`.
- [x] Replace raw `string.format` HTML construction with safe-by-default element helpers
    > **Completed:** 2026-11-23

    Introduce lightweight `el(tag, attrs, children)` and `raw(html)` helpers in `src/git2html.lua` that automatically `html_escape` plain string children and `attr_escape` attribute values by default, requiring explicit `raw(...)` opt-out for pre-rendered HTML (markdown, syntax highlighting, nested elements). Migrate table rows, breadcrumbs, navigation, and page templates so forgetting to escape git metadata or paths becomes structurally impossible.
- [ ] Fix truncated `<img>` closing tag in vendored lunamark when only `width` or `height` is set
    In `vendor/lunamark/writer/html.lua` (`Html.image`), `w` or `h` evaluates to `nil` when omitted, which terminates the returned sequence table early and drops the closing ` />` (e.g. `![alt](pic.png){width="100"}` emits `<img src="pic.png" alt="alt" width="100"`). Default missing `w`/`h` to `""`, attribute-escape their values, and add a regression test in `test/markdown.test.lua` and `test/webveld.test.lua`.
