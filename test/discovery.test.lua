local runner = require("test.runner")

runner.test("discovery test: non-repo directories are not mirrored into output", function()
    local root_dir = "/tmp/git2html-discovery-root"
    os.execute("rm -rf " .. root_dir .. " && mkdir -p " .. root_dir)

    local repo_dir = root_dir .. "/has-repo"
    os.execute("mkdir -p " .. repo_dir .. " && git -C " .. repo_dir .. " init >/dev/null 2>&1")
    os.execute("touch " .. repo_dir .. "/f && git -C " .. repo_dir .. " add f && git -C " .. repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")

    local no_repo_dir = root_dir .. "/no-repo/nested-no-repo"
    os.execute("mkdir -p " .. no_repo_dir)
    os.execute("echo 'just a file' > " .. no_repo_dir .. "/data.txt")

    local output_dir = "/tmp/git2html-discovery-output"
    os.execute("rm -rf " .. output_dir)

    local cmd = runner.bin .. " " .. root_dir .. " " .. output_dir .. " " .. root_dir .. " >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed")

    assert(os.execute("test -f " .. output_dir .. "/has-repo/index.html"), "has-repo missing")
    assert(not os.execute("test -d " .. output_dir .. "/no-repo"), "no-repo should not be mirrored into the output")

    os.execute("rm -rf " .. root_dir .. " " .. output_dir)
end)

runner.summary()
