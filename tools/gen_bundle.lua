#!/usr/bin/env lua
-- Generates build/bundle_data.c: src/git2html.lua, src/git_utils.lua, every vendored
-- Lua module and the bundled theme CSS, embedded as byte arrays so the
-- static binary (see src/bundle_main.c) needs no files on disk at run
-- time. Run at build time only (see Makefile); never shipped or executed by
-- the resulting binary.

local function read_file(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local content = f:read("*all")
    f:close()
    return content
end

local function module_name(relpath)
    local dir, base = relpath:match("^(.-)/?([^/]+)$")
    if base == "init.lua" then
        return (dir:gsub("/", "."))
    end
    local stem = base:gsub("%.lua$", "")
    if dir == "" then return stem end
    return (dir:gsub("/", ".")) .. "." .. stem
end

local function find_lua_files(root)
    local files = {}
    local p = assert(io.popen("find " .. root .. " -name '*.lua' | sort"))
    for line in p:lines() do table.insert(files, line) end
    p:close()
    return files
end

-- {name, path}
local modules = { { "git_utils", "src/git_utils.lua" } }
for _, path in ipairs(find_lua_files("vendor")) do
    local rel = path:match("^vendor/(.*)$")
    table.insert(modules, { module_name(rel), path })
end

local themes = {}
local function find_theme_files()
    local files = {}
    local p = assert(io.popen("find themes -name '*.css' | sort"))
    for line in p:lines() do table.insert(files, line) end
    p:close()
    return files
end
for _, path in ipairs(find_theme_files()) do
    local name = path:match("([^/]+)%.css$")
    table.insert(themes, { name, path })
end

local out = assert(io.open("build/bundle_data.c", "w"))

local function emit_array(cname, bytes)
    out:write(string.format("static const unsigned char %s[] = {\n", cname))
    local n = #bytes
    for i = 1, n do
        out:write(string.format("%d,", bytes:byte(i)))
        if i % 20 == 0 then out:write("\n") end
    end
    out:write("\n};\n")
end

out:write('#include "bundle_data.h"\n\n')

for i, m in ipairs(modules) do
    emit_array("g2h_mod_" .. i, read_file(m[2]))
end
for i, t in ipairs(themes) do
    emit_array("g2h_theme_" .. i, read_file(t[2]))
end
emit_array("g2h_main_data", read_file("src/git2html.lua"))

out:write("\nconst g2h_embedded_file g2h_modules[] = {\n")
for i, m in ipairs(modules) do
    out:write(string.format('    { %q, g2h_mod_%d, sizeof(g2h_mod_%d) },\n', m[1], i, i))
end
out:write("};\n")
out:write("const size_t g2h_modules_count = sizeof(g2h_modules) / sizeof(g2h_modules[0]);\n\n")

out:write("const g2h_embedded_file g2h_themes[] = {\n")
for i, t in ipairs(themes) do
    out:write(string.format('    { %q, g2h_theme_%d, sizeof(g2h_theme_%d) },\n', t[1], i, i))
end
out:write("};\n")
out:write("const size_t g2h_themes_count = sizeof(g2h_themes) / sizeof(g2h_themes[0]);\n\n")

out:write("const unsigned char *g2h_main = g2h_main_data;\n")
out:write("const size_t g2h_main_len = sizeof(g2h_main_data);\n")

out:close()

io.stderr:write(string.format("gen_bundle: embedded %d modules, %d themes\n", #modules, #themes))
