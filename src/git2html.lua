#!/usr/bin/env lua

-- Add script and vendor directory to package path for module loading. Only
-- relevant when running this file directly as a script from the source
-- tree (e.g. `make test`); the installed binary (see src/bundle_main.c)
-- has every module preloaded and needs none of this.
local script_full_path = debug.getinfo(1).source:match("@(.*)")
local script_dir = script_full_path and script_full_path:match("(.*)/") or "."
local repo_root = script_dir:match("(.*)/src$") or (script_dir == "src" and ".") or (script_dir .. "/..")
package.path = script_dir .. "/?.lua;" .. repo_root .. "/vendor/?.lua;" .. repo_root .. "/vendor/?/init.lua;" .. package.path
package.cpath = repo_root .. "/build/?.so;" .. repo_root .. "/vendor/?.so;" .. package.cpath

local git = require("git_utils")
local lunamark = require("lunamark")
local sh = require("syntaxhighlight")
local exec_ok = git.exec_ok

local verbose = false
local quiet = false
local footer_file = nil
local header_file = nil
-- WebVeld section 4.1 requires lang on <html>. Override with -l for a site
-- whose repository prose is not English.
local site_lang = "en"
-- Set via -c. git2html has no way to know the URL its own output will
-- actually be served from, so the clone line on a repo's Files page is
-- opt-in: nil means don't show one at all.
local clone_url_base = nil
-- Set via -r. Same idea as clone_url_base: the base URL under which each
-- repository's release archive folder is served. Nil means don't show
-- the releases line at all.
local release_url_base = nil
local has_multiple_repos = false
local function log(msg)
    if verbose then print(msg) end
end

-- Default-level progress: one line per repository and per directory, so a
-- large run visibly advances. Suppressed by -Q.
local function progress(msg)
    if not quiet then print(msg) end
end

-- Derived from the source, not the clock, so a rebuild of unchanged input
-- produces byte-identical output. A wall-clock timestamp in every footer meant
-- every page changed on every run: rsync re-uploaded the whole tree, a real
-- change was indistinguishable from a rebuild, and content-hash caching was
-- defeated. SOURCE_DATE_EPOCH overrides, per the reproducible-builds
-- convention; failing both, the clock is the last resort.
local generation_date = nil

local function resolve_generation_date(repo_path)
    if generation_date then return generation_date end

    local epoch = os.getenv("SOURCE_DATE_EPOCH")
    if epoch and epoch:match("^%d+$") then
        generation_date = os.date("!%Y-%m-%d %H:%M:%S", tonumber(epoch))
        return generation_date
    end

    if repo_path then
        local p = io.popen(string.format(
            "git -C %q log -1 --format=%%cd --date=format:'%%Y-%%m-%%d %%H:%%M:%%S' 2>/dev/null",
            repo_path))
        if p then
            local out = p:read("*line")
            p:close()
            if out and out:match("%d") then
                generation_date = out
                return generation_date
            end
        end
    end

    generation_date = os.date("%Y-%m-%d %H:%M:%S")
    return generation_date
end

