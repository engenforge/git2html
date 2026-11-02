local runner = require("test.runner")

local function capture(cmd)
    local p = io.popen(cmd, "r")
    if not p then return nil, false end
    local out = p:read("*all")
    local ok = p:close()
    return out, ok
end

runner.test("dist creates reproducible source and binary tarballs with SHA256SUMS", function()
    local ok = os.execute("make dist >/dev/null 2>&1")
    assert(ok, "make dist failed")

    local dist_dir = "build/dist"
    assert(os.execute("test -f " .. dist_dir .. "/SHA256SUMS"), "missing SHA256SUMS")

    -- verify sha256 checksums match
    local check_ok = os.execute("cd " .. dist_dir .. " && sha256sum -c SHA256SUMS >/dev/null 2>&1")
    assert(check_ok, "sha256sum validation failed in " .. dist_dir)

    -- verify source tarball contains project files
    local src_tar = capture("ls " .. dist_dir .. "/git2html-*.tar.xz 2>/dev/null | grep -v -- '-linux-' | head -n1") or ""
    src_tar = src_tar:gsub("%s+", "")
    assert(src_tar ~= "", "missing source tarball")
    local tar_list = capture("tar -tf " .. src_tar .. " 2>/dev/null") or ""
    assert(tar_list:match("Makefile"), "source tarball missing Makefile")
    assert(tar_list:match("src/git2html%.lua"), "source tarball missing src/git2html.lua")
end)

runner.summary()
