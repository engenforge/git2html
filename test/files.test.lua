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

runner.test("git.ls_tree and git.ls_files handle nested dirs, spaces, and non-ASCII paths", function()
    local temp_dir = "/tmp/git2html-files-utf8-" .. os.time()
    os.execute("rm -rf " .. temp_dir .. " && mkdir -p " .. temp_dir .. "/'sub dir'/deep")
    os.execute("git -C " .. temp_dir .. " init >/dev/null 2>&1")
    local f1 = io.open(temp_dir .. "/café.txt", "w"); f1:write("coffee\n"); f1:close()
    local f2 = io.open(temp_dir .. "/sub dir/hello world.txt", "w"); f2:write("hi\n"); f2:close()
    local f3 = io.open(temp_dir .. "/sub dir/deep/naïve.lua", "w"); f3:write("return 1\n"); f3:close()
    os.execute("git -C " .. temp_dir .. " add -A && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'unicode and spaces' >/dev/null 2>&1")

    local tree = git.ls_tree(temp_dir)
    assert(tree and tree.files, "git.ls_tree should return tree with files set")
    assert(tree.files["café.txt"], "tree.files should contain café.txt")
    assert(tree.files["sub dir/hello world.txt"], "tree.files should contain sub dir/hello world.txt")
    assert(tree.files["sub dir/deep/naïve.lua"], "tree.files should contain sub dir/deep/naïve.lua")

    local root_files = git.ls_files(temp_dir, "", nil, tree)
    local found_cafe, found_subdir = false, false
    for _, f in ipairs(root_files) do
        if f.path == "café.txt" and not f.is_dir then found_cafe = true end
        if f.path == "sub dir" and f.is_dir then found_subdir = true end
    end
    assert(found_cafe, "café.txt not found unquoted in root ls_files")
    assert(found_subdir, "sub dir not found in root ls_files")

    local sub_files = git.ls_files(temp_dir, "sub dir", nil, tree)
    local found_space, found_deep = false, false
    for _, f in ipairs(sub_files) do
        if f.path == "sub dir/hello world.txt" and not f.is_dir then found_space = true end
        if f.path == "sub dir/deep" and f.is_dir then found_deep = true end
    end
    assert(found_space, "sub dir/hello world.txt not found")
    assert(found_deep, "sub dir/deep not found")

    local deep_files = git.ls_files(temp_dir, "sub dir/deep", nil, tree)
    assert(#deep_files == 1 and deep_files[1].path == "sub dir/deep/naïve.lua", "deep file not found")

    os.execute("rm -rf " .. temp_dir)
end)

runner.test("git.get_bulk_metadata uses -z for non-ASCII paths and stops early once HEAD files are resolved", function()
    local temp_dir = "/tmp/git2html-meta-" .. os.time()
    os.execute("rm -rf " .. temp_dir .. " && mkdir -p " .. temp_dir .. "/sub")
    os.execute("git -C " .. temp_dir .. " init -q")

    -- Commit 1: an old file that will later be deleted
    local f0 = io.open(temp_dir .. "/ancient.txt", "w"); f0:write("old\n"); f0:close()
    os.execute("git -C " .. temp_dir .. " add -A && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'ancient commit'")

    -- Commit 2: delete ancient.txt and add current HEAD files including non-ASCII
    os.remove(temp_dir .. "/ancient.txt")
    local f1 = io.open(temp_dir .. "/café.txt", "w"); f1:write("coffee\n"); f1:close()
    local f2 = io.open(temp_dir .. "/sub/hello world.txt", "w"); f2:write("hi\n"); f2:close()
    os.execute("git -C " .. temp_dir .. " add -A && git -C " .. temp_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'current commit'")

    local tree = git.ls_tree(temp_dir)
    local meta = git.get_bulk_metadata(temp_dir, tree.files, tree.file_count)
    assert(meta["café.txt"] and meta["café.txt"].description == "current commit", "café.txt metadata missing or wrong")
    assert(meta["sub/hello world.txt"] and meta["sub/hello world.txt"].description == "current commit", "sub/hello world.txt metadata missing or wrong")
    assert(meta["sub"] and meta["sub"].description == "current commit", "sub dir metadata missing or wrong")

    -- Commit 3: touch café.txt again; now ancient.txt is behind an even older commit
    -- Actually, commit 2 deleted ancient.txt (so ancient.txt was in commit 2 too!).
    -- Add a separate test case where ancient.txt was ONLY in commit 1, commit 2 is empty, commit 3 touches all HEAD files.
    os.execute("rm -rf " .. temp_dir)

    local temp_dir2 = "/tmp/git2html-meta-early-" .. os.time()
    os.execute("rm -rf " .. temp_dir2 .. " && mkdir -p " .. temp_dir2)
    os.execute("git -C " .. temp_dir2 .. " init -q")
    local a1 = io.open(temp_dir2 .. "/only_in_c1.txt", "w"); a1:write("1\n"); a1:close()
    os.execute("git -C " .. temp_dir2 .. " add -A && git -C " .. temp_dir2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'c1'")
    os.remove(temp_dir2 .. "/only_in_c1.txt")
    local a2 = io.open(temp_dir2 .. "/live.txt", "w"); a2:write("v1\n"); a2:close()
    os.execute("git -C " .. temp_dir2 .. " add -A && git -C " .. temp_dir2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'c2'")
    -- Now modify live.txt in c3 so c3 alone resolves all HEAD files
    local a3 = io.open(temp_dir2 .. "/live.txt", "w"); a3:write("v2\n"); a3:close()
    os.execute("git -C " .. temp_dir2 .. " add -A && git -C " .. temp_dir2 .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -qm 'c3'")

    local tree2 = git.ls_tree(temp_dir2)
    local meta2 = git.get_bulk_metadata(temp_dir2, tree2.files, tree2.file_count)
    assert(meta2["live.txt"] and meta2["live.txt"].description == "c3", "live.txt should resolve from c3")
    assert(meta2["only_in_c1.txt"] == nil, "should have stopped early before reaching c2/c1")

    os.execute("rm -rf " .. temp_dir2)
end)

runner.summary()
