local git = {}

-- os.execute's return value isn't portable: Lua 5.1 returns the raw OS exit
-- code (so even a nonzero failure is truthy), while 5.2+ returns true/false
-- as the first result. This normalizes both to a single boolean.
local function exec_ok(cmd)
    local v1, v2, v3 = os.execute(cmd)
    if type(v1) == "number" then
        return v1 == 0
    end
    return v1 == true and v3 == 0
end
git.exec_ok = exec_ok

function git.is_repo(path)
    -- A repository root must contain a .git directory or be a bare repo
    -- We'll check for .git (directory or file for submodules)
    if _G.c_is_dir and _G.c_file_exists then
        local git_path = path .. "/.git"
        if _G.c_is_dir(git_path) or _G.c_file_exists(git_path) then
            return true
        end
    else
        local cmd = string.format("test -d %q/.git || test -f %q/.git", path, path)
        if exec_ok(cmd) then return true end
    end
    
    -- Also check if it's a bare repository (must have a HEAD file)
    local head_file = io.open(path .. "/HEAD", "r")
    if head_file then
        head_file:close()
        local bare_cmd = string.format("git -C %q rev-parse --is-bare-repository 2>/dev/null", path)
        local handle = io.popen(bare_cmd)
        if handle then
            local is_bare = handle:read("*line")
            handle:close()
            if is_bare == "true" then return true end
        end
    end
    
    return false
end

function git.is_url(path)
    if path:match("^https?://") or path:match("^git://") or path:match("^ssh://") or path:match("^file://") then
        return true
    end
    -- Also handle user@host:path
    if path:match("^%a[%w._-]*@[%w._-]+:.*") then
        return true
    end
    return false
end

function git.prepare_repo(input, temp_dir)
    if git.is_url(input) then
        local target = temp_dir .. "/repo"
        local cmd = string.format("git clone --depth 1 %q %q >/dev/null 2>&1", input, target)
        if exec_ok(cmd) then
            return target, true -- true means it's a temporary clone
        else
            return nil, false
        end
    else
        if git.is_repo(input) then
            return input, false
        else
            return nil, false
        end
    end
end

function git.get_head(path)
    local cmd = string.format("git -C %q rev-parse HEAD 2>/dev/null", path)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local head = handle:read("*line")
    handle:close()
    return head
end

function git.is_dirty(path)
    local cmd = string.format("git -C %q status --porcelain 2>/dev/null", path)
    local handle = io.popen(cmd)
    if not handle then return true end
    local first_line = handle:read("*line")
    handle:close()
    return (first_line ~= nil and first_line ~= "")
end

function git.get_bulk_metadata(path, head_files, head_count)
    local remaining = nil
    if head_files then
        if head_count ~= nil then
            remaining = head_count
        else
            remaining = 0
            for _ in pairs(head_files) do remaining = remaining + 1 end
        end
        if remaining == 0 then
            return {}
        end
    end

    -- Walk commit log once with -z to get the latest commit date and description
    -- for every file and directory, stopping early once all HEAD files are resolved.
    local cmd = string.format("git -C %q log -z --format=format:'COMMIT\31%%ad\31%%s' --name-only --date=format:'%%Y-%%m-%%d'", path)
    local handle = io.popen(cmd)
    if not handle then return {} end

    local meta = {}
    local cur_date = ""
    local cur_desc = ""
    local done = false

    local function record_file(file_path)
        if file_path == "" then return end
        if not meta[file_path] then
            meta[file_path] = { last_changed = cur_date, description = cur_desc }
            if head_files and head_files[file_path] then
                remaining = remaining - 1
                if remaining <= 0 then
                    done = true
                end
            end
        end
        local slash = file_path:find("/", 1, true)
        while slash do
            local dir = file_path:sub(1, slash - 1)
            if not meta[dir] then
                meta[dir] = { last_changed = cur_date, description = cur_desc }
            end
            slash = file_path:find("/", slash + 1, true)
        end
    end

    local function process_token(tok)
        if tok == "" then return end
        if tok:sub(1, 7) == "COMMIT\31" then
            local nl = tok:find("\n", 8, true)
            local header = nl and tok:sub(1, nl - 1) or tok
            local p1 = header:find("\31", 8, true)
            if p1 then
                cur_date = header:sub(8, p1 - 1)
                cur_desc = header:sub(p1 + 1)
            else
                cur_date = header:sub(8)
                cur_desc = ""
            end
            if nl then
                record_file(tok:sub(nl + 1))
            end
        else
            record_file(tok)
        end
    end

    local buf = ""
    while not done do
        local chunk = handle:read(65536)
        if not chunk then break end
        buf = buf .. chunk
        local pos = 1
        while not done do
            local nul = buf:find("\0", pos, true)
            if not nul then break end
            process_token(buf:sub(pos, nul - 1))
            pos = nul + 1
        end
        if pos > 1 then
            buf = buf:sub(pos)
        end
    end
    if not done and buf ~= "" then
        process_token(buf)
    end
    handle:close()
    return meta
