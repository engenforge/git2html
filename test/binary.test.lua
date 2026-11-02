local runner = require("test.runner")

-- A binary file used to be rendered into a <pre> as mojibake, and the real
-- file was never published: an image referenced from a README had nothing to
-- point at, and no binary asset could be downloaded at all.

local repo = "/tmp/git2html-bin-repo"
local out = "/tmp/git2html-bin-out"

os.execute("rm -rf " .. repo .. " " .. out)
os.execute("mkdir -p " .. repo)
os.execute("git -C " .. repo .. " init -q >/dev/null 2>&1")

-- A small PNG, written here so the fixture needs nothing from the filesystem.
local png = "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\1\0\0\0\1\8\2\0\0\0\144wS"
    .. "\222\0\0\0\12IDATx\156c\248\207\192\0\0\3\1\1\0\24\221\141\176\0\0\0"
    .. "\0IEND\174B`\130"
local f = assert(io.open(repo .. "/logo.png", "wb"))
f:write(png)
f:close()

f = assert(io.open(repo .. "/README.md", "w"))
f:write("# has an image\n\n![logo](logo.png)\n\nAnd a [link](logo.png).\n")
f:close()

os.execute("git -C " .. repo .. " add -A >/dev/null 2>&1")
os.execute("git -C " .. repo .. " -c user.email=t@e -c user.name=T"
    .. " -c commit.gpgsign=false commit -qm init >/dev/null 2>&1")
os.execute(runner.bin .. " " .. repo .. " " .. out .. " /tmp auto >/dev/null 2>&1")

local base = out .. "/git2html-bin-repo/"

runner.test("a binary file is published verbatim", function()
    local g = assert(io.open(base .. "logo.png", "rb"), "the PNG was not published")
    local data = g:read("*all")
    g:close()
    assert(data == png, "the published PNG differs from the source")
end)

runner.test("a binary file gets a landing page instead of mojibake", function()
    local g = assert(io.open(base .. "logo.png.html", "r"))
    local html = g:read("*all")
    g:close()
    assert(html:match("Binary file"), "no binary notice on the landing page")
    assert(html:match('href="logo%.png"'), "no download link")
    assert(not html:match("IHDR"), "raw binary leaked into the page")
end)

runner.test("an image in a README resolves to the published file", function()
    local g = assert(io.open(base .. "index.html", "r"))
    local html = g:read("*all")
    g:close()
    local src = html:match('<img src="([^"]+)"')
    assert(src, "no image in the rendered README")
    assert(os.execute("test -f " .. base .. src),
        "image src " .. src .. " does not resolve to a file")
end)

runner.test("a link to a binary goes to its landing page", function()
    local g = assert(io.open(base .. "index.html", "r"))
    local html = g:read("*all")
    g:close()
    assert(html:match('href="logo%.png%.html"'),
        "a markdown link to a binary was not rewritten to its page")
end)

os.execute("rm -rf " .. repo .. " " .. out)
runner.summary()
