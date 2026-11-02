package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")

runner.test("portability test: execute from external directory", function()
    local project_dir = os.getenv("PWD")
    local temp_run_dir = "/tmp/git2html-run"
    local output_dir = "/tmp/git2html-output-ext"
    local temp_repo = "/tmp/git2html-repo-ext"
    
    os.execute("rm -rf " .. temp_run_dir .. " " .. output_dir .. " " .. temp_repo)
    os.execute("mkdir -p " .. temp_run_dir)
    os.execute("mkdir -p " .. temp_repo .. " && git -C " .. temp_repo .. " init >/dev/null 2>&1")
    os.execute("echo '# Test' > " .. temp_repo .. "/README.md && git -C " .. temp_repo .. " add . && git -C " .. temp_repo .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    -- Run from temp_run_dir using path to binary
    local bin_path = runner.bin:sub(1, 1) == "/" and runner.bin or (project_dir .. "/" .. runner.bin)
    local cmd = "cd " .. temp_run_dir .. " && " .. bin_path .. " " .. temp_repo .. " " .. output_dir .. " >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed when run from external directory")
    
    assert(os.execute("test -f " .. output_dir .. "/git2html-repo-ext/index.html"), "repo index.html missing")
    assert(not os.execute("test -f " .. output_dir .. "/index.html"), "root index.html should be skipped for single repo")
    assert(os.execute("test -f " .. output_dir .. "/style.css"), "style.css missing")
    
    os.execute("rm -rf " .. temp_run_dir .. " " .. output_dir .. " " .. temp_repo)
end)

runner.summary()
