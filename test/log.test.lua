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

runner.summary()
