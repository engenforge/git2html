local runner = require("test.runner")

local function init_repo(dir, files)
    os.execute("mkdir -p " .. string.format("%q", dir))
    os.execute("git -C " .. string.format("%q", dir) .. " init >/dev/null 2>&1")
    for name, content in pairs(files) do
        local full = dir .. "/" .. name
        local parent = full:match("^(.*)/[^/]+$")
        if parent then os.execute("mkdir -p " .. string.format("%q", parent)) end
        local f = assert(io.open(full, "w"))
        f:write(content)
        f:close()
    end
    os.execute("git -C " .. string.format("%q", dir)
        .. " add . && git -C " .. string.format("%q", dir)
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
end

local function read_all(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*all")
    f:close()
    return s
end

runner.test("chrome: @@PATHTOROOT@@ substitutes relative path to site root with and without --root-offset", function()
    local base = "/tmp/git2html-chrome-pathtoroot"
    os.execute("rm -rf " .. base)
    local root = base .. "/repos"
    local r1 = root .. "/alpha"
    local r2 = root .. "/group/beta"
    init_repo(r1, { ["src/main.lua"] = "return 1\n" })
    init_repo(r2, { ["a/b/file.txt"] = "hello\n" })

    local hdr = base .. "/header.html"
    local ftr = base .. "/footer.html"
    local hf = assert(io.open(hdr, "w"))
    hf:write('<div class="top"><a href="@@PATHTOROOT@@index.html">Home</a></div>')
    hf:close()
    local ff = assert(io.open(ftr, "w"))
    ff:write('<footer class="colophon"><a href="@@PATHTOROOT@@about.html">About</a></footer>')
    ff:close()

    -- Without --root-offset: output_dir is the site root
    local out1 = base .. "/out1"
    local ok = os.execute(runner.bin .. " -Q -h " .. hdr .. " -f " .. ftr .. " " .. root .. " " .. out1 .. " " .. root .. " 2>/dev/null")
    assert(ok, "git2html failed without --root-offset")

    local root_idx = assert(read_all(out1 .. "/index.html"))
    assert(root_idx:find('href="index.html">Home</a>', 1, true), "root index @@PATHTOROOT@@ should be empty")
    assert(root_idx:find('href="about.html">About</a>', 1, true), "root footer @@PATHTOROOT@@ should be empty")

    local alpha_idx = assert(read_all(out1 .. "/alpha/index.html"))
    assert(alpha_idx:find('href="../index.html">Home</a>', 1, true), "alpha index @@PATHTOROOT@@ should be ../")
    assert(alpha_idx:find('href="../about.html">About</a>', 1, true), "alpha footer @@PATHTOROOT@@ should be ../")

    local alpha_sub = assert(read_all(out1 .. "/alpha/src/main.lua.html"))
    assert(alpha_sub:find('href="../../index.html">Home</a>', 1, true), "alpha/src/main.lua.html @@PATHTOROOT@@ should be ../../")

    local beta_deep = assert(read_all(out1 .. "/group/beta/a/b/file.txt.html"))
    assert(beta_deep:find('href="../../../../index.html">Home</a>', 1, true), "group/beta/a/b/file.txt.html @@PATHTOROOT@@ should be ../../../../")

    -- With --root-offset ../ (output_dir is 1 level below site root)
    local out2 = base .. "/out2"
    ok = os.execute(runner.bin .. " -Q --root-offset ../ -h " .. hdr .. " -f " .. ftr .. " " .. root .. " " .. out2 .. " " .. root .. " 2>/dev/null")
    assert(ok, "git2html failed with --root-offset ../")

    local root_idx2 = assert(read_all(out2 .. "/index.html"))
    assert(root_idx2:find('href="../index.html">Home</a>', 1, true), "root index with --root-offset ../ should be ../")

    local alpha_sub2 = assert(read_all(out2 .. "/alpha/src/main.lua.html"))
    assert(alpha_sub2:find('href="../../../index.html">Home</a>', 1, true), "alpha/src/main.lua.html with --root-offset ../ should be ../../../")

    -- With integer --root-offset 2
    local out3 = base .. "/out3"
    ok = os.execute(runner.bin .. " -Q --root-offset 2 -h " .. hdr .. " -f " .. ftr .. " " .. root .. " " .. out3 .. " " .. root .. " 2>/dev/null")
    assert(ok, "git2html failed with --root-offset 2")

    local alpha_log3 = assert(read_all(out3 .. "/alpha/log.html"))
    assert(alpha_log3:find('href="../../../index.html">Home</a>', 1, true), "alpha/log.html with --root-offset 2 should be ../../../")

    os.execute("rm -rf " .. base)
end)

runner.test("chrome: --icon emits <link rel=\"icon\"> resolved against site root", function()
    local base = "/tmp/git2html-chrome-icon"
    os.execute("rm -rf " .. base)
    local repo = base .. "/myrepo"
    init_repo(repo, { ["sub/a.txt"] = "hi\n" })

    -- Relative icon + --root-offset ../
    local out1 = base .. "/out1"
    local ok = os.execute(runner.bin .. " -Q --root-offset ../ --icon assets/favicon.svg " .. repo .. " " .. out1 .. " 2>/dev/null")
    assert(ok, "git2html --icon relative failed")

    local idx = assert(read_all(out1 .. "/myrepo/index.html"))
    assert(idx:find('<link rel="icon" href="../../assets/favicon.svg">', 1, true),
        "repo index icon should resolve to ../../assets/favicon.svg")

    local sub = assert(read_all(out1 .. "/myrepo/sub/a.txt.html"))
    assert(sub:find('<link rel="icon" href="../../../assets/favicon.svg">', 1, true),
        "subdir file icon should resolve to ../../../assets/favicon.svg")

    -- Root-absolute icon should stay unchanged
    local out2 = base .. "/out2"
    ok = os.execute(runner.bin .. " -Q --root-offset ../ --icon /favicon.ico " .. repo .. " " .. out2 .. " 2>/dev/null")
    assert(ok, "git2html --icon absolute failed")

    local idx2 = assert(read_all(out2 .. "/myrepo/index.html"))
    assert(idx2:find('<link rel="icon" href="/favicon.ico">', 1, true),
        "root-absolute icon should not be prefixed")

    -- Full URL icon should stay unchanged
    local out3 = base .. "/out3"
    ok = os.execute(runner.bin .. " -Q --icon https://example.com/icon.png " .. repo .. " " .. out3 .. " 2>/dev/null")
    assert(ok, "git2html --icon URL failed")

    local idx3 = assert(read_all(out3 .. "/myrepo/index.html"))
    assert(idx3:find('<link rel="icon" href="https://example.com/icon.png">', 1, true),
        "URL icon should not be prefixed")

    os.execute("rm -rf " .. base)
end)

runner.test("chrome: <!-- @@REPONAV@@ --> merges repo nav into custom header and omits duplicate masthead", function()
    local base = "/tmp/git2html-chrome-reponav"
    os.execute("rm -rf " .. base)
    local repo = base .. "/myrepo"
    init_repo(repo, { ["readme.txt"] = "hello\n" })

    -- Header WITH <!-- @@REPONAV@@ -->
    local hdr_merge = base .. "/header-merge.html"
    local hf = assert(io.open(hdr_merge, "w"))
    hf:write('<header class="masthead"><nav aria-label="Primary"><p class="site-nav"><a href="@@PATHTOROOT@@index.html">Site</a></p><!-- @@REPONAV@@ --></nav></header>')
    hf:close()

    local out1 = base .. "/out1"
    local ok = os.execute(runner.bin .. " -Q -h " .. hdr_merge .. " " .. repo .. " " .. out1 .. " 2>/dev/null")
    assert(ok, "git2html with merged header failed")

    local idx = assert(read_all(out1 .. "/myrepo/index.html"))
    assert(not idx:find("@@REPONAV@@", 1, true), "REPONAV placeholder should be substituted")
    assert(idx:find('<p class="nav">', 1, true), "repo nav <p class=\"nav\"> should be present")
    assert(idx:find('<a href="log.html">Log</a>', 1, true), "Log link should be inside merged nav")
    -- Only ONE <header class="masthead"> should appear (the custom one, not a duplicate)
    local _, count = idx:gsub('<header class="masthead">', "")
    assert(count == 1, "expected exactly 1 masthead header when merged, got " .. tostring(count))

    -- Header WITHOUT <!-- @@REPONAV@@ --> keeps default masthead
    local hdr_plain = base .. "/header-plain.html"
    local pf = assert(io.open(hdr_plain, "w"))
    pf:write('<div class="banner">Welcome</div>')
    pf:close()

    local out2 = base .. "/out2"
    ok = os.execute(runner.bin .. " -Q -h " .. hdr_plain .. " " .. repo .. " " .. out2 .. " 2>/dev/null")
    assert(ok, "git2html with plain header failed")

    local idx2 = assert(read_all(out2 .. "/myrepo/index.html"))
    assert(idx2:find('<div class="banner">Welcome</div>', 1, true), "plain header should be included")
    assert(idx2:find('<header class="masthead">', 1, true), "default masthead should remain when placeholder is absent")

    os.execute("rm -rf " .. base)
end)

runner.test("chrome: changing --icon or --root-offset invalidates incremental stamp", function()
    local base = "/tmp/git2html-chrome-stamp"
    os.execute("rm -rf " .. base)
    local repo = base .. "/myrepo"
    init_repo(repo, { ["a.txt"] = "a\n" })
    local out = base .. "/out"

    local ok = os.execute(runner.bin .. " -Q --icon first.png " .. repo .. " " .. out .. " 2>/dev/null")
    assert(ok, "first run failed")
    assert(assert(read_all(out .. "/myrepo/index.html")):find('href="../first.png"', 1, true))
    assert(assert(read_all(out .. "/myrepo/log.html")):find('href="../first.png"', 1, true))

    ok = os.execute(runner.bin .. " -Q --icon second.png --root-offset ../ " .. repo .. " " .. out .. " 2>/dev/null")
    assert(ok, "second run failed")
    assert(assert(read_all(out .. "/myrepo/index.html")):find('href="../../second.png"', 1, true),
        "index.html should rebuild when --icon/--root-offset changes")
    assert(assert(read_all(out .. "/myrepo/log.html")):find('href="../../second.png"', 1, true),
        "log.html should rebuild when --icon/--root-offset changes")

    os.execute("rm -rf " .. base)
end)

runner.summary()