end

function git.ls_tree(path)
    local cmd = string.format("git -C %q ls-tree -r -z HEAD", path)
    local handle = io.popen(cmd)
    local dirs = { [""] = {} }
    local files = {}
    local file_count = 0
    if not handle then
        return { dirs = dirs, files = files, file_count = 0 }
    end
    local raw = handle:read("*all") or ""
    handle:close()

    local seen_dirs = { [""] = true }
    for entry in raw:gmatch("[^\0]+") do
        -- Format: <mode> <type> <hash>\t<path>
        local mode, obj_type, hash, file_path = entry:match("^(%d+) (%a+) (%x+)\t(.*)$")
        if file_path and obj_type == "blob" then
            if not files[file_path] then
                files[file_path] = true
                file_count = file_count + 1
            end
            local parent = file_path:match("^(.*)/[^/]+$") or ""
            if not dirs[parent] then dirs[parent] = {} end
            local list = dirs[parent]
            list[#list + 1] = {
                mode = mode,
                type = obj_type,
                hash = hash,
                path = file_path,
                is_dir = false,
            }

            local cur = parent
            while cur ~= "" and not seen_dirs[cur] do
                seen_dirs[cur] = true
                local grand = cur:match("^(.*)/[^/]+$") or ""
                if not dirs[grand] then dirs[grand] = {} end
                local glist = dirs[grand]
                glist[#glist + 1] = {
                    mode = "040000",
                    type = "tree",
                    hash = "",
                    path = cur,
                    is_dir = true,
                }
                cur = grand
            end
        end
    end

    return { dirs = dirs, files = files, file_count = file_count }
end

function git.ls_files(path, subdir, metadata, tree)
    if not tree then
        tree = git.ls_tree(path)
    end
    local key = (subdir or ""):gsub("^/+", ""):gsub("/+$", "")
    local entries = tree.dirs[key]
    if not entries then return {} end

    local files = {}
    for _, e in ipairs(entries) do
        local file_path = e.path
        local last_changed, description
        if metadata and metadata[file_path] then
            last_changed = metadata[file_path].last_changed
            description = metadata[file_path].description
        else
            local age_cmd = string.format("git -C %q log -1 --format=%%ad%%x1f%%s --date=format:'%%Y-%%m-%%d' -- %q", path, file_path)
            local age_handle = io.popen(age_cmd)
            if age_handle then
                local line = age_handle:read("*line")
                age_handle:close()
                if line then
                    last_changed, description = line:match("^(.-)\31(.*)$")
                end
            end
        end

        files[#files + 1] = {
            mode = e.mode,
            type = e.type,
            hash = e.hash,
            path = file_path,
            is_dir = e.is_dir,
            last_changed = last_changed or "unknown",
            description = description
        }
    end
    return files
end

function git.get_log(path)
    -- Format: hash|date|subject|author
    local cmd = string.format("git -C %q log --pretty=format:'%%h|%%ad|%%s|%%an' --date=short", path)
    local handle = io.popen(cmd)
    local log = {}
    for line in handle:lines() do
        local hash, date, subject, author = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
        if hash then
            table.insert(log, {
                hash = hash,
                date = date,
                subject = subject,
                author = author
            })
        end
    end
    handle:close()
    return log
end

function git.get_description(path)
    -- Standard git way is .git/description
    local desc_path = path .. "/.git/description"
    local f = io.open(desc_path, "r")
    if not f then
        -- Bare repos have description in the root
        desc_path = path .. "/description"
        f = io.open(desc_path, "r")
    end
    
    if f then
        local desc = f:read("*line")
        f:close()
        if desc and not desc:match("^Unnamed repository") then
            return desc
        end
    end
    return "No description provided."
end

function git.get_repo_root(path)
    local cmd = string.format("git -C %q rev-parse --show-toplevel 2>/dev/null", path)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local root = handle:read("*line")
    handle:close()
    return root
end

function git.is_ignored(_, path)
    -- Find the nearest repository root for the path being checked
    local root = git.get_repo_root(path)
    if not root then
        -- Path is not in any repository, so it can't be git-ignored
        return false
    end
    
    -- Check if path is ignored relative to its own repository root
    local cmd = string.format("git -C %q check-ignore %q >/dev/null 2>&1", root, path)
    return exec_ok(cmd)
end

function git.get_subdirs(path)
    if _G.c_readdir then
        local entries = _G.c_readdir(path)
        local dirs = {}
        for _, entry in ipairs(entries) do
            if entry.is_dir then
                dirs[#dirs + 1] = entry.name
            end
        end
        table.sort(dirs)
        return dirs
    end
    local cmd = string.format("ls -1 -F %q 2>/dev/null", path)
    local handle = io.popen(cmd)
    local dirs = {}
    if not handle then return dirs end
    for line in handle:lines() do
        local name = line:match("(.*)/$")
        if name then
            table.insert(dirs, name)
        end
    end
    handle:close()
    return dirs
end

return git
