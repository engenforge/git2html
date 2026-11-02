local lpeg = require('lpeg')
-- Zoril LPeg lexer.
--
-- Derived from the vendored Rust lexer (rust.lua, Copyright 2015-2020
-- Alejandro Baez, MIT License). Zoril's syntax deliberately follows Rust's;
-- the differences that matter here are its smaller keyword set, its lack of
-- lifetimes, byte strings and hash-delimited raw strings, and its nested
-- block comments.
--
-- Language reference: src/lexer.zrl and src/token.zrl in the Zoril repository.

local lexer = require("syntaxhighlight.textadept.lexer")
local token, word_match = lexer.token, lexer.word_match
local P, R, S = lpeg.P, lpeg.R, lpeg.S

local lex = lexer.new('zoril')

-- Whitespace.
lex:add_rule('whitespace', token(lexer.WHITESPACE, lexer.space^1))

-- Keywords. Zoril reserves exactly these; `true` and `false` are Boolean
-- literals and are styled as constants below.
lex:add_rule('keyword', token(lexer.KEYWORD, word_match[[
  fn struct enum trait impl let mut if else match while for loop unsafe in
  return break continue defer type pub extern box try sizeof alignof as
  const static import use
]]))

-- Boolean literals.
lex:add_rule('constant', token(lexer.CONSTANT, word_match[[true false]]))

-- `self` is not a keyword but is the conventional receiver name; `Self` is
-- the receiver type in trait declarations.
lex:add_rule('self', token('self', word_match[[self Self]]))
lex:add_style('self', lexer.STYLE_TYPE)

-- Type names: struct, enum, trait and generic names are capitalized.
lex:add_rule('type_name', token(lexer.LABEL, lexer.upper * (lexer.lower + lexer.dec_num)^1))

-- Primitive types.
lex:add_rule('type', token(lexer.TYPE, word_match[[
  bool char unit never u8 u16 u32 u64 usize i8 i16 i32 i64 isize f32 f64
]]))

-- Intrinsics: @syscall, @alloca, @ptr_cast<...>, ...
lex:add_rule('preprocessor', token(lexer.PREPROCESSOR, P('@') * lexer.word))

-- Numbers: decimal, hex (0x), binary (0b) and octal (0o), with '_'
-- separators and an optional integer suffix. A '.' only starts a fractional
-- part when a digit follows, so `0..10` remains a range.
local decimal = lexer.digit * (lexer.digit + '_')^0
local float = decimal * P('.') * decimal * (P('f32') + P('f64'))^-1
local function radix_integer(prefix, digit)
  return prefix * P('_')^0 * digit * (digit + '_')^0
end
local integer = (
  radix_integer(P('0x'), lexer.xdigit) +
  radix_integer(P('0b'), S('01')) +
  radix_integer(P('0o'), R('07')) +
  decimal
) * (S('iu') * (P('8') + '16' + '32' + '64' + 'size'))^-1
lex:add_rule('number', token(lexer.NUMBER, float + integer))

-- Strings. Quoted strings allow escapes and may span lines; r"..." raw
-- strings take no escapes. Character literals are single-quoted and use the
-- same escapes as quoted strings ('\n', '\x1B'). There are no lifetimes in
-- Zoril, so a leading single quote always starts a character literal.
local dq_str = lexer.range('"')
local raw_str = P('r') * lexer.range('"', false, false)
local char = lexer.range("'", true)
lex:add_rule('string', token(lexer.STRING, raw_str + dq_str + char))

-- Identifiers.
lex:add_rule('identifier', token(lexer.IDENTIFIER, lexer.word))

-- Comments: // to end of line, and /* ... */, which nests in Zoril.
local line_comment = lexer.to_eol('//')
local block_comment = lexer.range('/*', '*/', false, false, true)
lex:add_rule('comment', token(lexer.COMMENT, line_comment + block_comment))

-- Operators and punctuation.
lex:add_rule('operator', token(lexer.OPERATOR, S('+-/*%<>!=&|^?:;,.()[]{}@#')))

-- Fold points.
lex:add_fold_point(lexer.COMMENT, '/*', '*/')
lex:add_fold_point(lexer.COMMENT, '//', lexer.fold_line_comments('//'))
lex:add_fold_point(lexer.OPERATOR, '(', ')')
lex:add_fold_point(lexer.OPERATOR, '{', '}')

return lex
