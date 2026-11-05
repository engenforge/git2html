-- WebVeld conformance of generated output.
--
-- Every page git2html emits comes from one of two templates, so a violation in
-- a template is a violation on every page built from it. This walks the whole
-- generated tree rather than sampling, because the markdown and syntax
-- highlighting paths can introduce markup the templates never see.
--
-- The validator is resolved as an installed utility (webveld-validate on
-- PATH, or pointed to by WEBVELD_VALIDATE). Standard installed documentation
-- locations for webveld-spec.md are checked if WEBVELD_SPEC is not already set.

local runner = require("test.runner")

local function capture(cmd)
    local p = io.popen(cmd, "r")
    if not p then return nil, false, 1 end
    local out = p:read("*all")
    local ok, _, code = p:close()
    return out, ok, code or 0
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- Checks standard installed documentation locations for the normative specification.
local function find_installed_spec()
    local env_spec = os.getenv("WEBVELD_SPEC")
    if env_spec and exists(env_spec) then
        return env_spec
    end

    local home = os.getenv("HOME") or ""
    local candidates = {
        "/usr/local/share/webveld/webveld-spec.md",
        "/usr/local/share/webveld/doc/webveld-spec.md",
        "/usr/share/webveld/webveld-spec.md",
        "/usr/share/webveld/doc/webveld-spec.md",
        "/usr/local/share/doc/webveld/webveld-spec.md",
        "/usr/share/doc/webveld/webveld-spec.md",
        home .. "/doc/reference/webveld-spec.md",
        home .. "/doc/reference/webveld.md",
        home .. "/.local/share/webveld/webveld-spec.md",
        home .. "/.local/share/doc/webveld/webveld-spec.md",
    }

    for _, path in ipairs(candidates) do
        if exists(path) then
            return path
        end
    end

    return nil
end

-- Returns a function mapping an absolute HTML path to validator output.
local function find_validator()
    local cmd = os.getenv("WEBVELD_VALIDATE") or "webveld-validate"
    local on_path = capture(string.format("command -v %q 2>/dev/null", cmd)) or ""
    on_path = on_path:gsub("%s+$", "")
    if on_path == "" then
        return nil
    end

    -- If WEBVELD_SPEC is not set, look for installed specification documentation
    local spec_env = ""
    if not os.getenv("WEBVELD_SPEC") then
        local installed_spec = find_installed_spec()
        if installed_spec then
            spec_env = string.format("WEBVELD_SPEC=%q ", installed_spec)
        end
    end

    -- Verify that the executable actually runs and can load its specification
    local probe_cmd = string.format("%s%s 2>&1", spec_env, cmd)
    local probe_out, _, code = capture(probe_cmd)
    if code == 127 or (probe_out and (probe_out:match("cannot read") or probe_out:match("not found"))) then
        return nil
    end

    return function(file)
        return capture(string.format("%s%s %q 2>&1", spec_env, cmd, file))
    end, on_path .. (spec_env ~= "" and (" (" .. spec_env:gsub("%s+$", "") .. ")") or "")
end

local validate, validator_name = find_validator()

if not validate then
    runner.skip("webveld: fixture produced pages to validate")
    runner.skip("webveld: every generated page conforms")
    runner.skip("webveld: bundled themes contain no forbidden CSS")
    runner.summary()
    return
end

local temp_repo = "/tmp/git2html-webveld-repo"
local output_dir = "/tmp/git2html-webveld-output"
local theme_probe = "/tmp/git2html-theme-probe.html"

