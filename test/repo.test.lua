package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")
local git = require("git_utils")

runner.test("git.is_repo returns true for current dir", function()
    assert(git.is_repo("."))
end)

runner.test("git.is_url identifies URLs", function()
    assert(git.is_url("https://github.com/user/repo"))
    assert(git.is_url("git://example.com/repo.git"))
    assert(git.is_url("git@github.com:user/repo.git"))
    assert(not git.is_url("./local/path"))
    assert(not git.is_url("/absolute/path"))
end)

runner.test("git.prepare_repo handles local path", function()
    local path, is_temp = git.prepare_repo(".", "/tmp")
    assert(path == ".")
    assert(not is_temp)
end)

runner.test("git.prepare_repo handles file:// URL (cloning)", function()
    -- Create a fake remote repo
    os.execute("mkdir -p /tmp/fake-remote && git -C /tmp/fake-remote init >/dev/null 2>&1")
    os.execute("touch /tmp/fake-remote/README && git -C /tmp/fake-remote add README && git -C /tmp/fake-remote -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'Initial commit' >/dev/null 2>&1")
    
    local temp_dir = "/tmp/git2html-test-" .. os.time()
    os.execute("mkdir -p " .. temp_dir)
    
    local path, is_temp = git.prepare_repo("file:///tmp/fake-remote", temp_dir)
    assert(path == temp_dir .. "/repo")
    assert(is_temp)
    assert(git.is_repo(path))
    
    os.execute("rm -rf /tmp/fake-remote " .. temp_dir)
end)

runner.summary()
