package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")
local lunamark = require("lunamark")

local writer = lunamark.writer.html.new()
local parse = lunamark.reader.markdown.new(writer)

local function md(content)
    return (parse(content))
end

runner.test("markdown to html converts headers", function()
    assert(md("# Header\n"):match("<h1>Header</h1>"))
    assert(md("## Subheader\n"):match("<h2>Subheader</h2>"))
end)

runner.test("markdown to html converts paragraphs", function()
    assert(md("Hello world\n\n"):match("<p>Hello world</p>"))
end)

runner.test("fancy_lists does not turn single-word paragraphs like Body. into empty list items", function()
    local fancy_parse = lunamark.reader.markdown.new(writer, { fancy_lists = true })
    local body_html = (fancy_parse("Body.\n\n"))
    assert(body_html:match("<p>Body%.</p>"),
        "expected <p>Body.</p>, got: " .. body_html)
    local multi_html = (fancy_parse("Hello. World.\n\n"))
    assert(multi_html:match("<p>Hello%. World%.</p>"),
        "expected <p>Hello. World.</p>, got: " .. multi_html)
    local alpha_html = (fancy_parse("a. first\nb. second\n\n"))
    assert(alpha_html:match('<ol class="list%-lower%-alpha">'),
        "expected lower-alpha list, got: " .. alpha_html)
    local roman_html = (fancy_parse("ii. first\niii. second\n\n"))
    assert(roman_html:match('<ol class="list%-lower%-roman"'),
        "expected lower-roman list, got: " .. roman_html)
    local indented_roman = (fancy_parse("  ii. first\n  iii. second\n\n"))
    assert(indented_roman:match('<ol class="list%-lower%-roman"'),
        "expected 2-space-indented lower-roman list, got: " .. indented_roman)
    local ill_html = (fancy_parse("ill.\n\n"))
    assert(ill_html:match("<p>ill%.</p>"),
        "expected <p>ill.</p>, got: " .. ill_html)
end)

runner.test("markdown to html converts links", function()
    assert(md("[link](url)\n"):match("<a href=\"url\">link</a>"))
end)

runner.test("image with only width or height closes tag and escapes attributes", function()
    local attr_parse = lunamark.reader.markdown.new(writer, { link_attributes = true })
    local w_only = (attr_parse('![alt](pic.png){width="100"}\n\n'))
    assert(w_only:match('<img src="pic%.png" alt="alt" width="100" />'),
        "expected closed img with width, got: " .. w_only)
    local h_only = (attr_parse('![alt](pic.png){height="50"}\n\n'))
    assert(h_only:match('<img src="pic%.png" alt="alt" height="50" />'),
        "expected closed img with height, got: " .. h_only)
    local escaped = (attr_parse("![alt](pic.png){width='100\"x'}\n\n"))
    assert(escaped:match('width="100&quot;x" />'),
        "expected escaped width attribute and closed img, got: " .. escaped)
end)


