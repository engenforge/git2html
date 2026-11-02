local runner = require("test.runner")

runner.test("submodule test: ignore submodules in file list", function()
    local base_dir = "/tmp/git2html-sub-test"
    os.execute("rm -rf " .. base_dir .. " && mkdir -p " .. base_dir)
    os.execute("git -C " .. base_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. base_dir .. "/root_file && git -C " .. base_dir .. " add root_file && git -C " .. base_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'root' >/dev/null 2>&1")
    
    local sub_repo_dir = "/tmp/git2html-sub-repo"
    os.execute("rm -rf " .. sub_repo_dir .. " && mkdir -p " .. sub_repo_dir)
    os.execute("git -C " .. sub_repo_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. sub_repo_dir .. "/sub_file && git -C " .. sub_repo_dir .. " add sub_file && git -C " .. sub_repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'sub' >/dev/null 2>&1")
    
    -- Add as submodule
    os.execute("git -C " .. base_dir .. " submodule add " .. sub_repo_dir .. " mysub >/dev/null 2>&1")
    os.execute("git -C " .. base_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'add sub' >/dev/null 2>&1")
    
    local output_dir = "/tmp/git2html-sub-output"
    os.execute("rm -rf " .. output_dir)
    
    local cmd = runner.bin .. " " .. base_dir .. " " .. output_dir .. " /tmp >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed")
    
    local f = io.open(output_dir .. "/git2html-sub-test/index.html", "r")
    local html = f:read("*all")
    f:close()
    
    -- Currently, it will show 'mysub' in the table because ls-tree includes it.
    -- If it's not a tree or blob, it should be ignored.
    assert(not html:match("mysub"), "Submodule 'mysub' should be ignored in the file list")
    
    os.execute("rm -rf " .. output_dir .. " " .. base_dir .. " " .. sub_repo_dir)
end)

runner.summary()
