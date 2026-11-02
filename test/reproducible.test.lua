local runner = require("test.runner")

-- A wall-clock timestamp in every footer made every page change on every run:
-- rsync re-uploaded the whole tree, a real change was indistinguishable from a
-- rebuild, and content-hash caching was defeated.

local repo = "/tmp/git2html-repro-repo"
local a, b = "/tmp/git2html-repro-a", "/tmp/git2html-repro-b"

local function build(out, env)
    os.execute("rm -rf " .. out)
    os.execute((env and (env .. " ") or "") .. runner.bin .. " " .. repo .. " " .. out
        .. " /tmp auto >/dev/null 2>&1")
end

os.execute("rm -rf " .. repo)
os.execute("mkdir -p " .. repo)
os.execute("git -C " .. repo .. " init -q >/dev/null 2>&1")
os.execute("printf '# repro\\n\\ntext\\n' > " .. repo .. "/README.md")
os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
os.execute("git -C " .. repo .. " -c user.email=t@e -c user.name=T"
    .. " -c commit.gpgsign=false commit -qm init >/dev/null 2>&1")

runner.test("two runs of unchanged input produce identical output", function()
    build(a)
    os.execute("sleep 1.1")
    build(b)
    local ok = os.execute("diff -r " .. a .. " " .. b .. " >/dev/null 2>&1")
    assert(ok, "output differs between runs of identical input")
end)

runner.test("SOURCE_DATE_EPOCH overrides the date", function()
    build(a, "SOURCE_DATE_EPOCH=1000000000")
    local f = assert(io.open(a .. "/git2html-repro-repo/index.html", "r"))
    local html = f:read("*all")
    f:close()
    assert(html:match("2001%-09%-09"), "SOURCE_DATE_EPOCH was not honoured")
end)

runner.test("the date comes from the repository, not the clock", function()
    build(a)
    local f = assert(io.open(a .. "/git2html-repro-repo/index.html", "r"))
    local html = f:read("*all")
    f:close()
    local p = io.popen("git -C " .. repo
        .. " log -1 --format=%cd --date=format:'%Y-%m-%d'")
    local commit_date = p:read("*line")
    p:close()
    -- Escape the hyphens: "-" is Lua's lazy quantifier, so an unescaped date
    -- is a malformed pattern rather than a literal.
    local pattern = commit_date:gsub("%-", "%%-")
    assert(html:match(pattern),
        "footer does not carry the last commit date " .. tostring(commit_date))
end)

os.execute("rm -rf " .. repo .. " " .. a .. " " .. b)
runner.summary()
