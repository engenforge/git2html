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

f = assert(io.open(repo .. "/photo.jpg", "wb"))
f:write("\255\216\255\224\0\16JFIF\0\1\1\0\0\1\0\1\0\0\255\217")
f:close()

f = assert(io.open(repo .. "/banner.JPEG", "wb"))
f:write("\255\216\255\224\0\16JFIF\0\1\1\0\0\1\0\1\0\0\255\217")
f:close()

os.execute("mkdir -p " .. repo .. "/images")
f = assert(io.open(repo .. "/images/icon.png", "wb"))
f:write(png)
f:close()

f = assert(io.open(repo .. "/anim.gif", "wb"))
f:write("GIF89a\0\0\0\0\0\0\0")
f:close()

f = assert(io.open(repo .. "/capital.TXT", "w"))
f:write("capitalized txt extension content\n")
f:close()

f = assert(io.open(repo .. "/archive.bin", "wb"))
f:write("bin\0data\0\1\2\3")
f:close()

f = assert(io.open(repo .. "/notes.txt", "w"))
f:write("sample notes text\nline 2\n")
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

runner.test("a WebVeld image file is displayed rather than giving a download message", function()
    local g = assert(io.open(base .. "logo.png.html", "r"))
    local html = g:read("*all")
    g:close()
    assert(html:match('<img%s+src="logo%.png"%s+alt="logo%.png">'), "no image tag on landing page")
    assert(not html:match("Download"), "download link present on image landing page")
    assert(not html:match("Binary file"), "binary notice present on image landing page")
    assert(not html:match("IHDR"), "raw binary leaked into the page")

    -- JPEG image display
    g = assert(io.open(base .. "photo.jpg.html", "r"))
    html = g:read("*all")
    g:close()
    assert(html:match('<img%s+src="photo%.jpg"%s+alt="photo%.jpg">'), "no image tag on photo.jpg landing page")
    assert(not html:match("Download"), "download link present on photo.jpg landing page")

    -- Uppercase JPEG image display
    g = assert(io.open(base .. "banner.JPEG.html", "r"))
    html = g:read("*all")
    g:close()
    assert(html:match('<img%s+src="banner%.JPEG"%s+alt="banner%.JPEG">'), "no image tag on banner.JPEG landing page")
    assert(not html:match("Download"), "download link present on banner.JPEG landing page")

    -- Nested image in subdirectory
    g = assert(io.open(base .. "images/icon.png.html", "r"))
    html = g:read("*all")
    g:close()
    assert(html:match('<img%s+src="icon%.png"%s+alt="icon%.png">'), "relative image tag incorrect in subdirectory")
    assert(not html:match("Download"), "download link present on nested image landing page")
end)

runner.test("a non-compatible binary file gets a download landing page", function()
    local g = assert(io.open(base .. "archive.bin.html", "r"))
    local html = g:read("*all")
    g:close()
    assert(html:match("Binary file"), "no binary notice on the landing page")
    assert(html:match('href="archive%.bin"'), "no download link")

    -- GIF is not permitted in WebVeld img documents, so it must receive a download landing page
    g = assert(io.open(base .. "anim.gif.html", "r"))
    html = g:read("*all")
    g:close()
    assert(html:match("Binary file"), "no binary notice on GIF landing page")
    assert(html:match('href="anim%.gif"'), "no download link for GIF")
end)

runner.test("a txt file displays text content rather than a download message", function()
    local g = assert(io.open(base .. "notes.txt.html", "r"))
    local html = g:read("*all")
    g:close()
    assert(html:match('<pre tabindex="0"><code>'), "no pre code block for txt file")
    assert(html:match("sample notes text"), "txt content missing")
    assert(not html:match("Download"), "download link present on txt page")

    -- Capitalized .TXT extension
    g = assert(io.open(base .. "capital.TXT.html", "r"))
    html = g:read("*all")
    g:close()
    assert(html:match('<pre tabindex="0"><code>'), "no pre code block for .TXT file")
    assert(html:match("capitalized txt extension content"), ".TXT content missing")
    assert(not html:match("Download"), "download link present on .TXT page")
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
