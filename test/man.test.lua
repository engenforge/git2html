local runner = require("test.runner")

local function capture(cmd)
    local p = io.popen(cmd, "r")
    if not p then return nil, false end
    local out = p:read("*all")
    local ok = p:close()
    return out, ok
end

local MIN_SCDOC_VERSION = { 1, 11, 5 }
local MIN_SCDOC_STR = "1.11.5"

local function parse_version(str)
    if not str then return nil end
    local major, minor, patch = str:match("(%d+)%.(%d+)%.?(%d*)")
    if not major or not minor then return nil end
    return {
        tonumber(major) or 0,
        tonumber(minor) or 0,
        tonumber(patch) or 0,
    }
end

local function version_ge(v1, v2)
    for i = 1, 3 do
        local a, b = v1[i] or 0, v2[i] or 0
        if a > b then return true end
        if a < b then return false end
    end
    return true
end

local scdoc_cmd = os.getenv("SCDOC") or "scdoc"
local has_scdoc = os.execute(string.format("command -v %s >/dev/null 2>&1", scdoc_cmd))

if not has_scdoc then
    runner.skip("man page: doc/man/git2html.1 builds properly from scdoc source")
    runner.skip("man page: committed doc/man/git2html.1 is up to date with scdoc source")
    runner.summary()
    return
end

local ver_out = capture(scdoc_cmd .. " -v 2>&1") or ""
local cur_ver = parse_version(ver_out)
if not cur_ver or not version_ge(cur_ver, MIN_SCDOC_VERSION) then
    local found = ver_out:match("(%d+%.%d+%.?%d*)") or ver_out:gsub("%s+$", "")
    if found == "" then found = "unknown" end
    io.stderr:write(string.format("WARNING: scdoc >= %s required (found %s); skipping man page tests\n",
        MIN_SCDOC_STR, found))
    runner.skip("man page: doc/man/git2html.1 builds properly from scdoc source")
    runner.skip("man page: committed doc/man/git2html.1 is up to date with scdoc source")
    runner.summary()
    return
end

runner.test("man page: doc/man/git2html.1 builds properly from scdoc source", function()
    local scd_path = "doc/man/git2html.1.scd"
    local f = assert(io.open(scd_path, "r"), scd_path .. " does not exist")
    f:close()

    local out, ok = capture(scdoc_cmd .. " < " .. scd_path .. " 2>/dev/null")
    assert(ok, "scdoc failed to compile " .. scd_path)
    assert(#out > 0, "scdoc produced empty output")
    assert(out:match('%.TH "git2html" "1"'), "man page missing .TH header")
    assert(out:match('%.SH NAME'), "man page missing NAME section")
    assert(out:match('%.SH SYNOPSIS'), "man page missing SYNOPSIS section")
    assert(out:match('%.SH DESCRIPTION'), "man page missing DESCRIPTION section")
end)

runner.test("man page: committed doc/man/git2html.1 is up to date with scdoc source", function()
    local scd_path = "doc/man/git2html.1.scd"
    local man_path = "doc/man/git2html.1"

    local f_man = assert(io.open(man_path, "r"), man_path .. " does not exist")
    local committed_content = f_man:read("*all")
    f_man:close()

    -- Determine MAN_EPOCH matching the Makefile logic
    local epoch_str = capture("git log -1 --format=%ct -- " .. scd_path .. " 2>/dev/null | grep . || stat -c %Y " .. scd_path) or ""
    epoch_str = epoch_str:gsub("%s+$", "")
    local epoch_env = ""
    if epoch_str ~= "" then
        epoch_env = "SOURCE_DATE_EPOCH=" .. epoch_str .. " "
    end

    local generated_content, ok = capture(epoch_env .. scdoc_cmd .. " < " .. scd_path .. " 2>/dev/null")
    assert(ok, "scdoc failed to generate man page")

    -- Normalize away generator comments and the .TH date so only documentation
    -- content drift counts (matching WebVeld MAN_NORMALIZE).
    local function normalize_man(text)
        text = text:gsub("^%.\\\"[^\n]*\n?", ""):gsub("\n%.\\\"[^\n]*", "")
        text = text:gsub('(%.TH%s+"[^"]+"%s+"[^"]+")%s+"[^\n"]*"', '%1')
        return text
    end

    assert(normalize_man(committed_content) == normalize_man(generated_content),
        "committed " .. man_path .. " is out of date with " .. scd_path .. ". Run 'make man' to regenerate it.")
end)

runner.summary()
