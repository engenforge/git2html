---
project: git2html
status: Active
sprint: 2026-S1
date: 2026-09-02
---

# Current Sprint

- [ ] Fix single-word paragraphs such as "Body." rendering as an empty list item
    A markdown paragraph that is just `Body.` (or similar) renders as `<ol class="list-upper-alpha"><li></li></ol>` and the text is lost. Reproduced against the vendored lunamark with `fancy_lists = true`; `Body text.` renders correctly. Likely the fancy_lists enumerator pattern accepting a multi-character word. Fix in the vendored lunamark reader or constrain the option, and add a regression test in `test/markdown.test.lua`.