-- Links inside rendered markdown must point at the generated pages, not at the
-- source paths. Every file in a repository is published as <path>.html, so a
-- link to ../README.md resolves to nothing once rendered.
runner.test("markdown links are rewritten to the generated pages", function()
    local repo = "/tmp/git2html-mdlink-repo"
    local out = "/tmp/git2html-mdlink-out"
    os.execute("rm -rf " .. repo .. " " .. out)
    os.execute("mkdir -p " .. repo .. "/doc")

    local f = io.open(repo .. "/README.md", "w")
    f:write("# Top\n\nSee [the guide](doc/guide.md), [src](src/), [src bare](src), "
        .. "[html](doc/page.html), and [html sec](doc/page.html#sec).\n")
    f:close()
    f = io.open(repo .. "/doc/guide.md", "w")
    f:write("# Guide\n\nBack to [the readme](../README.md), [page](page.html), "
        .. "[up](..), [here](.), and [up sec](..#files).\n"
        .. "External [site](https://example.com/x) and [anchor](#top).\n")
    f:close()
    f = io.open(repo .. "/doc/page.html", "w")
    f:write("<!DOCTYPE html><html><body><h1>Page</h1></body></html>\n")
    f:close()
    f = io.open(repo .. "/doc/uppercase.MD", "w")
    f:write("# Uppercase\n\nThis is uppercase markdown.\n")
    f:close()
    f = io.open(repo .. "/doc/with_nul.md", "wb")
    f:write("# NUL Markdown\n\nSome text with \0 byte.\n")
    f:close()
    f = io.open(repo .. "/doc/longext.markdown", "w")
    f:write("# Long Extension\n\nMarkdown with .markdown extension.\n")
    f:close()
    f = io.open(repo .. "/doc/alt.mdown", "w")
    f:write("# Alt Extension\n\nMarkdown with .mdown extension.\n")
    f:close()
    f = io.open(repo .. "/doc/fm.md", "w")
    f:write("---\ntitle: Frontmatter Test\nauthor: Alice\n---\n\n# Main Title\n\nBody here.\n")
    f:close()
    os.execute("mkdir -p " .. repo .. "/src && echo 'x = 1' > " .. repo .. "/src/a.lua")

    os.execute("git -C " .. repo .. " init -q >/dev/null 2>&1")
    os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. repo
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm init >/dev/null 2>&1")
    os.execute(runner.bin .. " " .. repo .. " " .. out .. " >/dev/null 2>&1")

    local g = io.open(out .. "/git2html-mdlink-repo/doc/guide.md.html", "r")
    local html = g:read("*all")
    g:close()

    assert(html:match('href="%.%./README%.md%.html"'),
        "relative markdown link was not rewritten")
    assert(html:match('href="page%.html%.html"'),
        "relative .html link was not rewritten to .html.html")
    assert(html:match('href="%.%./index%.html"'),
        "parent directory link .. was not rewritten to ../index.html")
    assert(html:match('href="%./index%.html"'),
        "current directory link . was not rewritten to ./index.html")
    assert(html:match('href="%.%./index%.html#files"'),
        "parent directory link with fragment was not rewritten")
    assert(html:match('href="https://example%.com/x"'),
        "external link was rewritten")
    assert(html:match('href="#top"'), "fragment link was rewritten")

    g = io.open(out .. "/git2html-mdlink-repo/README.md.html", "r")
    local top = g:read("*all")
    g:close()
    assert(top:match('href="doc/guide%.md%.html"'), "nested link was not rewritten")
    assert(top:match('href="src/index%.html"'), "directory link was not rewritten")
    assert(top:match('href="doc/page%.html%.html"'), "nested .html link was not rewritten")
    assert(top:match('href="doc/page%.html%.html#sec"'), "nested .html link with fragment was not rewritten")
    assert(top:match('href="src/index%.html".*href="src/index%.html"'),
        "bare directory link without trailing slash was not rewritten to src/index.html")

    assert(top:match('<div class="readme">'), "rendered markdown container missing in README.md.html")
    assert(not top:match('<pre tabindex="0"><code>'), "raw code block rendered for README.md.html")
    assert(not top:match("Download"), "download link present on README.md.html")
end)

