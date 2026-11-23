local runner = require("test.runner")

local function read_readme_version()
    local f = assert(io.open("README.md", "r"))
    local in_ver = false
    local ver = nil
    for line in f:lines() do
        if in_ver then
            ver = line:match("^%s*(.-)%s*$")
            break
        end
        if line:match("^## Version") then
            in_ver = true
        end
    end
    f:close()
    assert(ver and ver ~= "", "failed to read version from README.md")
    return ver
end

local function git_describe()
    local p = io.popen("git describe --tags --always 2>/dev/null")
    if not p then return nil end
    local out = p:read("*line")
    p:close()
    if out == "" then return nil end
    return out
end

local function run_cmd(cmd)
    local p = io.popen(cmd .. " 2>&1")
    local out = p:read("*all")
    local ok, _, code = p:close()
    return out, (ok == true or code == 0)
end

runner.test("--version prints git2html version and git describe info and exits 0", function()
    local ver = read_readme_version()
    local desc = git_describe()
    local expected = desc and ("git2html " .. ver .. " (" .. desc .. ")") or ("git2html " .. ver)

    local out, ok = run_cmd(runner.bin .. " --version")
    assert(ok, "--version should exit with status 0")
    local trimmed = out:gsub("%s+$", "")
    assert(trimmed == expected, string.format("expected %q, got %q", expected, trimmed))
end)

runner.test("--version works when running src/git2html.lua directly", function()
    local ver = read_readme_version()
    local desc = git_describe()
    local expected = desc and ("git2html " .. ver .. " (" .. desc .. ")") or ("git2html " .. ver)

    local out, ok = run_cmd("lua src/git2html.lua --version")
    assert(ok, "lua src/git2html.lua --version should exit with status 0")
    local trimmed = out:gsub("%s+$", "")
    assert(trimmed == expected, string.format("expected %q, got %q", expected, trimmed))
end)

runner.test("--version still prints when -Q is passed", function()
    local ver = read_readme_version()
    local out, ok = run_cmd(runner.bin .. " -Q --version")
    assert(ok, "-Q --version should exit with status 0")
    assert(out:find("git2html " .. ver, 1, true), "expected version output, got: " .. out)
end)

runner.summary()
