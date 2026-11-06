local runner = require("test.runner")

local repo = "/tmp/git2html-incr-repo"
local out = "/tmp/git2html-incr-out"

local function setup_repo()
    os.execute("rm -rf " .. repo .. " " .. out)
    os.execute("mkdir -p " .. repo .. "/src")
    os.execute("git -C " .. repo .. " init -q >/dev/null 2>&1")
    os.execute("echo '# Test' > " .. repo .. "/README.md")
    os.execute("echo 'print(1)' > " .. repo .. "/src/main.lua")
    os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm init >/dev/null 2>&1")
end

local function run_g2h(flags)
    flags = flags or ""
    local cmd = runner.bin .. " " .. flags .. " " .. repo .. " " .. out .. " /tmp auto 2>&1"
    local p = io.popen(cmd)
    local text = p:read("*all")
    local ok = p:close()
    return text, ok
end

local function cleanup()
    os.execute("rm -rf " .. repo .. " " .. out)
end

runner.test("skips output when destination file is newer than source", function()
    setup_repo()
    -- First run generates all outputs
    local text1 = run_g2h("-v")
    assert(text1:find("Rendering: src/main.lua", 1, true), "expected initial rendering in output:\n" .. text1)

    local target = out .. "/git2html-incr-repo/src/main.lua.html"
    assert(os.execute("test -f " .. target), "target HTML should exist")

    -- Overwrite target with custom marker content and set its timestamp into the future
    local f = io.open(target, "w")
    f:write("<!-- PRESERVED MARKER -->")
    f:close()
    os.execute("touch -d '2030-01-01 00:00:00' " .. target)

    -- Second run with -v: should skip main.lua because output is newer than source
    local text2 = run_g2h("-v")
    assert(text2:find("Skipping: src/main.lua", 1, true), "expected skipping in -v output:\n" .. text2)
    assert(not text2:find("Rendering: src/main.lua", 1, true), "should not render main.lua when skipped")

    -- Verify content was not overwritten
    local check_f = io.open(target, "r")
    local content = check_f:read("*all")
    check_f:close()
    assert(content == "<!-- PRESERVED MARKER -->", "newer target file should not have been overwritten")

    cleanup()
end)

runner.test("regenerates output when source is newer than destination file", function()
    setup_repo()
    run_g2h()

    local target = out .. "/git2html-incr-repo/src/main.lua.html"
    -- Set target timestamp in the past
    os.execute("touch -d '2020-01-01 00:00:00' " .. target)
    -- Touch source file to now
    os.execute("touch " .. repo .. "/src/main.lua")

    local text = run_g2h("-v")
    assert(text:find("Rendering: src/main.lua", 1, true), "expected rendering when source is newer:\n" .. text)

    cleanup()
end)

runner.test("destination prune option removes extraneous files and empty directories", function()
    setup_repo()
    run_g2h()

    local repo_out = out .. "/git2html-incr-repo"
    local stray_file = repo_out .. "/stray.txt"
    local stray_dir = repo_out .. "/old_subdir"
    local stray_nested = stray_dir .. "/nested.txt"

    os.execute("mkdir -p " .. stray_dir)
    os.execute("touch " .. stray_file)
    os.execute("touch " .. stray_nested)

    assert(os.execute("test -f " .. stray_file), "stray file should exist before prune")
    assert(os.execute("test -f " .. stray_nested), "stray nested file should exist before prune")

    -- Run without prune flag: stray files should be kept
    run_g2h()
    assert(os.execute("test -f " .. stray_file), "stray file should be kept when prune flag is omitted")

    -- Run with --prune flag: stray files and empty directories should be removed
    local text = run_g2h("-v --prune")
    assert(not os.execute("test -f " .. stray_file), "stray file should be removed by --prune")
    assert(not os.execute("test -f " .. stray_nested), "stray nested file should be removed by --prune")
    assert(not os.execute("test -d " .. stray_dir), "empty stray directory should be removed by --prune")

    -- Valid generated files and directories must remain intact
    assert(os.execute("test -f " .. repo_out .. "/index.html"), "repo index.html must remain intact")
    assert(os.execute("test -f " .. repo_out .. "/src/main.lua.html"), "src/main.lua.html must remain intact")
    assert(os.execute("test -d " .. repo_out .. "/src"), "src directory must remain intact")

    cleanup()
end)

runner.test("destination prune option preserves skipped files", function()
    setup_repo()
    run_g2h()

    local target = out .. "/git2html-incr-repo/src/main.lua.html"
    -- Target is newer than source
    os.execute("touch -d '2030-01-01 00:00:00' " .. target)

    -- Add an extraneous file
    local stray = out .. "/git2html-incr-repo/unrelated.tmp"
    os.execute("touch " .. stray)

    -- Run with -p: main.lua.html should be skipped, and unrelated.tmp removed
    run_g2h("-p")
    assert(os.execute("test -f " .. target), "skipped file must NOT be deleted by prune")
    assert(not os.execute("test -f " .. stray), "unrelated file must be deleted by prune")

    cleanup()
end)