runner.test("clicking a markdown file renders markdown rather than raw text or download link", function()
    local repo = "/tmp/git2html-mdlink-repo"
    local out = "/tmp/git2html-mdlink-out"
    local g_up = io.open(out .. "/git2html-mdlink-repo/doc/uppercase.MD.html", "r")
    local up_html = g_up:read("*all")
    g_up:close()
    assert(up_html:match('<div class="readme">'), "rendered markdown container missing for uppercase .MD")
    assert(up_html:match('<h1>Uppercase</h1>'), "rendered header missing for uppercase .MD")
    assert(not up_html:match('<pre tabindex="0"><code>'), "raw text block rendered for uppercase .MD")
    assert(not up_html:match("Download"), "download link present for uppercase .MD")

    local g_nul = io.open(out .. "/git2html-mdlink-repo/doc/with_nul.md.html", "r")
    local nul_html = g_nul:read("*all")
    g_nul:close()
    assert(nul_html:match('<div class="readme">'), "rendered markdown container missing for binary markdown")
    assert(not nul_html:match("Download"), "download link present for binary markdown")
    assert(not nul_html:match('<pre tabindex="0"><code>'), "raw code block rendered for binary markdown")

    -- .markdown extension
    local g_long = io.open(out .. "/git2html-mdlink-repo/doc/longext.markdown.html", "r")
    local long_html = g_long:read("*all")
    g_long:close()
    assert(long_html:match('<div class="readme">'), "rendered markdown container missing for .markdown")
    assert(long_html:match('<h1>Long Extension</h1>'), "rendered header missing for .markdown")
    assert(not long_html:match('<pre tabindex="0"><code>'), "raw code block rendered for .markdown")

    -- .mdown extension
    local g_mdown = io.open(out .. "/git2html-mdlink-repo/doc/alt.mdown.html", "r")
    local mdown_html = g_mdown:read("*all")
    g_mdown:close()
    assert(mdown_html:match('<div class="readme">'), "rendered markdown container missing for .mdown")
    assert(mdown_html:match('<h1>Alt Extension</h1>'), "rendered header missing for .mdown")

    -- Frontmatter rendering on viewed markdown file
    local g_fm = io.open(out .. "/git2html-mdlink-repo/doc/fm.md.html", "r")
    local fm_html = g_fm:read("*all")
    g_fm:close()
    assert(fm_html:match('<div class="readme">'), "rendered markdown container missing for frontmatter md")
    assert(fm_html:match('<table class="frontmatter">'), "frontmatter table missing")
    assert(fm_html:match('<h1>Main Title</h1>'), "header missing in frontmatter md")

    os.execute("rm -rf " .. repo .. " " .. out)
end)

runner.test("markdown escapes non-comment raw HTML and normalizes skipped heading levels", function()
    local repo = "/tmp/git2html-mdsanitize-repo"
    local out = "/tmp/git2html-mdsanitize-out"
    os.execute("rm -rf " .. repo .. " " .. out)
    os.execute("mkdir -p " .. repo)

    local f = io.open(repo .. "/README.md", "w")
    f:write("# Title\n\n"
        .. "Use <text>, Vec<T>, <point>, and <script>x</script>, plus<br>break.\n\n"
        .. "<!-- hidden -->\n\n"
        .. "### Sec A\n\n"
        .. "#### Sub A1\n\n"
        .. "### Sec B\n")
    f:close()

    os.execute("git -C " .. repo .. " init -q >/dev/null 2>&1")
    os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. repo
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm init >/dev/null 2>&1")
    os.execute(runner.bin .. " " .. repo .. " " .. out .. " >/dev/null 2>&1")

    local g = io.open(out .. "/git2html-mdsanitize-repo/README.md.html", "r")
    local html = g:read("*all")
    g:close()

    assert(html:match("&lt;text&gt;"), "<text> was not escaped")
    assert(html:match("Vec&lt;T&gt;"), "Vec<T> was not escaped")
    assert(html:match("&lt;point&gt;"), "<point> was not escaped")
    assert(html:match("&lt;script&gt;x&lt;/script&gt;"), "<script> was not escaped")
    assert(html:match("<br>"), "<br> was not preserved")
    assert(html:match("<!%-%- hidden %-%->"), "HTML comment was not preserved")
    assert(html:match("<h1>Title</h1>"), "<h1>Title</h1> missing")
    assert(html:match("<h2>Sec A</h2>"), "### Sec A was not normalized to <h2>")
    assert(html:match("<h3>Sub A1</h3>"), "#### Sub A1 was not normalized to <h3>")
    assert(html:match("<h2>Sec B</h2>"), "### Sec B was not normalized to <h2>")

    os.execute("rm -rf " .. repo .. " " .. out)
end)
runner.summary()