-- Without fenced_code_blocks, a ``` fence is parsed as a run of inline-code
-- backticks, which can't span a blank line -- any fenced block containing
-- one (most real code) falls through into ordinary paragraph text, garbled
-- by emphasis parsing (e.g. get_title turning into get<em>title</em>).
--
-- Every other extension below was checked against vendor/lunamark/writer/
-- html.lua and enabled only because its HTML output stays within WebVeld's
-- allowed element/attribute set (strikeout, pipe table alignment, and
-- fancy_lists' ordered-list numbering were patched in that writer to emit a
-- class instead of a forbidden <strike> element, inline style, or type
-- attribute -- see the themes' .align-*/.list-* rules). raw_attribute and
-- lua_metadata are deliberately left off: both let document content inject
-- unsanitized raw HTML or execute Lua.
-- Maps a file extension or markdown fence language tag to the lexer name
-- vendor/syntaxhighlight actually ships it under, for every case where the
-- two differ (most lexers are named for their extension already, so this
-- covers only the exceptions -- e.g. ansi_c.lua serves both .c and .h).
-- Left out: ambiguous extensions with no safe default (.m, .v, .pp).
local lang_map = {
    js = "javascript", jsx = "javascript", ts = "javascript", tsx = "javascript",
    py = "python",
    md = "markdown",
    sh = "bash",
    cs = "csharp",
    rs = "rust",
    zrl = "zoril", zri = "zoril",
    c = "ansi_c", h = "ansi_c",
    cc = "cpp", cxx = "cpp", hpp = "cpp", hh = "cpp", hxx = "cpp",
    mm = "objective_c",
    rb = "ruby",
    pl = "perl", pm = "perl",
    hs = "haskell",
    ex = "elixir", exs = "elixir",
    ml = "caml", mli = "caml",
    erl = "erlang", hrl = "erlang",
    f = "fortran", ["for"] = "fortran", f90 = "fortran", f95 = "fortran",
    s = "asm",
    pas = "pascal",
    ps1 = "powershell", psm1 = "powershell",
    fs = "fsharp", fsx = "fsharp",
    yml = "yaml",
    htm = "html",
    txt = "text",
    scm = "scheme", ss = "scheme",
    el = "lisp",
    vh = "verilog", sv = "verilog", svh = "verilog",
    adb = "ada", ads = "ada",
}

local function html_escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function attr_escape(s)
    return html_escape(s):gsub('"', "&quot;")
end

local function truncate_desc(desc, max_chars)
    if not desc then return "" end
    max_chars = max_chars or 50
    if max_chars <= 3 then
        return desc:sub(1, max_chars)
    end
    local len = utf8.len(desc)
    if not len then
        if #desc > max_chars then
            return desc:sub(1, max_chars - 3) .. "..."
        end
        return desc
    end
    if len > max_chars then
        local offset = utf8.offset(desc, max_chars - 2)
        if offset then
            return desc:sub(1, offset - 1) .. "..."
        else
            return desc:sub(1, max_chars - 3) .. "..."
        end
    end
    return desc
end

local function format_description(desc)
    if not desc or desc == "" or desc == "-" then
        return '<td class="col-desc">-</td>'
    end
    desc = desc:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local truncated = truncate_desc(desc, 50)
    if truncated ~= desc then
        return string.format('<td class="col-desc" title="%s">%s</td>', attr_escape(desc), html_escape(truncated))
    else
        return string.format('<td class="col-desc">%s</td>', html_escape(desc))
    end
end

local function hl_to_html(code, lang)
    if not lang then lang = "text" end
    lang = lang_map[lang] or lang
    -- The "hl-" prefix is the shared theme contract: the same class names the
    -- luasmith site templates emit, so one stylesheet colors both.
    local html, err = sh.highlight_to_html(lang, code, { bare = true, class_prefix = "hl-" })
    if not html then
        return html_escape(code)
    end
    return html
end

local md_writer = lunamark.writer.html.new()

-- lunamark's own fenced_code just escapes the code and tags it with
-- class="language-X"; route it through the same highlighter standalone
-- file views use instead, so a fenced block in a README gets the same
-- hl-* coloring as the file it was copied from.
function md_writer.fenced_code(code, info)
    local lang = info ~= "" and info:match("%S+") or nil
    if not lang then
        return md_writer.verbatim(code)
    end
    return {'<pre tabindex="0"><code data-lang="', lang, '">', hl_to_html(code, lang), "</code></pre>"}
end

local md_parse = lunamark.reader.markdown.new(md_writer, {
    fenced_code_blocks = true,
    pipe_tables = true,
    table_captions = true,
    task_list = true,
    strikeout = true,
    mark = true,
    superscript = true,
    subscript = true,
    definition_lists = true,
    notes = true,
    inline_notes = true,
    header_attributes = true,
    bracketed_spans = true,
    fenced_divs = true,
    link_attributes = true,
    fancy_lists = true,
    hash_enumerators = true,
    smart = true,
    escaped_line_breaks = true,
})

local function md_render(content)
    -- Without a trailing blank line, lunamark's last block loses its <p>
    -- wrapper -- every README.md read from disk ends in a single newline
    -- at most, so this would otherwise strip the tag from every README's
    -- final paragraph.
    return (md_parse(content:gsub("%s*$", "") .. "\n\n"))
end

-- Splits a leading YAML frontmatter block off a markdown document, the way
-- GitHub does: the block must open on the very first line with "---" and
-- close with a later "---" (or "...") line. Returns the frontmatter lines and
-- the remaining body, or nil when there is no frontmatter.
local function split_frontmatter(content)
    content = content:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
    if not content:match("^%-%-%-[ \t]*\n") then return nil end
    local lines = {}
    local pos = content:find("\n", 1, true) + 1
    while pos <= #content do
        local nl = content:find("\n", pos, true) or (#content + 1)
        local line = content:sub(pos, nl - 1)
        pos = nl + 1
        if line:match("^%-%-%-[ \t]*$") or line:match("^%.%.%.[ \t]*$") then
            return lines, content:sub(pos)
        end
        lines[#lines + 1] = line
    end
    return nil
end

local function unquote_yaml(v)
    local q = v:match('^"(.*)"$') or v:match("^'(.*)'$")
    return q or v
end

-- Renders frontmatter as a table with one row per item: the key in a row
-- header cell and its value beside it. Only flat "key: value" pairs are understood;
-- anything more structured (nested maps, block lists, multi-line scalars)
-- falls back to a verbatim block rather than being mis-rendered.
local function frontmatter_html(lines)
    local keys, vals = {}, {}
    for _, line in ipairs(lines) do
        if line:match("^%s*$") or line:match("^%s*#") then
            -- blank line or comment: nothing to show
        else
            local k, v = line:match("^([%w_][%w_ .%-]*):%s*(.-)%s*$")
            if not k or v:match("^[|>][%+%-]?$") or v == "" then
                return "<pre tabindex=\"0\"><code>" .. html_escape(table.concat(lines, "\n")) .. "</code></pre>"
            end
            keys[#keys + 1] = k
            vals[#vals + 1] = unquote_yaml(v)
        end
    end
    if #keys == 0 then return "" end
    local rows = {}
    for i = 1, #keys do
        rows[i] = "<tr><th scope=\"row\">" .. html_escape(keys[i]) .. "</th><td>"
            .. html_escape(vals[i]) .. "</td></tr>"
    end
    return "<table class=\"frontmatter\">\n<tbody>\n" .. table.concat(rows, "\n")
        .. "\n</tbody>\n</table>\n"
end

local function md(content)
    local fm_lines, body = split_frontmatter(content)
    if fm_lines then
        local html = frontmatter_html(fm_lines)
        return html .. (body:match("%S") and md_render(body) or "")
    end
    return md_render(content)
end


-- Rewrites relative links inside rendered markdown to the pages this tool
-- actually generates. Every file in a repository is published as <path>.html
-- and every directory as <path>/index.html, so a source link such as
-- ../README.md resolves to nothing once rendered.
--
-- Anything carrying a scheme, a fragment-only target, or a root-absolute path
-- is left alone: the first two are not repository paths, and rewriting the
-- third would be wrong in a tree that has to stay relocatable.
local function rewrite_md_links(html)
    return (html:gsub('href="([^"]*)"', function(href)
        if href == "" or href:match("^%a[%w+.-]*:") or href:sub(1, 1) == "#"
            or href:sub(1, 1) == "/" then
            return 'href="' .. href .. '"'
        end
        local target, suffix = href:match("^([^#?]*)(.*)$")
        if target == "" or target:match("%.html$") then
            return 'href="' .. href .. '"'
        end
        if target:match("/$") then
            target = target .. "index.html"
        else
            target = target .. ".html"
        end
        return 'href="' .. target .. suffix .. '"'
    end))
end

local function is_markdown_file(path)
    local ext = path:match("%.([^%.]+)$")
    if not ext then return false end
    local ext_lower = ext:lower()
    return ext_lower == "md" or ext_lower == "markdown" or ext_lower == "mdown" or ext_lower == "mkdn" or ext_lower == "mkd"
end

-- A file with a NUL byte in its first block is not text. Rendering one into a
-- <pre> produced a page of mojibake and, worse, meant the real file was never
-- published: an image referenced from a README had nothing to point at and no
-- binary asset could be downloaded at all.
local function is_binary(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local chunk = f:read(8000) or ""
    f:close()
    return chunk:find("\0", 1, true) ~= nil
end

local function sh_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function normalize_path(p)
    p = p:gsub("/+", "/")
    if #p > 1 and p:sub(-1) == "/" then
        p = p:sub(1, -2)
    end
    return p
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function is_newer(target, source)
    if _G.c_is_newer then
        return _G.c_is_newer(target, source)
    end
    return exec_ok("test -f " .. sh_quote(target) .. " && test -e " .. sh_quote(source) .. " && test " .. sh_quote(target) .. " -nt " .. sh_quote(source))
end

local expected_files = {}
local expected_dirs = {}

local function register_expected_file(path)
    local norm = normalize_path(path)
    expected_files[norm] = true
    local dir = norm:match("^(.*)/[^/]+$")
    while dir and dir ~= "" do
        expected_dirs[dir] = true
        dir = dir:match("^(.*)/[^/]+$")
    end
end

local function register_expected_dir(path)
    local norm = normalize_path(path)
    local dir = norm
    while dir and dir ~= "" do
        expected_dirs[dir] = true
        dir = dir:match("^(.*)/[^/]+$")
    end
end

local function clean_destination_tree(output_root)
    local norm_root = normalize_path(output_root)
    -- Remove any files or non-directories not registered in expected_files
    local p = io.popen("find " .. sh_quote(norm_root) .. " ! -type d -print0 2>/dev/null")
    if p then
        local content = p:read("*all")
        p:close()
        for path in content:gmatch("[^\0]+") do
            local norm = normalize_path(path)
            if not expected_files[norm] then
                log("    Removing: " .. norm)
                os.remove(norm)
            end
        end
    end

    -- Remove any directories not registered in expected_dirs (depth-first)
    local pd = io.popen("find " .. sh_quote(norm_root) .. " -depth -mindepth 1 -type d -print0 2>/dev/null")
    if pd then
        local content = pd:read("*all")
        pd:close()
        for path in content:gmatch("[^\0]+") do
            local norm = normalize_path(path)
            if not expected_dirs[norm] then
                log("    Removing: " .. norm)
                os.remove(norm)
            end
        end
    end
end

local function copy_file(src, dest)
    register_expected_file(dest)
    local i = io.open(src, "rb")
    if not i then return false end
    local o = io.open(dest, "wb")
    if not o then i:close() return false end
    while true do
        local block = i:read(64 * 1024)
        if not block then break end
        o:write(block)
    end
    i:close()
    o:close()
    return true
end

local function human_size(bytes)
    if bytes >= 1048576 then return string.format("%.1f MiB", bytes / 1048576) end
    if bytes >= 1024 then return string.format("%.1f KiB", bytes / 1024) end
    return tostring(bytes) .. " B"
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function write_file(path, content)
    register_expected_file(path)
    local existing = read_file(path)
    if existing == content then
        return true
    end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- A theme is either a path to a CSS file on disk, or CSS text baked into the
-- binary by the static-build bundler (see src/bundle_main.c) -- the latter
-- has no file to `cp`, so it's written out directly instead.
local function install_theme(theme, dest)
    register_expected_file(dest)
    if theme.path and is_newer(dest, theme.path) then
        log("    Skipping: " .. dest)
        return
    end
    if theme.content then
        write_file(dest, theme.content)
    else
        os.execute(string.format("cp %q %q", theme.path, dest))
    end
end

-- Separators used to keep the HTML built up below from collapsing into one
-- enormous line: CI joins block-level pieces at content's own indent level
-- (matching where the page shell substitutes %s for it -- see template()
-- and repo_template()), RI is one level deeper, for rows nested in a table
-- body. Markdown-rendered content doesn't need this: lunamark's own writer
-- already breaks blocks onto separate lines.
local CI = "\n        "
local RI = "\n            "

-- Renders a chain of linked path segments ("a / b / c"), each pointing to
-- its own index.html relative to the page currently being written -- the
-- last segment (the current page) links to itself. Used for a repo's path
-- within itself (subdirectories) and for a discovery walk's nested groups.
local function breadcrumb_trail(parts)
    local html = ""
    for i, part in ipairs(parts) do
        if i > 1 then html = html .. " / " end
        local up_levels = #parts - i
        local part_rel = ""
        for _ = 1, up_levels do part_rel = part_rel .. "../" end
        local link_target = (up_levels == 0 and "index.html" or part_rel .. "index.html")
        html = html .. string.format('<a href="%s">%s</a>', link_target, part)
    end
    return html
end

-- Empty unless -c was given: git2html has no other way to know the URL its
-- own output will be served from.
local function clone_line(header_parts)
    if not clone_url_base then return "" end
    local base = clone_url_base:gsub("/+$", "")
    local url = base .. "/" .. table.concat(header_parts, "/") .. ".git"
    return string.format('<p class="clone-url">Git clone via <code>%s</code></p>' .. CI, html_escape(url))
end

-- Empty unless -r was given: shows a "Releases available at ..." line
-- directly below the clone line on each repository's Files page.
local function release_line(header_parts)
    if not release_url_base then return "" end
    local base = release_url_base:gsub("/+$", "")
    local url = base .. "/" .. table.concat(header_parts, "/") .. "/archive/"
    return string.format('<p class="release-url">Releases available at <a href="%s">%s</a></p>' .. CI,
        html_escape(url), html_escape(url))
end


-- Column proportions used to live in an inline <style> block relying on
-- table-layout and text-overflow, neither of which WebVeld permits (6.2).
-- colgroup carries the same intent declaratively and the widths are styled
-- from the theme. Without table-layout the widths are hints rather than hard
-- constraints, so long names wrap instead of being clipped to an ellipsis --
-- which keeps the content readable rather than truncating it.
local function files_table(rows, scrollable)
    local table_html = '<table class="listing">' .. CI
        .. '<colgroup><col class="col-name"><col class="col-desc"><col class="col-changed"></colgroup>' .. CI
        .. '<thead><tr><th>Name</th><th>Description</th><th>Last Changed</th></tr></thead>' .. CI
        .. '<tbody>' .. rows .. CI
        .. '</tbody>' .. CI
        .. '</table>'
    if scrollable then
        return '<div class="listing-pane" tabindex="0">' .. CI
            .. table_html .. CI
            .. '</div>'
    else
        return table_html
    end
end

local function log_table(rows)
    return '<table class="listing">' .. CI
        .. '<colgroup><col class="col-hash"><col class="col-date"><col class="col-subject"><col class="col-author"></colgroup>' .. CI
        .. '<thead><tr><th>Hash</th><th>Date</th><th>Subject</th><th>Author</th></tr></thead>' .. CI
        .. '<tbody>' .. rows .. CI
        .. '</tbody>' .. CI
        .. '</table>'
end

local function get_footer()
    local content
    if footer_file then
        content = read_file(footer_file)
        if content then
            content = content:gsub("{{date}}", generation_date or "")
            return content
        end
    end
    -- Spacing belongs to .colophon in the style sheet; WebVeld section 6.1
    -- forbids the inline style attribute this used to carry.
    return string.format("<footer class=\"colophon\">Generated by <a href=\"https://git.engenforge.com/git2html\">git2html</a> on %s</footer>", generation_date or "")
end

-- Empty by default: unlike the footer, there's no sensible built-in content
-- to show above the nav bar, so a caller who doesn't pass -h just gets one.
local function get_header()
    if header_file then
        local content = read_file(header_file)
        if content then
            return content:gsub("{{date}}", generation_date or "")
        end
    end
    return ""
end

-- Same nav-only masthead as repo_template: no separate <h1> repeating what
-- the nav already says. The nav here has just the one "Repositories" link
-- since there's no repo or log page in scope -- a nested discovery group's
-- own path is shown as a content breadcrumb instead, same as a repo
-- subdirectory's (see breadcrumb_trail).
local function template(page_title, content, rel_path)
    rel_path = rel_path or ""

    return string.format([[
<!DOCTYPE html>
<html lang="%s">
<head>
    <meta charset="UTF-8">
    <title>%s</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <meta name="generator" content="git2html">
    <link rel="stylesheet" href="%sstyle.css">
</head>
<body>
<div class="site-container">
    <a class="skip" href="#content">Skip to content</a>
    %s
    <header class="masthead">
        <nav aria-label="Primary">
            <p class="nav">
            <a href="%sindex.html">Repositories</a>
            </p>
        </nav>
    </header>
    <main class="page" id="content" tabindex="-1">
        %s
    </main>
    %s
</div>
</body>
</html>
]], site_lang, page_title, rel_path, get_header(), rel_path, content, get_footer())
end

local function generate_parent_indexes(output_root, header_parts, theme)
    for i = 0, #header_parts - 1 do
        if i > 0 or has_multiple_repos then
            local parts = {}
            for j = 1, i do table.insert(parts, header_parts[j]) end
            
            local rel_output = table.concat(parts, "/")
            local target_output = output_root .. (rel_output == "" and "" or "/" .. rel_output)
            register_expected_dir(target_output)
            os.execute("mkdir -p " .. target_output)
            local rel_to_root = ""
            for _ = 1, i do rel_to_root = rel_to_root .. "../" end
            
            local next_part = header_parts[i+1]
            local rows = RI .. string.format('<tr><td><a href="%s/index.html">%s/</a></td><td class="col-desc">-</td><td class="col-changed">-</td></tr>', next_part, next_part)
            if i > 0 then
                rows = RI .. '<tr><td><a href="../index.html">..</a></td><td class="col-desc">-</td><td class="col-changed">-</td></tr>' .. rows
            end

            -- At the root, the nav's "Repositories" link already says this is
            -- the repositories index -- a breadcrumb here would just repeat
            -- that. A nested group's path is real extra information the nav
            -- doesn't carry, so it gets one.
            local index_content = i == 0 and "" or ("<h2>" .. breadcrumb_trail(parts) .. "</h2>" .. CI)
            index_content = index_content .. files_table(rows, false)
            local page_title = (i == 0 and "Repositories" or table.concat(parts, " / "))
            write_file(target_output .. "/index.html", template(page_title, index_content, rel_to_root))
        end
    end
end

-- Function for repo-specific views
local function repo_template(header_parts, page_title, content, rel_path)
    rel_path = rel_path or ""
    -- The repo's own file-listing page already shows the full breadcrumb
    -- (path within the repo, or the repo's own name at its root) as an <h2>
    -- in the content itself, so the nav only needs the repo's name, not the
    -- full header_parts trail -- showing both was the duplicated-title
    -- confusion this replaced.
    local repo_name = header_parts[#header_parts] or ""

    local site_rel = rel_path
    for _ = 1, #header_parts do site_rel = site_rel .. "../" end

    local nav_prefix = ""
    if has_multiple_repos then
        nav_prefix = string.format('<a href="%sindex.html">Repositories</a> &middot; ', site_rel)
    end

    return string.format([[
<!DOCTYPE html>
<html lang="%s">
<head>
    <meta charset="UTF-8">
    <title>%s</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <meta name="generator" content="git2html">
    <link rel="stylesheet" href="%sstyle.css">
</head>
<body>
<div class="site-container">
    <a class="skip" href="#content">Skip to content</a>
    %s
    <header class="masthead">
        <nav aria-label="Primary">
            <p class="nav">
            %s<a href="%sindex.html">%s</a> &middot; <a href="%slog.html">Log</a>
            </p>
        </nav>
    </header>
    <main class="page" id="content" tabindex="-1">
        %s
    </main>
    %s
</div>
</body>
</html>
]], site_lang, page_title, rel_path, get_header(), nav_prefix, rel_path, repo_name, rel_path, content, get_footer())
end

local function generate_repo_tree(repo_path, output_dir, header_parts, subdir, metadata)
    subdir = subdir or ""
    progress("  Walking tree: " .. (subdir == "" and "[root]" or subdir))
    local files = git.ls_files(repo_path, subdir, metadata)
    
    table.sort(files, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        return a.path < b.path
    end)

    local rel_to_root = ""
    local display_name = header_parts[#header_parts]
    local parts = {}
    for part in subdir:gmatch("[^/]+") do table.insert(parts, part) end
    for i = 1, #parts do rel_to_root = rel_to_root .. "../" end

    local breadcrumb_parts = { display_name }
    for _, part in ipairs(parts) do table.insert(breadcrumb_parts, part) end
    local breadcrumbs = breadcrumb_trail(breadcrumb_parts)

    local rows = ""
    if subdir ~= "" then
        rows = rows .. RI .. '<tr><td><a href="../index.html">..</a></td><td class="col-desc">-</td><td class="col-changed">-</td></tr>'
    end

    for _, f in ipairs(files) do
        local name = f.path:match("([^/]+)$") or f.path
        local desc_td = format_description(f.description)
        if f.is_dir then
            rows = rows .. RI .. string.format('<tr><td><a href="%s/index.html">%s/</a></td>%s<td class="col-changed">%s</td></tr>', name, name, desc_td, f.last_changed)
            register_expected_dir(output_dir .. "/" .. f.path)
            os.execute("mkdir -p " .. output_dir .. "/" .. f.path)
            generate_repo_tree(repo_path, output_dir, header_parts, f.path, metadata)
        else
            local file_view_path = name .. ".html"
            rows = rows .. RI .. string.format('<tr><td><a href="%s">%s</a></td>%s<td class="col-changed">%s</td></tr>', file_view_path, name, desc_td, f.last_changed)
            
            local source = repo_path .. "/" .. f.path

            if is_binary(source) then
                -- Published verbatim, with a landing page describing it, so a
                -- reader can download it and a README can link to it.
                local binary_target = output_dir .. "/" .. f.path
                local html_target = output_dir .. "/" .. f.path .. ".html"
                register_expected_file(binary_target)
                register_expected_file(html_target)

                if is_newer(binary_target, source) then
                    log("    Skipping: " .. f.path)
                else
                    log("    Copying: " .. f.path)
                    copy_file(source, binary_target)
                end

                if is_newer(html_target, source) then
                    log("    Skipping: " .. f.path .. ".html")
                else
                    local ext = name:match("%.([^%.]+)$")
                    local ext_lower = ext and ext:lower()
                    local file_breadcrumbs = breadcrumbs .. " / " .. name
                    local body

                    if ext_lower == "png" or ext_lower == "jpg" or ext_lower == "jpeg" then
                        body = string.format(
                            '<h2>%s</h2>' .. CI .. '<p><img src="%s" alt="%s"></p>',
                            file_breadcrumbs, attr_escape(name), attr_escape(name))
                    elseif is_markdown_file(name) then
                        local content = read_file(source) or ""
                        local html_content = "<div class=\"readme\">" .. rewrite_md_links(md(content)) .. "</div>"
                        body = "<h2>" .. file_breadcrumbs .. "</h2>" .. CI .. html_content
                    elseif ext_lower == "txt" or ext_lower == "text" then
                        local content = read_file(source) or ""
                        local html_content = '<pre tabindex="0"><code>' .. hl_to_html(content, "text") .. "</code></pre>"
                        body = "<h2>" .. file_breadcrumbs .. "</h2>" .. CI .. html_content
                    else
                        local size = 0
                        local probe = io.open(source, "rb")
                        if probe then size = probe:seek("end") probe:close() end

                        body = string.format(
                            '<h2>%s</h2>' .. CI .. '<p class="meta">Binary file, %s.</p>' .. CI
                            .. '<p><a href="%s">Download %s</a></p>',
                            file_breadcrumbs, human_size(size), name, name)
                    end

                    write_file(html_target,
                        repo_template(header_parts, display_name .. " - " .. f.path,
                            body, rel_to_root))
                end
            else
                local html_target = output_dir .. "/" .. f.path .. ".html"
                register_expected_file(html_target)

                if is_newer(html_target, source) then
                    log("    Skipping: " .. f.path)
                else
                    local content = read_file(source)
                    if content then
                        log("    Rendering: " .. f.path)
                        local is_markdown = is_markdown_file(name)
                        local html_content
                        if is_markdown then
                            html_content = "<div class=\"readme\">" .. rewrite_md_links(md(content)) .. "</div>"
                        else
                            local extension = name:match("%.([^%.]+)$")
                            local lang = extension and extension:lower()
                            if not lang then
                                if name:lower() == "makefile" then lang = "makefile"
                                elseif name:lower() == "dockerfile" then lang = "dockerfile"
                                end
                            end
                            -- overflow-x on pre makes a wide block a scrollable region,
                            -- and a scrollable region that cannot be focused cannot be
                            -- scrolled without a pointer. tabindex="0" puts it in the
                            -- tab order, which is what spec section 5.1 admits the
                            -- attribute for.
                            html_content = '<pre tabindex="0"><code>' .. hl_to_html(content, lang) .. "</code></pre>"
                        end

                        local file_breadcrumbs = breadcrumbs .. " / " .. name
                        write_file(html_target, repo_template(header_parts, display_name .. " - " .. f.path, "<h2>" .. file_breadcrumbs .. "</h2>" .. CI .. html_content, rel_to_root))
                    end
                end
            end
        end
    end

    -- At the repo root, breadcrumbs is just a link back to this same page
    -- with the repo's own name -- already shown in the nav bar, so
    -- repeating it here would be the same redundant-title problem the nav
    -- redesign fixed. A subdirectory's breadcrumbs carries real extra path
    -- information the nav doesn't, so it stays.
    local index_content = subdir == "" and "" or ("<h2>" .. breadcrumbs .. "</h2>" .. CI)
    local is_main_landing = (subdir == "")
    if is_main_landing then
        index_content = index_content .. clone_line(header_parts)
        index_content = index_content .. release_line(header_parts)
    end
    index_content = index_content .. files_table(rows, is_main_landing)
    if is_main_landing then
        local readme = read_file(repo_path .. "/README.md")
            or read_file(repo_path .. "/README.markdown")
            or read_file(repo_path .. "/readme.md")
            or read_file(repo_path .. "/README.MD")
        if readme then
            index_content = index_content .. CI .. "<div class=\"readme\">" .. rewrite_md_links(md(readme)) .. "</div>"
        end
    end

    local target_path = output_dir .. "/" .. (subdir == "" and "" or subdir .. "/") .. "index.html"
    write_file(target_path, repo_template(header_parts, display_name .. (subdir == "" and "" or " - " .. subdir), index_content, rel_to_root))
end

local function generate_repo_site(repo_path, target_output, header_parts, theme, output_root)
    progress("Processing repository: " .. table.concat(header_parts, " / "))
    register_expected_dir(target_output)
    os.execute("mkdir -p " .. target_output)

    install_theme(theme, target_output .. "/style.css")

    generate_parent_indexes(output_root, header_parts, theme)
    
    -- Repo Log
    local log_data = git.get_log(repo_path)
    local log_rows = ""
    for _, c in ipairs(log_data) do
        log_rows = log_rows .. RI .. string.format("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", c.hash, c.date, c.subject, c.author)
    end
    local log_html = log_table(log_rows)
    write_file(target_output .. "/log.html", repo_template(header_parts, header_parts[#header_parts] .. " - Log", log_html))
    
    -- Recursive Tree
    local metadata = git.get_bulk_metadata(repo_path)
    generate_repo_tree(repo_path, target_output, header_parts, "", metadata)
end

local function count_direct_repos(dir, strip)
    local subdirs = git.get_subdirs(dir)
    local count = 0
    for _, name in ipairs(subdirs) do
        local full_sub = dir .. "/" .. name
        if not git.is_ignored(strip, full_sub) then
            if git.is_repo(full_sub) then
                count = count + 1
            else
                local check_cmd = string.format("find %q \\( -name .git -o -name HEAD \\) 2>/dev/null | head -n 1", full_sub)
                local check = io.popen(check_cmd)
                local candidate = check and check:read("*line")
                if check then check:close() end
                if candidate and candidate ~= "" then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function walk_and_process(current_path, output_root, strip_path, theme)
    if git.is_repo(current_path) then
        local escaped = strip_path:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        local rel_output = current_path:gsub("^" .. escaped, ""):gsub("^/+", ""):gsub("/+$", "")
        if rel_output == "" then rel_output = current_path:match("([^/]+)/?$") or "repo" end
        
        local target_output = output_root .. "/" .. rel_output
        local header_parts = {}
        for part in rel_output:gmatch("[^/]+") do table.insert(header_parts, part) end
        
        generate_repo_site(current_path, target_output, header_parts, theme, output_root)
        
        local age_cmd = string.format("git -C %q log -1 --format=%%ad --date=format:'%%Y-%%m-%%d' 2>/dev/null", current_path)
        local age_handle = io.popen(age_cmd)
        local age = age_handle:read("*line") or "unknown"
        age_handle:close()
        
        local desc = git.get_description(current_path)
        
        return { type = "repo", name = header_parts[#header_parts], description = desc, age = age, rel = rel_output:match("([^/]+)$") }
    else
        log("Scanning directory: " .. current_path)
        local subdirs = git.get_subdirs(current_path)
        local children = {}
        
        local escaped = strip_path:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        local rel_output = current_path:gsub("^" .. escaped, ""):gsub("^/+", ""):gsub("/+$", "")
        local target_output = output_root .. (rel_output == "" and "" or "/" .. rel_output)

        for _, name in ipairs(subdirs) do
            local full_sub = current_path .. "/" .. name
            -- Check if this subdirectory is ignored by git
            if not git.is_ignored(strip_path, full_sub) then
                local res = walk_and_process(full_sub, output_root, strip_path, theme)
                if res then
                    table.insert(children, res)
                end
            else
                log("  Skipping ignored directory: " .. full_sub)
            end
        end
        
        if #children > 0 then
            local header_parts = {}
            for part in rel_output:gmatch("[^/]+") do table.insert(header_parts, part) end
            
            local rel_to_root = ""
            for i = 1, #header_parts do rel_to_root = rel_to_root .. "../" end

            local rows = ""
            if #header_parts > 0 then
                rows = rows .. RI .. '<tr><td><a href="../index.html">..</a></td><td class="col-desc">-</td><td class="col-changed">-</td></tr>'
            end

            table.sort(children, function(a, b) return a.name < b.name end)

            for _, child in ipairs(children) do
                local link = child.rel .. "/index.html"
                local suffix = (child.type == "dir" and "/" or "")
                local desc_td = format_description(child.description)
                rows = rows .. RI .. string.format('<tr><td><a href="%s">%s%s</a></td>%s<td class="col-changed">%s</td></tr>', link, child.name, suffix, desc_td, child.age or "-")
            end

            -- Same nav-only-at-root rule as generate_parent_indexes: skip
            -- the breadcrumb where it would just repeat "Repositories".
            local index_content = #header_parts == 0 and "" or ("<h2>" .. breadcrumb_trail(header_parts) .. "</h2>" .. CI)
            index_content = index_content .. files_table(rows, false)
            local page_title = (#header_parts == 0 and "Repositories" or table.concat(header_parts, " / "))
            -- Only created once we know this directory (or a descendant)
            -- actually has something to show -- otherwise every non-repo
            -- folder in the walked tree would be mirrored into the output
            -- as an empty directory.
            if #header_parts > 0 or has_multiple_repos then
                register_expected_dir(target_output)
                os.execute("mkdir -p " .. target_output)
                write_file(target_output .. "/index.html", template(page_title, index_content, rel_to_root))
            end

            return { type = "dir", name = header_parts[#header_parts] or current_path:match("([^/]+)$") or "root", rel = rel_output:match("([^/]+)$") or "", age = "-" }
        end
    end
end

local function main(raw_args)
    local args = {}
    local theme_flag = nil
    local clean_dest = false
    local i = 1
    while i <= #raw_args do
        local arg = raw_args[i]
        if arg == "-v" then
            verbose = true
        elseif arg == "-Q" or arg == "--quiet" then
            quiet = true
        elseif arg == "-p" or arg == "--prune" then
            clean_dest = true
        elseif arg == "-c" then
            clone_url_base = raw_args[i+1]
            i = i + 1
        elseif arg == "-r" then
            release_url_base = raw_args[i+1]
            i = i + 1
        elseif arg == "-f" then
            footer_file = raw_args[i+1]
            i = i + 1
        elseif arg == "-h" then
            header_file = raw_args[i+1]
            i = i + 1
        elseif arg == "-l" then
            site_lang = raw_args[i+1]
            i = i + 1
        elseif arg == "-t" then
            theme_flag = raw_args[i+1]
            i = i + 1
        else
            table.insert(args, arg)
        end
        i = i + 1
    end

    if #args < 2 then
        print("Usage: git2html [-v] [-Q|--quiet] [-p|--prune] [-c clone-url-base] [-r release-url-base] [-f footer-file] [-h header-file] [-l lang] [-t theme] <repo-path-or-url> <output-dir> [strip-path] [theme]")
        os.exit(1)
    end

    local repo_input = args[1]
    local output_dir = args[2]
    local strip_input = args[3] or repo_input:match("(.*)/") or ""
    -- -t takes precedence over the positional theme argument so a caller
    -- doesn't have to pass an empty string placeholder for strip-path just
    -- to reach it -- easy to get wrong silently, since an unintended
    -- 3rd positional is read as strip-path instead and the theme quietly
    -- falls back to the default with no error.
    local theme_input = theme_flag or args[4] or "auto"
    
    log("Initializing git2html...")
    
    -- Ensure output_dir is absolute for the walker
    if not output_dir:match("^/") then
        local pwd = io.popen("pwd"):read("*line")
        output_dir = pwd .. "/" .. output_dir
    end
    output_dir = normalize_path(output_dir)
    register_expected_dir(output_dir)

    -- Theme selection
    local theme
    if theme_input:match("%.css$") then
        theme = { path = theme_input }
    elseif _EMBEDDED_THEMES and _EMBEDDED_THEMES[theme_input] then
        theme = { content = _EMBEDDED_THEMES[theme_input] }
    else
        local paths = {
            repo_root .. "/themes/" .. theme_input .. ".css",
            script_dir .. "/themes/" .. theme_input .. ".css",
        }
        for _, p in ipairs(paths) do
            local f = io.open(p, "r")
            if f then
                f:close()
                theme = { path = p }
                break
            end
        end
    end
    if not theme then
        print("Error: Could not find theme " .. theme_input)
        os.exit(1)
    end

    log("Using theme: " .. theme_input)

    if git.is_url(repo_input) then
        local temp_dir = "/tmp/git2html-" .. os.time()
        os.execute("mkdir -p " .. temp_dir)
        log("Cloning remote repository: " .. repo_input)
        local repo_path, is_temp = git.prepare_repo(repo_input, temp_dir)
        if not repo_path then
            print("Error: Could not clone repository")
            if is_temp then os.execute("rm -rf " .. temp_dir) end
            os.exit(1)
        end

        resolve_generation_date(repo_path)
        log("Generation date: " .. generation_date)
        if footer_file then log("Using custom footer from: " .. footer_file) end
        if header_file then log("Using custom header from: " .. header_file) end

        -- One style sheet at the output root, linked relatively from every page.
        os.execute("mkdir -p " .. output_dir)
        install_theme(theme, output_dir .. "/style.css")

        local display_name = repo_input:match("([^/]+)$"):gsub("%.git$", "")
        generate_repo_site(repo_path, output_dir .. "/" .. display_name, {display_name}, theme, output_dir)
        generate_parent_indexes(output_dir, {display_name}, theme)
        if is_temp then os.execute("rm -rf " .. temp_dir) end
    else
        -- Local path: check that path exists and is a directory
        local is_dir = exec_ok(string.format("test -d %q", repo_input))
        if not is_dir then
            print("Error: Not a git repository: " .. repo_input)
            os.exit(1)
        end

        if git.is_repo(repo_input) then
            log("Single local repository detected: " .. repo_input)
            resolve_generation_date(repo_input)
            log("Generation date: " .. generation_date)
            if footer_file then log("Using custom footer from: " .. footer_file) end
            if header_file then log("Using custom header from: " .. header_file) end

            -- One style sheet at the output root, linked relatively from every page.
            os.execute("mkdir -p " .. output_dir)
            install_theme(theme, output_dir .. "/style.css")

            local escaped = strip_input:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            local rel_output = repo_input:gsub("^" .. escaped, ""):gsub("^/+", ""):gsub("/+$", "")
            if rel_output == "" then rel_output = repo_input:match("([^/]+)/?$") or "repo" end
            
            local header_parts = {}
            for part in rel_output:gmatch("[^/]+") do table.insert(header_parts, part) end
            
            generate_repo_site(repo_input, output_dir .. "/" .. rel_output, header_parts, theme, output_dir)
            generate_parent_indexes(output_dir, header_parts, theme)
        else
            -- Quick check before deep traversal: does repo_input contain any .git or HEAD?
            local check_cmd = string.format("find %q \\( -name .git -o -name HEAD \\) 2>/dev/null | head -n 1", repo_input)
            local check = io.popen(check_cmd)
            local candidate = check and check:read("*line")
            if check then check:close() end
            if not candidate or candidate == "" then
                print("Error: Not a git repository: " .. repo_input)
                os.exit(1)
            end

            has_multiple_repos = (count_direct_repos(repo_input, strip_input) > 1)

            resolve_generation_date(nil)
            log("Generation date: " .. generation_date)
            if footer_file then log("Using custom footer from: " .. footer_file) end
            if header_file then log("Using custom header from: " .. header_file) end

            log("Starting discovery walk in: " .. repo_input)
            local res = walk_and_process(repo_input, output_dir, strip_input, theme)
            if not res then
                print("Error: Not a git repository: " .. repo_input)
                os.exit(1)
            end

            -- One style sheet at the output root, linked relatively from every page.
            os.execute("mkdir -p " .. output_dir)
            install_theme(theme, output_dir .. "/style.css")
        end
    end
    
    if clean_dest then
        clean_destination_tree(output_dir)
    end

    progress("Done! Static site generated in " .. output_dir)
end

main({...})
