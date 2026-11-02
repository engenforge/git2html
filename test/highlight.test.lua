package.path = './src/?.lua;./vendor/?.lua;./vendor/?/init.lua;' .. package.path; package.cpath = './build/?.so;./vendor/?.so;' .. package.cpath
local runner = require("test.runner")
local sh = require("syntaxhighlight")

runner.test("highlight.to_html highlights Lua keywords", function()
    local code = "local x = 1"
    local html = sh.highlight_to_html("lua", code, { bare = true, class_prefix = "" })
    assert(html:match("class=\"keyword\""), "local keyword not highlighted")
end)

local function zoril(code)
    local html, err = sh.highlight_to_html("zoril", code, { bare = true, class_prefix = "" })
    assert(html, err)
    return html
end

local function assert_span(html, class, text)
    local needle = 'class="' .. class .. '">' .. text .. "<"
    assert(html:find(needle, 1, true),
        "missing " .. class .. " span for " .. text .. "\n" .. html)
end

runner.test("highlight.to_html highlights Zoril keywords and types", function()
    local html = zoril("fn main() -> i32 { let mut x = 0; return x; }")
    assert_span(html, "keyword", "fn")
    assert_span(html, "keyword", "let")
    assert_span(html, "keyword", "mut")
    assert_span(html, "keyword", "return")
    assert_span(html, "type", "i32")
end)

runner.test("Zoril keywords match whole words only", function()
    local html = zoril("let deferred = 1; defer close(fd); let uses = 2;")
    assert_span(html, "identifier", "deferred")
    assert_span(html, "keyword", "defer")
    assert_span(html, "identifier", "uses")
end)

runner.test("Zoril types, constants, and numeric literals", function()
    local html = zoril(
        "let a: usize = 42usize; let b: f64 = 1.5f64;"
        .. " let ok = true; let no = false;"
        .. " let h = 0xFF_AB; let bin = 0b1010_0101; let oct = 0o755;")
    assert_span(html, "type", "usize")
    assert_span(html, "type", "f64")
    assert_span(html, "number", "42usize")
    assert_span(html, "number", "1.5f64")
    assert_span(html, "constant", "true")
    assert_span(html, "constant", "false")
    assert_span(html, "number", "0xFF_AB")
    assert_span(html, "number", "0b1010_0101")
    assert_span(html, "number", "0o755")
end)

runner.test("Zoril ranges are not parsed as floats", function()
    local html = zoril("for i in 0..10 { }")
    assert_span(html, "number", "0")
    assert_span(html, "operator", "..")
    assert_span(html, "number", "10")
end)

runner.test("Zoril strings, raw strings, and character escapes", function()
    local html = zoril([[
let a = "line\n";
let b = "// not a comment";
let c = r"raw // text";
let d = '\x1B';
]])
    assert_span(html, "string", "&quot;line\\n&quot;")
    assert_span(html, "string", "&quot;// not a comment&quot;")
    assert_span(html, "string", "r&quot;raw // text&quot;")
    assert_span(html, "string", "&#39;\\x1B&#39;")
    assert(not html:find('class="comment"', 1, true),
        "comment markers inside strings were highlighted as comments")
end)

runner.test("Zoril line and nested block comments", function()
    local html = zoril("// line one\n/* outer /* inner */ outer */\nlet x = 1;")
    assert_span(html, "comment", "// line one")
    assert_span(html, "comment", "/* outer /* inner */ outer */")
    assert_span(html, "keyword", "let")
end)

runner.test("Zoril operators, self, and intrinsic names", function()
    local html = zoril(
        "fn f(self: &Point) -> Option<u64> {"
        .. " x +%= 1; y = a :: b; @syscall(nr); @ptr_cast<&T>(p); }")
    assert(html:find('class="self type">self<', 1, true), "self receiver not highlighted")
    assert_span(html, "label", "Point")
    assert_span(html, "label", "Option")
    assert_span(html, "type", "u64")
    assert_span(html, "operator", "+%=")
    assert_span(html, "operator", "::")
    assert_span(html, "operator", "-&gt;")
    assert_span(html, "preprocessor", "@syscall")
    assert_span(html, "preprocessor", "@ptr_cast")
end)

runner.summary()
