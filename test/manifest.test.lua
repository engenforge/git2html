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

runner.test("manifest: renders multiple repos with custom placement and per-repo themes", function()
    local base = "/tmp/git2html-manifest-basic"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/src/alpha"
    local r2 = base .. "/src/beta"
    local r3 = base .. "/src/gamma"
    init_repo(r1, { ["README.md"] = "# Alpha\n", ["main.lua"] = "print('alpha')\n" })
    init_repo(r2, { ["README.md"] = "# Beta\n", ["lib.lua"] = "return 2\n" })
    init_repo(r3, { ["README.md"] = "# Gamma\n", ["app.lua"] = "return 3\n" })

    local custom_css = base .. "/custom.css"
    local cf = assert(io.open(custom_css, "w"))
    cf:write("/* custom-manifest-theme */\nbody { color: #112233; }\n")
    cf:close()

    local out1 = base .. "/out/custom-alpha"
    local out2 = base .. "/out/nested/custom-beta"
    local out3 = base .. "/out/custom-gamma"

    local manifest = base .. "/manifest.tsv"
    local mf = assert(io.open(manifest, "w"))
    mf:write("# Comment line\n")
    mf:write("\n")
    mf:write(r1 .. "\t" .. out1 .. "\n")
    mf:write(r2 .. "\t" .. out2 .. "\tdark\n")
    mf:write(r3 .. "\t" .. out3 .. "\t" .. custom_css .. "\n")
    mf:close()

    local ok = os.execute(runner.bin .. " -Q -t light --manifest " .. manifest .. " 2>/dev/null")
    assert(ok, "git2html --manifest failed")

    -- Verify pages exist at custom target locations
    assert(read_all(out1 .. "/index.html"), "alpha index.html missing")
    assert(read_all(out1 .. "/main.lua.html"), "alpha main.lua.html missing")
    assert(read_all(out1 .. "/log.html"), "alpha log.html missing")
    assert(read_all(out2 .. "/index.html"), "beta index.html missing")
    assert(read_all(out2 .. "/lib.lua.html"), "beta lib.lua.html missing")
    assert(read_all(out3 .. "/index.html"), "gamma index.html missing")
    assert(read_all(out3 .. "/app.lua.html"), "gamma app.lua.html missing")

    -- Verify per-repo themes
    local css1 = assert(read_all(out1 .. "/style.css"), "alpha style.css missing")
    local css2 = assert(read_all(out2 .. "/style.css"), "beta style.css missing")
    local css3 = assert(read_all(out3 .. "/style.css"), "gamma style.css missing")
    assert(css1 ~= css2, "alpha (light) and beta (dark) should have different stylesheets")
    assert(css3:find("custom-manifest-theme", 1, true), "gamma should use custom CSS override")

    os.execute("rm -rf " .. base)
end)

runner.test("manifest: reads from stdin with '-' and handles paths with spaces", function()
    local base = "/tmp/git2html-manifest-stdin"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/repo with spaces"
    local out1 = base .. "/out dir/my repo"
    init_repo(r1, { ["hello.txt"] = "hello world\n" })

    local cmd = string.format("printf '%%s\\t%%s\\tmonochrome\\n' %q %q | %s -Q --manifest - 2>/dev/null",
        r1, out1, runner.bin)
    local ok = os.execute(cmd)
    assert(ok, "git2html --manifest - failed")

    local idx = assert(read_all(out1 .. "/index.html"), "index.html missing for spaced path")
    assert(idx:find("hello.txt", 1, true), "hello.txt missing from index")
    assert(read_all(out1 .. "/hello.txt.html"), "hello.txt.html missing")
    assert(read_all(out1 .. "/style.css"), "style.css missing")

    os.execute("rm -rf " .. base)
end)

runner.test("manifest: resolves relative targets against output-dir and supports --prune", function()
    local base = "/tmp/git2html-manifest-prune"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/src/r1"
    local r2 = base .. "/src/r2"
    init_repo(r1, { ["a.txt"] = "a\n" })
    init_repo(r2, { ["b.txt"] = "b\n" })

    local out_root = base .. "/out"
    os.execute("mkdir -p " .. out_root .. "/stale-repo " .. out_root .. "/r1")
    local sf = assert(io.open(out_root .. "/stale-repo/index.html", "w"))
    sf:write("stale")
    sf:close()
    local sf2 = assert(io.open(out_root .. "/r1/extra.html", "w"))
    sf2:write("extra")
    sf2:close()

    local manifest = base .. "/manifest.tsv"
    local mf = assert(io.open(manifest, "w"))
    mf:write(r1 .. "\tr1\n")
    mf:write(r2 .. "\tgroup/r2\tdark\n")
    mf:close()

    local ok = os.execute(runner.bin .. " -Q -p --manifest " .. manifest .. " " .. out_root .. " 2>/dev/null")
    assert(ok, "git2html --manifest with output-dir and --prune failed")

    assert(read_all(out_root .. "/r1/index.html"), "r1 index missing")
    assert(read_all(out_root .. "/group/r2/index.html"), "group/r2 index missing")
    assert(not read_all(out_root .. "/r1/extra.html"), "extra.html inside r1 should be pruned")
    assert(not read_all(out_root .. "/stale-repo/index.html"), "stale-repo should be pruned")

    os.execute("rm -rf " .. base)
end)