local function build_fixture()
    os.execute("rm -rf " .. temp_repo .. " && mkdir -p " .. temp_repo
        .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")

    -- A README exercises the markdown writer, a Lua file the highlighter, and
    -- a nested directory the breadcrumb and parent-index paths.
    local readme = io.open(temp_repo .. "/README.md", "w")
    readme:write("# Fixture\n\nA paragraph with a [link](https://example.com).\n\n"
        .. "```lua\nlocal x = 1 -- comment\n```\n\n"
        .. "| a | b |\n| - | - |\n| 1 | 2 |\n")
    readme:close()

    os.execute("mkdir -p " .. temp_repo .. "/src")
    local src = io.open(temp_repo .. "/src/main.lua", "w")
    src:write('local function greet(name)\n  return "hello " .. name\nend\nreturn greet\n')
    src:close()

    local png = "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\1\0\0\0\1\8\2\0\0\0\144wS"
        .. "\222\0\0\0\12IDATx\156c\248\207\192\0\0\3\1\1\0\24\221\141\176\0\0\0"
        .. "\0IEND\174B`\130"
    local img = io.open(temp_repo .. "/logo.png", "wb")
    img:write(png)
    img:close()

    local txt = io.open(temp_repo .. "/sample.txt", "w")
    txt:write("WebVeld compatible plain text\n")
    txt:close()

    local bin = io.open(temp_repo .. "/blob.bin", "wb")
    bin:write("\0\1\2\3\4\5")
    bin:close()

    os.execute("git -C " .. temp_repo .. " add -A >/dev/null 2>&1")
    os.execute("git -C " .. temp_repo
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'fixture' >/dev/null 2>&1")

    os.execute("rm -rf " .. output_dir)
    os.execute(runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1")
end

build_fixture()

local pages = {}
local listing = capture("find " .. output_dir .. " -name '*.html' | sort") or ""
for line in listing:gmatch("[^\n]+") do
    pages[#pages + 1] = line
end

runner.test("webveld: fixture produced pages to validate", function()
    assert(#pages > 0, "no HTML generated in " .. output_dir)
end)

runner.test("webveld: every generated page conforms", function()
    local failures = {}
    for _, page in ipairs(pages) do
        local out, ok, code = validate(page)
        if not out or code == 127 or (not ok and code ~= 1) then
            error(string.format("validator failed to run on %s (exit code %s): %s",
                page, tostring(code), tostring(out)))
        end
        local has_findings = false
        for line in (out or ""):gmatch("[^\n]+") do
            local finding = line:match("^%s+%- (.+)$")
            if finding then
                has_findings = true
                failures[#failures + 1] = page:gsub(output_dir .. "/", "") .. ": " .. finding
            end
        end
        if not ok and not has_findings then
            error(string.format("validator failed with exit code %s on %s:\n%s",
                tostring(code), page, out))
        end
    end
    assert(#failures == 0,
        string.format("%d violation(s) across %d page(s):\n  %s",
            #failures, #pages, table.concat(failures, "\n  ")))
end)

-- The validator parses HTML documents, so an external style sheet passed to it
-- directly is read as malformed HTML and its CSS is never examined. Every
-- bundled theme is therefore checked by embedding it in a minimal conforming
-- document: section 6.1 admits <style> and <link> alike, so the same rules
-- apply either way, and this is the path that catches a forbidden property
-- before it ships in a theme.
runner.test("webveld: bundled themes contain no forbidden CSS", function()
    local themes = {}
    local listing = capture("ls themes/*.css 2>/dev/null") or ""
    for line in listing:gmatch("[^\n]+") do
        themes[#themes + 1] = line
    end
    assert(#themes > 0, "no bundled themes found")

    local failures = {}
    for _, theme in ipairs(themes) do
        local css = io.open(theme, "r")
        local rules = css:read("*all")
        css:close()

        local doc = io.open(theme_probe, "w")
        doc:write('<!DOCTYPE html>\n<html lang="en">\n<head>\n'
            .. '<meta charset="utf-8">\n<title>theme probe</title>\n'
            .. "<style>\n" .. rules .. "\n</style>\n</head>\n<body>\n"
            .. "<p>probe</p>\n</body>\n</html>\n")
        doc:close()

        local out, ok, code = validate(theme_probe)
        if not out or code == 127 or (not ok and code ~= 1) then
            error(string.format("validator failed to run on %s (exit code %s): %s",
                theme, tostring(code), tostring(out)))
        end
        local has_findings = false
        for line in (out or ""):gmatch("[^\n]+") do
            local finding = line:match("^%s+%- (.+)$")
            if finding then
                has_findings = true
                failures[#failures + 1] = theme .. ": " .. finding
            end
        end
        if not ok and not has_findings then
            error(string.format("validator failed with exit code %s on %s:\n%s",
                tostring(code), theme, out))
        end
    end
    os.remove(theme_probe)

    assert(#failures == 0, string.format("%d violation(s) in %d theme(s):\n  %s",
        #failures, #themes, table.concat(failures, "\n  ")))
end)

os.execute("rm -rf " .. output_dir .. " " .. temp_repo .. " " .. theme_probe)

runner.summary()
