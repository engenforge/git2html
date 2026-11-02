local runner = require("test.runner")

local repo = "/tmp/git2html-frontmatter-repo"
local out = "/tmp/git2html-frontmatter-site"

local function render(readme_text)
    os.execute("rm -rf " .. repo .. " " .. out .. " && mkdir -p " .. repo)
    os.execute("git -C " .. repo .. " init >/dev/null 2>&1")
    local f = assert(io.open(repo .. "/README.md", "w"))
    f:write(readme_text)
    f:close()
    os.execute("git -C " .. repo .. " add . && git -C " .. repo ..
        " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m init >/dev/null 2>&1")
    assert(os.execute(runner.bin .. " -Q " .. repo .. " " .. out), "git2html failed")
    local h = assert(io.open(out .. "/git2html-frontmatter-repo/README.md.html"))
    local html = h:read("a")
    h:close()
    os.execute("rm -rf " .. repo .. " " .. out)
    return html
end

runner.test("YAML frontmatter renders as a key/value table", function()
    local html = render("---\nproject: zoril\nstatus: draft\ntitle: \"A <b> title\"\n---\n\n# Heading\n\nBody text.\n")
    assert(html:find('<table class="frontmatter">', 1, true), "no frontmatter table")
    assert(html:find('<tr><th scope="row">project</th><td>zoril</td></tr>', 1, true), "project row wrong")
    assert(html:find('<tr><th scope="row">status</th><td>draft</td></tr>', 1, true), "status row wrong")
    assert(html:find('<tr><th scope="row">title</th><td>A &lt;b&gt; title</td></tr>', 1, true), "title row wrong")
    assert(not html:find("<thead>", 1, true), "frontmatter should be one row per item, not a header row")
    assert(html:find("<h1>Heading</h1>", 1, true), "body not rendered")
    assert(not html:find("project: zoril", 1, true), "raw frontmatter leaked")
end)

runner.test("complex frontmatter falls back to a verbatim block", function()
    local html = render("---\ntags:\n  - a\n  - b\n---\n\nSome body text.\n")
    assert(not html:find('class="frontmatter"', 1, true))
    assert(html:find("<pre", 1, true) and html:find("tags:", 1, true))
    assert(html:find("Some body text.", 1, true))
end)

runner.test("a horizontal rule that is not first is not frontmatter", function()
    local html = render("Intro\n\n---\n\nMore\n")
    assert(not html:find('class="frontmatter"', 1, true))
end)

runner.test("every theme styles the frontmatter table", function()
    for _, name in ipairs({"auto", "light", "dark", "monochrome"}) do
        local f = assert(io.open("themes/" .. name .. ".css"))
        local css = f:read("a")
        f:close()
        local rule = css:match("table%.frontmatter {(.-)}")
        assert(rule, name .. ": no table.frontmatter rule")
        assert(rule:find("border:", 1, true), name .. ": frontmatter has no outline")
        assert(rule:find("background%-color:"), name .. ": frontmatter has no background")
        assert(css:find("table%.frontmatter td {[^}]-text%-align: left"), name .. ": cells not left-aligned")
    end
end)

runner.summary()
