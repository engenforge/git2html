package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")
local git = require("git_utils")

runner.test("git.ls_files returns files in HEAD", function()
    local temp_dir = "/tmp/git2html-files-" .. os.time()
    os.execute("mkdir -p " .. temp_dir .. " && git -C " .. temp_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. temp_dir .. "/testfile.txt && git -C " .. temp_dir .. " add testfile.txt && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'test' >/dev/null 2>&1")

    local files = git.ls_files(temp_dir)
    local found = false
    for _, f in ipairs(files) do
        if f.path == "testfile.txt" then found = true end
    end
    assert(found, "testfile.txt not found")
    
    os.execute("rm -rf " .. temp_dir)
end)

runner.summary()
