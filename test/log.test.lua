package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")
local git = require("git_utils")

runner.test("git.get_log returns commits", function()
    local temp_dir = "/tmp/git2html-log-" .. os.time()
    os.execute("mkdir -p " .. temp_dir .. " && git -C " .. temp_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_dir .. "/f && git -C " .. temp_dir .. " add f && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'Initial commit' >/dev/null 2>&1")
    os.execute("echo 'more' > " .. temp_dir .. "/f && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -am 'Second commit' >/dev/null 2>&1")

    local log = git.get_log(temp_dir)
    assert(#log == 2, "Expected 2 commits, got " .. #log)
    assert(log[1].subject == "Second commit")
    assert(log[2].subject == "Initial commit")
    
    os.execute("rm -rf " .. temp_dir)
end)

runner.test("log.html HTML-escapes commit subject and author", function()
    local temp_repo = "/tmp/git2html-log-escape-" .. os.time()
    local output_dir = "/tmp/git2html-log-escape-out-" .. os.time()
    os.execute("rm -rf " .. temp_repo .. " " .. output_dir .. " && mkdir -p " .. temp_repo)
    os.execute("git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_repo .. "/f && git -C " .. temp_repo .. " add f && git -C " .. temp_repo
        .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit --author='Alice & Bob <t@e>' -m 'use Vec<u8> & Option<T> here' >/dev/null 2>&1")

    local ok = os.execute(runner.bin .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1")
    assert(ok, "git2html failed")

    local repo_name = temp_repo:match("([^/]+)$")
    local f = assert(io.open(output_dir .. "/" .. repo_name .. "/log.html", "r"), "log.html missing")
    local html = f:read("*all")
    f:close()

    assert(html:find("use Vec&lt;u8&gt; &amp; Option&lt;T&gt; here", 1, true),
        "commit subject was not HTML-escaped in log.html")
    assert(html:find("Alice &amp; Bob", 1, true),
        "commit author was not HTML-escaped in log.html")
    assert(not html:find("<u8>", 1, true),
        "raw <u8> tag found in log.html")

    os.execute("rm -rf " .. temp_repo .. " " .. output_dir)
end)

runner.summary()
