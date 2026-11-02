local runner = require("test.runner")

runner.test("ignore test: skip ignored directories", function()
    local root_dir = "/tmp/git2html-ignore-root"
    os.execute("rm -rf " .. root_dir .. " && mkdir -p " .. root_dir)
    -- Root is a repo to define .gitignore
    os.execute("git -C " .. root_dir .. " init >/dev/null 2>&1")
    os.execute("echo 'ignored/' > " .. root_dir .. "/.gitignore")
    os.execute("git -C " .. root_dir .. " add .gitignore && git -C " .. root_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'ignore' >/dev/null 2>&1")
    
    -- Subdirs
    local active_dir = root_dir .. "/active"
    local ignored_dir = root_dir .. "/ignored"
    os.execute("mkdir -p " .. active_dir .. " " .. ignored_dir)
    
    local repo1 = active_dir .. "/repo1"
    os.execute("mkdir -p " .. repo1 .. " && git -C " .. repo1 .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo1 .. "/f && git -C " .. repo1 .. " add f && git -C " .. repo1 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    local repo2 = ignored_dir .. "/repo2"
    os.execute("mkdir -p " .. repo2 .. " && git -C " .. repo2 .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo2 .. "/f && git -C " .. repo2 .. " add f && git -C " .. repo2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    local output_dir = "/tmp/git2html-ignore-output"
    os.execute("rm -rf " .. output_dir)
    
    -- We start discovery at root_dir, but we need it to NOT be a repo itself 
    -- to trigger the walk. Wait, if root_dir IS a repo, git2html processes it as one.
    -- So let's delete root_dir/.git but keep the .gitignore (or just use a parent repo)
    os.execute("rm -rf " .. root_dir .. "/.git")
    
    -- Now root_dir is not a repo, but it has a .gitignore. 
    -- But 'git check-ignore' needs to be run from A repo.
    -- I'll create a dummy repo in a parent to provide the ignore context.
    local parent_dir = "/tmp/git2html-parent"
    os.execute("rm -rf " .. parent_dir .. " && mkdir -p " .. parent_dir)
    os.execute("git -C " .. parent_dir .. " init >/dev/null 2>&1")
    os.execute("mv " .. root_dir .. " " .. parent_dir .. "/root")
    os.execute("echo 'root/ignored/' > " .. parent_dir .. "/.gitignore")
    
    local cmd = runner.bin .. " " .. parent_dir .. "/root " .. output_dir .. " " .. parent_dir .. "/root >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed")
    
    -- Check if repo1 exists
    assert(os.execute("test -f " .. output_dir .. "/active/repo1/index.html"), "repo1 missing")
    -- Check if repo2 DOES NOT exist
    assert(not os.execute("test -f " .. output_dir .. "/ignored/repo2/index.html"), "repo2 should be ignored")
    
    os.execute("rm -rf " .. output_dir .. " " .. parent_dir)
end)

runner.summary()
