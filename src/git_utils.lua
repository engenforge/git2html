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
    local cmd = string.format("test -d %q/.git || test -f %q/.git", path, path)
    if exec_ok(cmd) then return true end
    
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

function git.get_bulk_metadata(path)
    -- Walk commit log once to get the latest commit date and description for every file and directory
    local cmd = string.format("git -C %q log --format=format:'COMMIT\31%%ad\31%%s' --name-only --date=format:'%%Y-%%m-%%d'", path)
    local handle = io.popen(cmd)
    if not handle then return {} end
    local meta = {}
    local cur_date = ""
    local cur_desc = ""
    for line in handle:lines() do
        if line:sub(1, 7) == "COMMIT\31" then
            local p1 = line:find("\31", 8, true)
            if p1 then
                cur_date = line:sub(8, p1 - 1)
                cur_desc = line:sub(p1 + 1)
            else
                cur_date = line:sub(8)
                cur_desc = ""
            end
        elseif line ~= "" then
            if not meta[line] then
                meta[line] = { last_changed = cur_date, description = cur_desc }
            end
            local slash = line:find("/", 1, true)
            while slash do
                local dir = line:sub(1, slash - 1)
                if not meta[dir] then
                    meta[dir] = { last_changed = cur_date, description = cur_desc }
                end
                slash = line:find("/", slash + 1, true)
            end
        end
    end
    handle:close()
    return meta
end

function git.ls_files(path, subdir, metadata)
    local ref = "HEAD"
    local tree_path = "."
    if subdir and subdir ~= "" then
        tree_path = subdir
        -- Ensure it ends with / for ls-tree to list contents
        if not tree_path:match("/$") then tree_path = tree_path .. "/" end
    end
    
    local cmd = string.format("git -C %q ls-tree %s %q", path, ref, tree_path)
    local handle = io.popen(cmd)
    local files = {}
    for line in handle:lines() do
        -- Format: 100644 blob <hash>    <path>
        local mode, type, hash, file_path = line:match("(%d+) (%a+) (%w+)%s+(.*)")
        if file_path and (type == "blob" or type == "tree") then
            local last_changed, description
            if metadata and metadata[file_path] then
                last_changed = metadata[file_path].last_changed
                description = metadata[file_path].description
            else
                local age_cmd = string.format("git -C %q log -1 --format=%%ad%%x1f%%s --date=format:'%%Y-%%m-%%d' -- %q", path, file_path)
                local age_handle = io.popen(age_cmd)
                local line = age_handle:read("*line")
                age_handle:close()
                if line then
                    last_changed, description = line:match("^(.-)\31(.*)$")
                end
            end

            table.insert(files, {
                mode = mode,
                type = type,
                hash = hash,
                path = file_path,
                is_dir = (type == "tree"),
                last_changed = last_changed or "unknown",
                description = description
            })
        end
    end
    handle:close()
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
