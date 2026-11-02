local runner = require("test.runner")

local repo = "/tmp/git2html-output-repo"
local out = "/tmp/git2html-output-site"

local function make_repo()
    os.execute("rm -rf " .. repo .. " && mkdir -p " .. repo .. "/src/deep")
    os.execute("git -C " .. repo .. " init >/dev/null 2>&1")
    os.execute("echo '# T' > " .. repo .. "/README.md")
    os.execute("echo 'x = 1' > " .. repo .. "/src/a.lua")
    os.execute("echo 'y = 2' > " .. repo .. "/src/deep/b.lua")
    os.execute("git -C " .. repo .. " add . && git -C " .. repo ..
        " -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -m init >/dev/null 2>&1")
end

-- Runs git2html with extra flags and returns its combined stdout+stderr.
local function run(flags)
    os.execute("rm -rf " .. out)
    local p = io.popen(runner.bin .. " " .. flags .. " " .. repo .. " " .. out .. " 2>&1")
    local text = p:read("a")
    p:close()
    return text
end

local function count(text, pat)
    local n = 0
    for _ in text:gmatch(pat) do n = n + 1 end
    return n
end

local function cleanup()
    os.execute("rm -rf " .. repo .. " " .. out)
end

runner.test("default mode prints a progress line per directory", function()
    make_repo()
    local text = run("")
    assert(text:find("Processing repository:", 1, true), "missing repository line")
    -- root, src and src/deep
    assert(count(text, "Walking tree:") == 3, "expected 3 directory lines, got:\n" .. text)
    assert(text:find("Done!", 1, true), "missing completion line")
    -- Per-file detail is reserved for -v.
    assert(not text:find("Rendering:", 1, true), "per-file output leaked into default mode")
    cleanup()
end)

runner.test("-Q suppresses all output", function()
    make_repo()
    local text = run("-Q")
    assert(text == "", "expected no output, got:\n" .. text)
    assert(os.execute("test -f " .. out .. "/git2html-output-repo/index.html"), "site not generated")
    cleanup()
end)

runner.test("--quiet is equivalent to -Q", function()
    make_repo()
    local text = run("--quiet")
    assert(text == "", "expected no output, got:\n" .. text)
    cleanup()
end)

runner.test("-v adds per-file detail on top of progress", function()
    make_repo()
    local text = run("-v")
    assert(text:find("Walking tree:", 1, true))
    assert(text:find("Rendering:", 1, true), "missing per-file output")
    cleanup()
end)

runner.test("-Q does not suppress errors", function()
    local p = io.popen(runner.bin .. " -Q 2>&1")
    local text = p:read("a")
    p:close()
    assert(text:find("Usage", 1, true), "usage message should still print, got:\n" .. text)
end)

runner.test("fails on a path that is not a git repository", function()
    local non_repo = "/tmp/git2html-non-repo"
    local bad_out = "/tmp/git2html-bad-out"
    os.execute("rm -rf " .. non_repo .. " " .. bad_out)
    os.execute("mkdir -p " .. non_repo .. "/sub && echo 'data' > " .. non_repo .. "/sub/file.txt")

    local p = io.popen(runner.bin .. " " .. non_repo .. " " .. bad_out .. " 2>&1")
    local text = p:read("a")
    local ok, kind, code = p:close()

    assert(ok == nil or ok == false or code ~= 0, "expected git2html to fail on non-repo")
    assert(text:find("Error: Not a git repository: " .. non_repo, 1, true), "expected error message, got:\n" .. text)
    assert(not os.execute("test -d " .. bad_out), "output directory should not be created on error")

    os.execute("rm -rf " .. non_repo .. " " .. bad_out)
end)

runner.test("fails on a nonexistent path", function()
    local bad_in = "/tmp/git2html-nonexistent-input"
    local bad_out = "/tmp/git2html-bad-out"
    os.execute("rm -rf " .. bad_in .. " " .. bad_out)

    local p = io.popen(runner.bin .. " " .. bad_in .. " " .. bad_out .. " 2>&1")
    local text = p:read("a")
    local ok, kind, code = p:close()

    assert(ok == nil or ok == false or code ~= 0, "expected git2html to fail on nonexistent path")
    assert(text:find("Error: Not a git repository: " .. bad_in, 1, true), "expected error message, got:\n" .. text)
    assert(not os.execute("test -d " .. bad_out), "output directory should not be created on error")

    os.execute("rm -rf " .. bad_out)
end)

runner.summary()
