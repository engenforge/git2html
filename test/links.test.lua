local runner = require("test.runner")

runner.test("link validation: all generated links must point to existing files", function()
    local base_dir = "/tmp/git2html-link-check"
    local repo_dir = base_dir .. "/repo1"
    os.execute("rm -rf " .. base_dir .. " && mkdir -p " .. repo_dir)
    os.execute("git -C " .. repo_dir .. " init >/dev/null 2>&1")
    os.execute("echo '# README' > " .. repo_dir .. "/README.md")
    os.execute("mkdir -p " .. repo_dir .. "/docs")
    os.execute("echo 'doc' > " .. repo_dir .. "/docs/manual.md")
    os.execute("git -C " .. repo_dir .. " add . && git -C " .. repo_dir .. " -c user.email=t@e -c user.name=T -c commit.gpgsign=false commit -m 'init' >/dev/null 2>&1")
    
    local output_dir = "/tmp/git2html-link-output"
    os.execute("rm -rf " .. output_dir)
    
    local cmd = runner.bin .. " " .. repo_dir .. " " .. output_dir .. " >/dev/null 2>&1"
    local ok = os.execute(cmd)
    assert(ok, "git2html failed")
    
    -- Function to find all HTML files recursively
    local function get_all_html_files(dir)
        local files = {}
        local p = io.popen('find "' .. dir .. '" -name "*.html"')
        for line in p:lines() do
            table.insert(files, line)
        end
        p:close()
        return files
    end
    
    local html_files = get_all_html_files(output_dir)
    assert(#html_files > 0, "No HTML files generated")
    
    for _, html_file in ipairs(html_files) do
        local f = io.open(html_file, "r")
        local content = f:read("*all")
        f:close()
        
        local current_dir = html_file:match("(.+)/")
        
        -- Extract all hrefs using a simple pattern
        for href in content:gmatch('href="([^"]+)"') do
            -- Ignore anything carrying a scheme (http, https, mailto, ...)
            if not href:match("^%a[%w+.-]*:") then
                -- Strip the fragment. The pattern must be anchored: an
                -- unanchored [^#]+ turns the fragment-only "#content" into
                -- "content" and then reports a missing file of that name.
                local target = href:match("^([^#]*)")

                if target:sub(1, 1) == "/" then
                    -- A root-absolute link resolves against the filesystem root
                    -- under file:// and against the document root once served,
                    -- so it cannot be right in both places. The output tree has
                    -- to stay relocatable and browsable locally.
                    error("Root-absolute link in " .. html_file .. ": " .. href
                        .. " (use a path relative to the page)")
                elseif target:match("/$") then
                    -- A bare directory link is served as its index.html by
                    -- httpd but shows a directory listing under file://. Link
                    -- to index.html explicitly so both agree.
                    error("Directory link in " .. html_file .. ": " .. href
                        .. " (link to index.html explicitly)")
                elseif target ~= "" then
                    local target_path = current_dir .. "/" .. target
                    local exists = os.execute('test -e "' .. target_path .. '"')
                    if not exists then
                        error("Broken link in " .. html_file .. ": " .. href .. " (Target " .. target_path .. " does not exist)")
                    end
                end
            end
        end
    end
    
    os.execute("rm -rf " .. output_dir .. " " .. base_dir)
end)

runner.summary()
