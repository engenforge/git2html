local runner = require("test.runner")

runner.test("integration test: generate site for a repo", function()
    local temp_repo = "/tmp/git2html-test-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo)
    os.execute("git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("echo '# Test Repo' > " .. temp_repo .. "/README.md")
    os.execute("mkdir -p " .. temp_repo .. "/src")
    os.execute("echo 'print(\"hello\")' > " .. temp_repo .. "/src/main.lua")
    os.execute("git -C " .. temp_repo .. " add . && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'Initial' >/dev/null 2>&1")

    local output_dir = "/tmp/git2html-output"
    os.execute("rm -rf " .. output_dir)
    
    -- When stripping, the repo name is used as the subdir. 
    -- Since we pass repo_dir and no strip-path, it might use the whole path if not careful.
    -- In walk_and_process, if current is repo, it calculates rel_output.
    local cmd = runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed")
    
    -- Check if files exist. They should be in output_dir/git2html-test-repo/ because of discovery
    local final_output = output_dir .. "/git2html-test-repo"
    assert(os.execute("test -f " .. final_output .. "/index.html"), "repo index.html missing")
    assert(os.execute("test -f " .. final_output .. "/src/index.html"), "src index.html missing")
    assert(os.execute("test -f " .. final_output .. "/src/main.lua.html"), "src/main.lua.html missing")
    
    -- Root index.html should be skipped for a single repo
    assert(not os.execute("test -f " .. output_dir .. "/index.html"), "root index.html should be skipped for a single repo")
    
    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("theme test: use dark theme", function()
    local temp_repo = "/tmp/git2html-theme-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/f && git -C " .. temp_repo .. " add f && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    local output_dir = "/tmp/git2html-dark-output"
    os.execute("rm -rf " .. output_dir)
    
    local cmd = runner.bin .. " " .. temp_repo .. " " .. output_dir .. " /tmp dark >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed with dark theme")
    
    -- One style sheet at the output root, linked relatively from every page.
    -- It used to be copied into every directory.
    local f = assert(io.open(output_dir .. "/style.css", "r"),
        "no style sheet at the output root")
    local css = f:read("*all")
    f:close()
    assert(css:match("#0d1117"), "Dark theme CSS not found in output")

    -- One per repository plus one at the output root for the parent indexes,
    -- rather than one per directory. The repository is the unit a theme
    -- applies to, so a caller can theme repositories independently.
    local p = io.popen("find " .. output_dir .. " -name style.css | wc -l")
    local count = tonumber(p:read("*all"))
    p:close()
    assert(count == 2, "expected two style sheets, found " .. tostring(count))
    assert(os.execute("test -f " .. output_dir .. "/git2html-theme-repo/style.css"),
        "the repository has no style sheet of its own")

    -- ...and every page must still reach it.
    local page = io.open(output_dir .. "/git2html-theme-repo/index.html", "r")
    local html = page:read("*all")
    page:close()
    local href = html:match('<link rel="stylesheet" href="([^"]+)"')
    assert(href, "no stylesheet link on the page")
    local resolved = output_dir .. "/git2html-theme-repo/" .. href
    assert(os.execute("test -f " .. resolved),
        "stylesheet link " .. href .. " does not resolve")
    
    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("clone url test: -c shows a clone line only at the repo root", function()
    local temp_repo = "/tmp/git2html-clone-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo .. "/sub"
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/sub/f && git -C " .. temp_repo
        .. " add . && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local output_dir = "/tmp/git2html-clone-output"
    os.execute("rm -rf " .. output_dir)

    local cmd = runner.bin .. " -c https://git.example.com/ " .. temp_repo .. " " .. output_dir .. " /tmp >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed with -c")

    local root = assert(io.open(output_dir .. "/git2html-clone-repo/index.html", "r"))
    local root_html = root:read("*all")
    root:close()
    assert(root_html:match('<p class="clone%-url">Git clone via <code>'
        .. 'https://git%.example%.com/git2html%-clone%-repo%.git</code></p>'),
        "clone line missing or wrong URL on the repo root Files page")

    local sub = assert(io.open(output_dir .. "/git2html-clone-repo/sub/index.html", "r"))
    local sub_html = sub:read("*all")
    sub:close()
    assert(not sub_html:match('clone%-url'), "clone line should not appear on a subdirectory page")

    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("no -c flag: no clone line is shown", function()
    local temp_repo = "/tmp/git2html-noclone-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/f && git -C " .. temp_repo
        .. " add f && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local output_dir = "/tmp/git2html-noclone-output"
    os.execute("rm -rf " .. output_dir)
    os.execute(runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1")

    local f = assert(io.open(output_dir .. "/git2html-noclone-repo/index.html", "r"))
    local html = f:read("*all")
    f:close()
    assert(not html:match('clone%-url'), "clone line should not appear without -c")

    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("path strip test: create hierarchical header", function()
    local base_dir = "/tmp/git-repos"
    local user_dir = base_dir .. "/jason"
    local repo_dir = user_dir .. "/my-project"
    local repo_dir2 = user_dir .. "/other-project"
    os.execute("rm -rf " .. base_dir .. " && mkdir -p " .. repo_dir .. " " .. repo_dir2)
    os.execute("git -C " .. repo_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo_dir .. "/README.md && git -C " .. repo_dir .. " add . && git -C " .. repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    os.execute("git -C " .. repo_dir2 .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo_dir2 .. "/README.md && git -C " .. repo_dir2 .. " add . && git -C " .. repo_dir2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    local output_dir = "/tmp/git2html-strip-output"
    os.execute("rm -rf " .. output_dir)
    
    -- Strip /tmp/git-repos to get "jason/my-project"
    local cmd = runner.bin .. " " .. user_dir .. " " .. output_dir .. " " .. base_dir .. " >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed with path strip")
    
    local f = io.open(output_dir .. "/jason/my-project/index.html", "r")
    local html = f:read("*all")
    f:close()
    
    -- The repo's nav only names the repo itself, but "Repositories" must
    -- still climb the full stripped depth (two levels: jason/my-project).
    assert(html:match('<a href="%.%./%.%./index.html">Repositories</a>'), "Repositories link missing or wrong depth")
    assert(html:match('<a href="index.html">my%-project</a>'), "project link missing or incorrect")
    
    os.execute("rm -rf " .. output_dir .. " " .. base_dir)
end)

runner.test("release url test: -r shows a release line only at the repo root", function()
    local temp_repo = "/tmp/git2html-release-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo .. "/sub"
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/sub/f && git -C " .. temp_repo
        .. " add . && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local output_dir = "/tmp/git2html-release-output"
    os.execute("rm -rf " .. output_dir)

    local cmd = runner.bin .. " -r https://git.example.com/ " .. temp_repo .. " " .. output_dir .. " /tmp >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed with -r")

    local root = assert(io.open(output_dir .. "/git2html-release-repo/index.html", "r"))
    local root_html = root:read("*all")
    root:close()
    assert(root_html:match('<p class="release%-url">Releases available at '
        .. '<a href="https://git%.example%.com/git2html%-release%-repo/archive/">'
        .. 'https://git%.example%.com/git2html%-release%-repo/archive/</a></p>'),
        "release line missing or wrong URL on the repo root Files page")

    local sub = assert(io.open(output_dir .. "/git2html-release-repo/sub/index.html", "r"))
    local sub_html = sub:read("*all")
    sub:close()
    assert(not sub_html:match('release%-url'), "release line should not appear on a subdirectory page")

    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("no -r flag: no release line is shown", function()
    local temp_repo = "/tmp/git2html-norelease-repo"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/f && git -C " .. temp_repo
        .. " add f && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local output_dir = "/tmp/git2html-norelease-output"
    os.execute("rm -rf " .. output_dir)
    os.execute(runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1")

    local f = assert(io.open(output_dir .. "/git2html-norelease-repo/index.html", "r"))
    local html = f:read("*all")
    f:close()
    assert(not html:match('release%-url'), "release line should not appear without -r")

    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.test("Zoril test: .zrl source and zoril fences are highlighted", function()
    local temp_repo = "/tmp/git2html-zoril-repo"
    local output_dir = "/tmp/git2html-zoril-output"
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")

    local source = assert(io.open(temp_repo .. "/sample.zrl", "w"))
    source:write("fn main() -> i32 { return 0; }\n")
    source:close()

    local readme = assert(io.open(temp_repo .. "/README.md", "w"))
    readme:write("# Zoril\n\n```zoril\nfn main() -> i32 { return 0; }\n```\n")
    readme:close()

    os.execute("git -C " .. temp_repo .. " add . && git -C " .. temp_repo
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    os.execute("rm -rf " .. output_dir)
    local ok = os.execute(runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1")
    assert(ok, "git2html failed")

    local repo_dir = output_dir .. "/git2html-zoril-repo"

    local page = assert(io.open(repo_dir .. "/sample.zrl.html", "r"))
    local page_html = page:read("*all")
    page:close()
    assert(page_html:match('class="hl%-keyword">fn<'),
        ".zrl file page was not highlighted as Zoril")

    local index = assert(io.open(repo_dir .. "/index.html", "r"))
    local index_html = index:read("*all")
    index:close()
    assert(index_html:match('class="hl%-keyword">fn<'),
        "zoril fenced block was not highlighted")

    os.execute("rm -rf " .. output_dir .. " " .. temp_repo)
end)

runner.summary()
