package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path
package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath

local runner = {}
runner.tests = 0
runner.passed = 0
runner.failed = 0
runner.skipped = 0
runner.errors = {}
runner.is_suite = false
runner._running = false
runner.SKIP_TAG = {}

local project_dir = os.getenv("PWD") or "."
local default_bin = project_dir .. "/build/git2html"
local bin_file = io.open(default_bin, "r")
if bin_file then
    bin_file:close()
    runner.bin = os.getenv("GIT2HTML_BIN") or default_bin
else
    runner.bin = os.getenv("GIT2HTML_BIN") or ("lua " .. project_dir .. "/src/git2html.lua")
end

-- Register early so require("test.runner") in tests reuses this module
package.loaded["test.runner"] = runner

function runner.skip(name, reason)
    runner.tests = runner.tests + 1
    runner.skipped = runner.skipped + 1
    local title = tostring(name)
    if #title > 130 then
        title = title:sub(1, 130)
    end
    print(string.format("[SKIP] %s", title))
end

function runner.skip_test(reason)
    error({ tag = runner.SKIP_TAG, reason = reason })
end

function runner.test(name, fn)
    runner.tests = runner.tests + 1
    local title = tostring(name)
    if #title > 130 then
        title = title:sub(1, 130)
    end
    local ok, err = pcall(fn)
    if ok then
        runner.passed = runner.passed + 1
        print(string.format("[PASS] %s", title))
    elseif type(err) == "table" and err.tag == runner.SKIP_TAG then
        runner.skipped = runner.skipped + 1
        print(string.format("[SKIP] %s", title))
    else
        runner.failed = runner.failed + 1
        print(string.format("[FAIL] %s", title))
        table.insert(runner.errors, { name = title, err = err })
    end
end

function runner.summary()
    if runner.is_suite then
        return
    end
    print(string.format("%d tests executed, %d passed, %d failed, %d skipped",
        runner.tests, runner.passed, runner.failed, runner.skipped))
    if #runner.errors > 0 then
        print("\nFailures:")
        for _, item in ipairs(runner.errors) do
            print(string.format("  - %s: %s", item.name, item.err))
        end
        os.exit(1)
    end
end

if not runner._running and arg and arg[0] and arg[0]:match("runner%.lua$") then
    runner._running = true
    runner.is_suite = true
    runner.tests = 0
    runner.passed = 0
    runner.failed = 0
    runner.skipped = 0
    runner.errors = {}

    local files = {}
    if #arg > 0 then
        for i = 1, #arg do
            table.insert(files, arg[i])
        end
    else
        local p = io.popen("ls test/*.test.lua 2>/dev/null | sort")
        if p then
            for line in p:lines() do
                table.insert(files, line)
            end
            p:close()
        end
    end

    for _, file in ipairs(files) do
        local ok, err = pcall(dofile, file)
        if not ok then
            runner.tests = runner.tests + 1
            runner.failed = runner.failed + 1
            local name = tostring(file):match("([^/]+)$") or file
            if #name > 130 then
                name = name:sub(1, 130)
            end
            print(string.format("[FAIL] %s", name))
            table.insert(runner.errors, { name = name, err = err })
        end
    end

    runner.is_suite = false
    runner.summary()
end

return runner
