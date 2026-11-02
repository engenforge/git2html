local runner = require("test.runner")

runner.test("single repo: skips the root index page", function()
    local repo_dir = "/tmp/git2html-single-test-repo"
    local output_dir = "/tmp/git2html-single-test-out"
    os.execute("rm -rf " .. repo_dir .. " " .. output_dir)
    os.execute("mkdir -p " .. repo_dir .. " && git -C " .. repo_dir .. " init >/dev/null 2>&1")
    os.execute("echo '# Single' > " .. repo_dir .. "/README.md")
    os.execute("git -C " .. repo_dir .. " add . && git -C " .. repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local ok = os.execute(runner.bin .. " " .. repo_dir .. " " .. output_dir .. " >/dev/null 2>&1")
    assert(ok, "git2html failed on single repo")

    -- Repo pages should exist
    assert(os.execute("test -f " .. output_dir .. "/git2html-single-test-repo/index.html"), "repo index missing")
    -- Root index.html should be skipped
    assert(not os.execute("test -f " .. output_dir .. "/index.html"), "root index.html should be skipped for a single repo")

    -- Nav bar should NOT contain "Repositories" link
    local f = io.open(output_dir .. "/git2html-single-test-repo/index.html", "r")
    local html = f:read("*all")
    f:close()
    assert(not html:match('Repositories</a>'), "nav bar should not have a Repositories link when index page is skipped")
    assert(html:match('<a href="index%.html">git2html%-single%-test%-repo</a>'), "repo name link missing from nav")

    os.execute("rm -rf " .. repo_dir .. " " .. output_dir)
end)

runner.test("discovery with 1 repo directly under path: skips the root index page", function()
    local root_dir = "/tmp/git2html-disc1-root"
    local repo_dir = root_dir .. "/myrepo"
    local output_dir = "/tmp/git2html-disc1-out"
    os.execute("rm -rf " .. root_dir .. " " .. output_dir)
    os.execute("mkdir -p " .. repo_dir .. " && git -C " .. repo_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo_dir .. "/f && git -C " .. repo_dir .. " add f && git -C " .. repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local ok = os.execute(runner.bin .. " " .. root_dir .. " " .. output_dir .. " " .. root_dir .. " >/dev/null 2>&1")
    assert(ok, "git2html failed on discovery with 1 repo")

    assert(os.execute("test -f " .. output_dir .. "/myrepo/index.html"), "myrepo index missing")
    assert(not os.execute("test -f " .. output_dir .. "/index.html"), "root index.html should be skipped when only 1 repo detected")

    os.execute("rm -rf " .. root_dir .. " " .. output_dir)
end)

runner.test("discovery with multiple repos directly under path: generates the root index page", function()
    local root_dir = "/tmp/git2html-disc2-root"
    local repo1 = root_dir .. "/repo1"
    local repo2 = root_dir .. "/repo2"
    local output_dir = "/tmp/git2html-disc2-out"
    os.execute("rm -rf " .. root_dir .. " " .. output_dir)
    os.execute("mkdir -p " .. repo1 .. " " .. repo2)
    os.execute("git -C " .. repo1 .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo1 .. "/f && git -C " .. repo1 .. " add f && git -C " .. repo1 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    os.execute("git -C " .. repo2 .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo2 .. "/f && git -C " .. repo2 .. " add f && git -C " .. repo2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local ok = os.execute(runner.bin .. " " .. root_dir .. " " .. output_dir .. " " .. root_dir .. " >/dev/null 2>&1")
    assert(ok, "git2html failed on discovery with multiple repos")

    assert(os.execute("test -f " .. output_dir .. "/index.html"), "root index.html should be generated when multiple repos detected")
    assert(os.execute("test -f " .. output_dir .. "/repo1/index.html"), "repo1 index missing")
    assert(os.execute("test -f " .. output_dir .. "/repo2/index.html"), "repo2 index missing")

    -- Root index should link to both repos
    local f = io.open(output_dir .. "/index.html", "r")
    local html = f:read("*all")
    f:close()
    assert(html:match('repo1/index%.html'), "root index should link to repo1")
    assert(html:match('repo2/index%.html'), "root index should link to repo2")

    -- Repo pages should have "Repositories" link in nav
    local rf = io.open(output_dir .. "/repo1/index.html", "r")
    local rhtml = rf:read("*all")
    rf:close()
    assert(rhtml:match('<a href="%.%./index%.html">Repositories</a>'), "repo1 nav should link back to Repositories index")

    os.execute("rm -rf " .. root_dir .. " " .. output_dir)
end)

runner.summary()