runner.test("manifest: --prune without output-dir prunes only inside each target_dir", function()
    local base = "/tmp/git2html-manifest-prune-local"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/src/r1"
    init_repo(r1, { ["a.txt"] = "a\n" })

    local out1 = base .. "/out/r1"
    os.execute("mkdir -p " .. out1)
    local keep = assert(io.open(base .. "/out/keep.html", "w"))
    keep:write("keep me")
    keep:close()
    local stale = assert(io.open(out1 .. "/stale.html", "w"))
    stale:write("remove me")
    stale:close()

    local manifest = base .. "/manifest.tsv"
    local mf = assert(io.open(manifest, "w"))
    mf:write(r1 .. "\t" .. out1 .. "\n")
    mf:close()

    local ok = os.execute(runner.bin .. " -Q -p --manifest " .. manifest .. " 2>/dev/null")
    assert(ok, "git2html --manifest -p without output-dir failed")

    assert(read_all(out1 .. "/index.html"), "r1 index missing")
    assert(not read_all(out1 .. "/stale.html"), "stale.html inside target_dir should be pruned")
    assert(read_all(base .. "/out/keep.html") == "keep me", "sibling file outside target_dir must be preserved")

    os.execute("rm -rf " .. base)
end)

runner.test("manifest: --prune-targets with output-dir prunes only each target_dir and preserves siblings", function()
    local base = "/tmp/git2html-manifest-prune-targets"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/src/r1"
    local r2 = base .. "/src/r2"
    init_repo(r1, { ["a.txt"] = "a\n" })
    init_repo(r2, { ["b.txt"] = "b\n" })

    local out_root = base .. "/out"
    os.execute("mkdir -p " .. out_root .. "/themes " .. out_root .. "/r1 " .. out_root .. "/group/r2")
    local icon = assert(io.open(out_root .. "/icon.png", "w"))
    icon:write("icon-data")
    icon:close()
    local theme_css = assert(io.open(out_root .. "/themes/site.css", "w"))
    theme_css:write("body{}")
    theme_css:close()
    local stale1 = assert(io.open(out_root .. "/r1/stale.html", "w"))
    stale1:write("remove1")
    stale1:close()
    local stale2 = assert(io.open(out_root .. "/group/r2/stale.html", "w"))
    stale2:write("remove2")
    stale2:close()

    local manifest = base .. "/manifest.tsv"
    local mf = assert(io.open(manifest, "w"))
    mf:write(r1 .. "\tr1\n")
    mf:write(r2 .. "\tgroup/r2\n")
    mf:close()

    local ok = os.execute(runner.bin .. " -Q --prune-targets --manifest " .. manifest .. " " .. out_root .. " 2>/dev/null")
    assert(ok, "git2html --manifest --prune-targets with output-dir failed")

    assert(read_all(out_root .. "/r1/index.html"), "r1 index missing")
    assert(read_all(out_root .. "/group/r2/index.html"), "group/r2 index missing")
    assert(not read_all(out_root .. "/r1/stale.html"), "stale.html inside r1 should be pruned")
    assert(not read_all(out_root .. "/group/r2/stale.html"), "stale.html inside group/r2 should be pruned")
    assert(read_all(out_root .. "/icon.png") == "icon-data", "sibling icon.png in output-dir must be preserved")
    assert(read_all(out_root .. "/themes/site.css") == "body{}", "sibling themes/site.css in output-dir must be preserved")

    os.execute("rm -rf " .. base)
end)

runner.test("manifest: rejects empty, malformed, invalid repo, and invalid theme manifests", function()
    local base = "/tmp/git2html-manifest-errors"
    os.execute("rm -rf " .. base)
    local r1 = base .. "/src/r1"
    init_repo(r1, { ["a.txt"] = "a\n" })

    -- Empty manifest
    local empty_m = base .. "/empty.tsv"
    local f = assert(io.open(empty_m, "w"))
    f:write("# only comment\n\n")
    f:close()
    assert(not os.execute(runner.bin .. " -Q --manifest " .. empty_m .. " >/dev/null 2>&1"),
        "empty manifest should fail")

    -- Malformed line (only 1 column)
    local bad_m = base .. "/bad.tsv"
    f = assert(io.open(bad_m, "w"))
    f:write(r1 .. "\n")
    f:close()
    assert(not os.execute(runner.bin .. " -Q --manifest " .. bad_m .. " >/dev/null 2>&1"),
        "malformed manifest line should fail")

    -- Non-git repo
    local not_repo = base .. "/not-a-repo"
    os.execute("mkdir -p " .. not_repo)
    local nonrepo_m = base .. "/nonrepo.tsv"
    f = assert(io.open(nonrepo_m, "w"))
    f:write(not_repo .. "\t" .. base .. "/out/x\n")
    f:close()
    assert(not os.execute(runner.bin .. " -Q --manifest " .. nonrepo_m .. " >/dev/null 2>&1"),
        "non-git repo in manifest should fail")

    -- Invalid theme
    local badtheme_m = base .. "/badtheme.tsv"
    f = assert(io.open(badtheme_m, "w"))
    f:write(r1 .. "\t" .. base .. "/out/y\tnonexistent-theme-xyz\n")
    f:close()
    assert(not os.execute(runner.bin .. " -Q --manifest " .. badtheme_m .. " >/dev/null 2>&1"),
        "invalid theme in manifest should fail")

    os.execute("rm -rf " .. base)
end)

runner.summary()
