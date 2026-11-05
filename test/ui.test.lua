-- UI regressions on the generated page shell.
--
-- These assertions moved with the WebVeld conformance work: footer spacing and
-- table column proportions used to be carried by an inline style attribute and
-- an inline <style> block using table-layout and text-overflow. WebVeld
-- section 6.1 forbids the former and 6.2 permits neither property, so both now
-- come from the theme via the shared class vocabulary. What is asserted here is
-- the markup contract the style sheets hang off -- webveld.test.lua asserts
-- conformance itself.

local runner = require("test.runner")

local root_dir = "/tmp/git2html-ui-root"
local temp_repo = root_dir .. "/git2html-ui-repo"
local temp_repo2 = root_dir .. "/git2html-ui-repo2"
local output_dir = "/tmp/git2html-ui-output"

local function build()
    os.execute("rm -rf " .. root_dir .. " && mkdir -p " .. temp_repo .. " " .. temp_repo2)
    os.execute("git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/f && git -C " .. temp_repo
        .. " add f && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/long.txt && git -C " .. temp_repo
        .. " add long.txt && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'This is a very long commit message that definitely exceeds the fifty character limit for description truncation' >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/short.txt && git -C " .. temp_repo
        .. " add short.txt && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'Short description' >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/quoted.txt && git -C " .. temp_repo
        .. ' add quoted.txt && git -C ' .. temp_repo .. ' -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m \'fix: handle "quoted" values in commit messages properly across trees\' >/dev/null 2>&1')
    os.execute("mkdir -p " .. temp_repo .. "/subdir/deep && touch " .. temp_repo .. "/subdir/subfile " .. temp_repo .. "/subdir/deep/nested && git -C " .. temp_repo
        .. " add subdir/subfile subdir/deep/nested && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'add subdir and nested' >/dev/null 2>&1")
    os.execute("git -C " .. temp_repo2 .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo2 .. "/f && git -C " .. temp_repo2
        .. " add f && git -C " .. temp_repo2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    os.execute("rm -rf " .. output_dir)
    os.execute(runner.bin .. " " .. root_dir .. " " .. output_dir .. " " .. root_dir .. " >/dev/null 2>&1")
end

local function read(path)
    local f = assert(io.open(path, "r"), "missing generated page: " .. path)
    local html = f:read("*all")
    f:close()
    return html
end

build()

runner.test("UI regression: footer carries the colophon class, not inline style", function()
    local html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(html:match('<footer class="colophon">'), "Footer colophon class missing")
    assert(not html:match('<footer style='), "Footer still carries an inline style attribute")
end)

runner.test("UI regression: index table declares column proportions via colgroup", function()
    local html = read(output_dir .. "/index.html")
    assert(html:match('<table class="listing">'), "Listing table class missing")
    assert(html:match('<col class="col%-name">'), "Name column missing")
    assert(html:match('<col class="col%-desc">'), "Description column missing")
    assert(html:match('<col class="col%-changed">'), "Last Changed column missing")
    assert(not html:match("table%-layout"), "Forbidden table-layout survived")
    assert(not html:match("text%-overflow"), "Forbidden text-overflow survived")
end)

runner.test("UI regression: log table declares its own column proportions", function()
    local html = read(output_dir .. "/git2html-ui-repo/log.html")
    assert(html:match('<col class="col%-hash">'), "Hash column missing")
    assert(html:match('<col class="col%-subject">'), "Subject column missing")
    assert(html:match('<col class="col%-author">'), "Author column missing")
end)

runner.test("UI regression: page shell matches the shared theme contract", function()
    -- Neither shell carries a brand heading: the nav already says
    -- "Repositories" at the top level, and already names the repo on a
    -- repo page -- a separate heading repeating either was the
    -- duplicated-title problem the nav redesign fixed.
    local root_html = read(output_dir .. "/index.html")
    assert(not root_html:match('<h1 class="brand">'), "Root shell unexpectedly carries a brand heading")

    local html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(html:match('<html lang="en">'), "Document language missing")
    assert(html:match('<div class="site%-container">'), "Site container missing")
    assert(html:match('<a class="skip" href="#content">'), "Skip link missing")
    assert(html:match('<header class="masthead">'), "Masthead missing")
    assert(not html:match('<h1 class="brand">'), "Repo page unexpectedly carries a brand heading")
    assert(html:match('<main class="page" id="content" tabindex="%-1">'), "Main landmark missing")
    assert(html:match('name="color%-scheme" content="light dark"'), "Colour-scheme hint missing")

    -- At the repo root, a content <h2> breadcrumb would just repeat the
    -- repo name the nav already names -- the same duplicated-title problem
    -- one level down.
    assert(not html:match("<h2>"), "Repo root Files page has a redundant breadcrumb heading")
end)

runner.test("UI regression: navigation links", function()
    local root_html = read(output_dir .. "/index.html")
    assert(root_html:match('<a href="index.html">Repositories</a>'), "Root Repositories link missing")
    assert(not root_html:match('Global Log'), "Global Log should not be in root index")

    local repo_html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(repo_html:match('<p class="nav">'), "Nav paragraph missing")
    assert(repo_html:match('<a href="../index.html">Repositories</a>'), "Repo Repositories link incorrect")
    assert(repo_html:match('<a href="index.html">git2html%-ui%-repo</a>'), "Repo name link missing")
    assert(repo_html:match('<a href="log.html">Log</a>'), "Repo Log link missing")
end)

runner.test("UI regression: source views are keyboard-scrollable", function()
    -- overflow-x on pre makes a wide block a scroll region; without tabindex a
    -- keyboard-only reader cannot reach the clipped half (spec section 5.1).
    local html = read(output_dir .. "/git2html-ui-repo/f.html")
    assert(html:match('<pre tabindex="0">'), "Code block is not focusable")
end)

runner.test("UI regression: listing table is wrapped in a keyboard-scrollable listing-pane", function()
    local html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(html:match('<div class="listing%-pane" tabindex="0">%s*<table class="listing">'),
        "Listing table is not wrapped in a focusable listing-pane container")
end)

runner.test("UI regression: only the main landing page has a scrollable list, other pages display without a scroll box", function()
    -- Main landing page of first repo has listing-pane
    local main_html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(main_html:match('class="listing%-pane"'),
        "Main repo landing page must have a listing-pane scroll box")

    -- Main landing page of second repo has listing-pane
    local main_html2 = read(output_dir .. "/git2html-ui-repo2/index.html")
    assert(main_html2:match('class="listing%-pane"'),
        "Second repo main landing page must have a listing-pane scroll box")

    -- Subdirectory does NOT have listing-pane
    local sub_html = read(output_dir .. "/git2html-ui-repo/subdir/index.html")
    assert(not sub_html:match('class="listing%-pane"'),
        "Subdirectory listing table should not be wrapped in a listing-pane scroll box")
    assert(sub_html:match('<table class="listing">'),
        "Subdirectory should still display the listing table")

    -- Deeply nested subdirectory does NOT have listing-pane
    local deep_html = read(output_dir .. "/git2html-ui-repo/subdir/deep/index.html")
    assert(not deep_html:match('class="listing%-pane"'),
        "Deep subdirectory listing table should not be wrapped in a listing-pane scroll box")
    assert(deep_html:match('<table class="listing">'),
        "Deep subdirectory should still display the listing table")

    -- Multi-repo root Repositories index does NOT have listing-pane
    local root_html = read(output_dir .. "/index.html")
    assert(not root_html:match('class="listing%-pane"'),
        "Repositories index table should not be wrapped in a listing-pane scroll box")
end)

runner.test("UI regression: descriptions longer than 50 characters are truncated with an ellipsis and title attribute", function()
    local html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(html:match('<td class="col%-desc" title="This is a very long commit message that definitely exceeds the fifty character limit for description truncation">This is a very long commit message that definit%.%.%.</td>'),
        "Long description was not truncated with title attribute")
    assert(html:match('<td class="col%-desc">Short description</td>'),
        "Short description was unexpectedly truncated or altered")
end)

runner.test("UI regression: title attribute escapes double quotes properly", function()
    local html = read(output_dir .. "/git2html-ui-repo/index.html")
    assert(html:match('title="fix: handle &quot;quoted&quot; values in commit messages properly across trees"'),
        "Quotes inside description title attribute were not escaped")
end)

os.execute("rm -rf " .. output_dir .. " " .. root_dir)

runner.summary()