runner.test("skips binary output and landing page when destination is newer", function()
    setup_repo()
    -- Add a small binary file
    local bin_data = "\0\1\2\3\4\5"
    local bf = io.open(repo .. "/data.bin", "wb")
    bf:write(bin_data)
    bf:close()
    os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'add bin' >/dev/null 2>&1")

    local text1 = run_g2h("-v")
    assert(text1:find("Copying: data.bin", 1, true), "expected initial binary copying:\n" .. text1)

    local bin_target = out .. "/git2html-incr-repo/data.bin"
    local html_target = out .. "/git2html-incr-repo/data.bin.html"
    assert(os.execute("test -f " .. bin_target), "binary target should exist")
    assert(os.execute("test -f " .. html_target), "binary html landing page should exist")

    -- Set future timestamps
    os.execute("touch -d '2030-01-01 00:00:00' " .. bin_target)
    os.execute("touch -d '2030-01-01 00:00:00' " .. html_target)

    local text2 = run_g2h("-v")
    assert(text2:find("Skipping: data.bin", 1, true), "expected binary skipping in -v output:\n" .. text2)
    assert(not text2:find("Copying: data.bin", 1, true), "should not copy binary when skipped")

    cleanup()
end)

runner.test("-p and --prune prune extraneous files", function()
    setup_repo()
    run_g2h()

    local stray = out .. "/git2html-incr-repo/old.bak"

    -- Test --prune
    os.execute("touch " .. stray)
    run_g2h("--prune")
    assert(not os.execute("test -f " .. stray), "stray file should be removed by --prune")

    -- Test -p
    os.execute("touch " .. stray)
    run_g2h("-p")
    assert(not os.execute("test -f " .. stray), "stray file should be removed by -p")

    cleanup()
end)

runner.test("repeat build preserves output and leaves no dotfiles or marker files", function()
    setup_repo()
    run_g2h()

    local repo_out = out .. "/git2html-incr-repo"
    -- Verify no hidden files exist anywhere in the generated output
    local p = io.popen("find " .. repo_out .. " -name '.*' ! -path " .. repo_out)
    local dotfiles = p:read("*all")
    p:close()
    assert(dotfiles == "", "no hidden dotfiles or marker files should exist in output:\n" .. dotfiles)

    -- Second run with -v: should skip unchanged files
    local text = run_g2h("-v")
    assert(text:find("Skipping: src/main.lua", 1, true), "repeat build should skip unchanged files:\n" .. text)

    -- All outputs must remain intact
    assert(os.execute("test -f " .. repo_out .. "/index.html"), "repo index.html must remain intact")
    assert(os.execute("test -f " .. repo_out .. "/src/main.lua.html"), "src/main.lua.html must remain intact")

    cleanup()
end)

runner.test("rebuilds properly and quickly when files are deleted from output", function()
    setup_repo()
    -- Add multiple files to have several files in repo
    os.execute("echo 'util = {}' > " .. repo .. "/src/util.lua")
    os.execute("echo 'config = {}' > " .. repo .. "/src/config.lua")
    os.execute("mkdir -p " .. repo .. "/doc")
    os.execute("echo '# Manual' > " .. repo .. "/doc/manual.md")
    os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'add more files' >/dev/null 2>&1")

    -- First run generates all outputs
    run_g2h()

    local repo_out = out .. "/git2html-incr-repo"
    local f1 = repo_out .. "/src/util.lua.html"
    local f2 = repo_out .. "/doc/manual.md.html"
    assert(os.execute("test -f " .. f1), "f1 should exist after first run")
    assert(os.execute("test -f " .. f2), "f2 should exist after first run")

    -- Delete the two files in the output
    os.remove(f1)
    os.remove(f2)
    assert(not os.execute("test -f " .. f1), "f1 should be deleted")
    assert(not os.execute("test -f " .. f2), "f2 should be deleted")

    -- Second run rebuilds
    local text = run_g2h("-v")

    -- Missing files must be regenerated properly
    assert(os.execute("test -f " .. f1), "f1 should be regenerated")
    assert(os.execute("test -f " .. f2), "f2 should be regenerated")

    -- Check that existing unchanged files were skipped in -v output and only missing files were rendered
    assert(text:find("Skipping: src/main.lua", 1, true), "unchanged file should be skipped")
    assert(text:find("Rendering: src/util.lua", 1, true), "deleted file should be rendered")
    assert(text:find("Rendering: doc/manual.md", 1, true), "deleted file should be rendered")

    cleanup()
end)

runner.test("prune properly removes spurious files added in output folder", function()
    setup_repo()
    run_g2h()

    local repo_out = out .. "/git2html-incr-repo"
    local spurious1 = repo_out .. "/spurious_file.tmp"
    local spurious2 = repo_out .. "/src/random_artifact.bak"
    local spurious_dir = repo_out .. "/unexpected_folder"
    local spurious3 = spurious_dir .. "/stray.data"

    os.execute("mkdir -p " .. spurious_dir)
    os.execute("touch " .. spurious1)
    os.execute("touch " .. spurious2)
    os.execute("touch " .. spurious3)

    assert(os.execute("test -f " .. spurious1), "spurious1 should exist before prune")
    assert(os.execute("test -f " .. spurious2), "spurious2 should exist before prune")
    assert(os.execute("test -f " .. spurious3), "spurious3 should exist before prune")

    -- Run with --prune
    run_g2h("--prune")

    assert(not os.execute("test -f " .. spurious1), "spurious1 should be removed by prune")
    assert(not os.execute("test -f " .. spurious2), "spurious2 should be removed by prune")
    assert(not os.execute("test -f " .. spurious3), "spurious3 should be removed by prune")
    assert(not os.execute("test -d " .. spurious_dir), "spurious directory should be removed by prune")

    -- All legitimate files must remain intact
    assert(os.execute("test -f " .. repo_out .. "/index.html"), "index.html must be kept")
    assert(os.execute("test -f " .. repo_out .. "/style.css"), "style.css must be kept")
    assert(os.execute("test -f " .. repo_out .. "/log.html"), "log.html must be kept")
    assert(os.execute("test -f " .. repo_out .. "/src/main.lua.html"), "src/main.lua.html must be kept")

    cleanup()
end)

cleanup()
runner.summary()
