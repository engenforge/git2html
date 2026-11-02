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

runner.test("markdown to html converts links", function()
    assert(md("[link](url)\n"):match("<a href=\"url\">link</a>"))
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
    f:write("# Top\n\nSee [the guide](doc/guide.md) and [src](src/).\n")
    f:close()
    f = io.open(repo .. "/doc/guide.md", "w")
    f:write("# Guide\n\nBack to [the readme](../README.md).\n"
        .. "External [site](https://example.com/x) and [anchor](#top).\n")
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
    assert(html:match('href="https://example%.com/x"'),
        "external link was rewritten")
    assert(html:match('href="#top"'), "fragment link was rewritten")

    g = io.open(out .. "/git2html-mdlink-repo/README.md.html", "r")
    local top = g:read("*all")
    g:close()
    assert(top:match('href="doc/guide%.md%.html"'), "nested link was not rewritten")
    assert(top:match('href="src/index%.html"'), "directory link was not rewritten")

    os.execute("rm -rf " .. repo .. " " .. out)
end)
runner.summary()
