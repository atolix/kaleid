const std = @import("std");

const c = @cImport({
    @cInclude("prism.h");
});

pub fn parseRubyAst(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var parser: c.pm_parser_t = undefined;
    c.pm_parser_init(&parser, source.ptr, source.len, null);
    defer c.pm_parser_free(&parser);

    const node = c.pm_parse(&parser);
    if (node == null) {
        return error.ParseFailed;
    }

    if (!c.pm_list_empty_p(&parser.error_list)) {
        return error.ParseFailed;
    }

    var buffer: c.pm_buffer_t = undefined;
    _ = c.pm_buffer_init(&buffer);
    defer c.pm_buffer_free(&buffer);

    c.pm_prettyprint(&buffer, &parser, node);

    const length = c.pm_buffer_length(&buffer);
    const result = try allocator.alloc(u8, length);
    errdefer allocator.free(result);

    const value_ptr = c.pm_buffer_value(&buffer);
    const slice = value_ptr[0..length];
    std.mem.copyForwards(u8, result, slice);
    return result;
}

test "parseRubyAst reports syntax error when def lacks end" {
    const allocator = std.testing.allocator;
    const src = "def hi; puts 'hello'";
    try std.testing.expectError(error.ParseFailed, parseRubyAst(allocator, src));
}

test "parse class with interpolated string" {
    const allocator = std.testing.allocator;
    const src =
        \\class Greeter
        \\  def hello(name)
        \\    puts "Hello, #{name}!"
        \\  end
        \\end
        \\
    ;
    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);
    const expected =
        \\@ ProgramNode (location: (1,0)-(5,3))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(5,3))
        \\    +-- body: (length: 1)
        \\        +-- @ ClassNode (location: (1,0)-(5,3))
        \\            +-- locals: []
        \\            +-- class_keyword_loc: (1,0)-(1,5) = "class"
        \\            +-- constant_path:
        \\            |   @ ConstantReadNode (location: (1,6)-(1,13))
        \\            |   +-- name: :Greeter
        \\            +-- inheritance_operator_loc: nil
        \\            +-- superclass: nil
        \\            +-- body:
        \\            |   @ StatementsNode (location: (2,2)-(4,5))
        \\            |   +-- body: (length: 1)
        \\            |       +-- @ DefNode (location: (2,2)-(4,5))
        \\            |           +-- name: :hello
        \\            |           +-- name_loc: (2,6)-(2,11) = "hello"
        \\            |           +-- receiver: nil
        \\            |           +-- parameters:
        \\            |           |   @ ParametersNode (location: (2,12)-(2,16))
        \\            |           |   +-- requireds: (length: 1)
        \\            |           |   |   +-- @ RequiredParameterNode (location: (2,12)-(2,16))
        \\            |           |   |       +-- ParameterFlags: nil
        \\            |           |   |       +-- name: :name
        \\            |           |   +-- optionals: (length: 0)
        \\            |           |   +-- rest: nil
        \\            |           |   +-- posts: (length: 0)
        \\            |           |   +-- keywords: (length: 0)
        \\            |           |   +-- keyword_rest: nil
        \\            |           |   +-- block: nil
        \\            |           +-- body:
        \\            |           |   @ StatementsNode (location: (3,4)-(3,26))
        \\            |           |   +-- body: (length: 1)
        \\            |           |       +-- @ CallNode (location: (3,4)-(3,26))
        \\            |           |           +-- CallNodeFlags: ignore_visibility
        \\            |           |           +-- receiver: nil
        \\            |           |           +-- call_operator_loc: nil
        \\            |           |           +-- name: :puts
        \\            |           |           +-- message_loc: (3,4)-(3,8) = "puts"
        \\            |           |           +-- opening_loc: nil
        \\            |           |           +-- arguments:
        \\            |           |           |   @ ArgumentsNode (location: (3,9)-(3,26))
        \\            |           |           |   +-- ArgumentsNodeFlags: nil
        \\            |           |           |   +-- arguments: (length: 1)
        \\            |           |           |       +-- @ InterpolatedStringNode (location: (3,9)-(3,26))
        \\            |           |           |           +-- InterpolatedStringNodeFlags: nil
        \\            |           |           |           +-- opening_loc: (3,9)-(3,10) = "\""
        \\            |           |           |           +-- parts: (length: 3)
        \\            |           |           |           |   +-- @ StringNode (location: (3,10)-(3,17))
        \\            |           |           |           |   |   +-- StringFlags: frozen
        \\            |           |           |           |   |   +-- opening_loc: nil
        \\            |           |           |           |   |   +-- content_loc: (3,10)-(3,17) = "Hello, "
        \\            |           |           |           |   |   +-- closing_loc: nil
        \\            |           |           |           |   |   +-- unescaped: "Hello, "
        \\            |           |           |           |   +-- @ EmbeddedStatementsNode (location: (3,17)-(3,24))
        \\            |           |           |           |   |   +-- opening_loc: (3,17)-(3,19) = "\#{"
        \\            |           |           |           |   |   +-- statements:
        \\            |           |           |           |   |   |   @ StatementsNode (location: (3,19)-(3,23))
        \\            |           |           |           |   |   |   +-- body: (length: 1)
        \\            |           |           |           |   |   |       +-- @ LocalVariableReadNode (location: (3,19)-(3,23))
        \\            |           |           |           |   |   |           +-- name: :name
        \\            |           |           |           |   |   |           +-- depth: 0
        \\            |           |           |           |   |   +-- closing_loc: (3,23)-(3,24) = "}"
        \\            |           |           |           |   +-- @ StringNode (location: (3,24)-(3,25))
        \\            |           |           |           |       +-- StringFlags: frozen
        \\            |           |           |           |       +-- opening_loc: nil
        \\            |           |           |           |       +-- content_loc: (3,24)-(3,25) = "!"
        \\            |           |           |           |       +-- closing_loc: nil
        \\            |           |           |           |       +-- unescaped: "!"
        \\            |           |           |           +-- closing_loc: (3,25)-(3,26) = "\""
        \\            |           |           +-- closing_loc: nil
        \\            |           |           +-- block: nil
        \\            |           +-- locals: [:name]
        \\            |           +-- def_keyword_loc: (2,2)-(2,5) = "def"
        \\            |           +-- operator_loc: nil
        \\            |           +-- lparen_loc: (2,11)-(2,12) = "("
        \\            |           +-- rparen_loc: (2,16)-(2,17) = ")"
        \\            |           +-- equal_loc: nil
        \\            |           +-- end_keyword_loc: (4,2)-(4,5) = "end"
        \\            +-- end_keyword_loc: (5,0)-(5,3) = "end"
        \\            +-- name: :Greeter
        \\
    ;
    try std.testing.expectEqualStrings(expected, pretty);
}

test "parse inline definition pretty print" {
    const allocator = std.testing.allocator;
    const src = "def hi; puts 'hello'; end";
    const expected =
        \\@ ProgramNode (location: (1,0)-(1,25))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(1,25))
        \\    +-- body: (length: 1)
        \\        +-- @ DefNode (location: (1,0)-(1,25))
        \\            +-- name: :hi
        \\            +-- name_loc: (1,4)-(1,6) = "hi"
        \\            +-- receiver: nil
        \\            +-- parameters: nil
        \\            +-- body:
        \\            |   @ StatementsNode (location: (1,8)-(1,20))
        \\            |   +-- body: (length: 1)
        \\            |       +-- @ CallNode (location: (1,8)-(1,20))
        \\            |           +-- CallNodeFlags: ignore_visibility
        \\            |           +-- receiver: nil
        \\            |           +-- call_operator_loc: nil
        \\            |           +-- name: :puts
        \\            |           +-- message_loc: (1,8)-(1,12) = "puts"
        \\            |           +-- opening_loc: nil
        \\            |           +-- arguments:
        \\            |           |   @ ArgumentsNode (location: (1,13)-(1,20))
        \\            |           |   +-- ArgumentsNodeFlags: nil
        \\            |           |   +-- arguments: (length: 1)
        \\            |           |       +-- @ StringNode (location: (1,13)-(1,20))
        \\            |           |           +-- StringFlags: nil
        \\            |           |           +-- opening_loc: (1,13)-(1,14) = "'"
        \\            |           |           +-- content_loc: (1,14)-(1,19) = "hello"
        \\            |           |           +-- closing_loc: (1,19)-(1,20) = "'"
        \\            |           |           +-- unescaped: "hello"
        \\            |           +-- closing_loc: nil
        \\            |           +-- block: nil
        \\            +-- locals: []
        \\            +-- def_keyword_loc: (1,0)-(1,3) = "def"
        \\            +-- operator_loc: nil
        \\            +-- lparen_loc: nil
        \\            +-- rparen_loc: nil
        \\            +-- equal_loc: nil
        \\            +-- end_keyword_loc: (1,22)-(1,25) = "end"
        \\
    ;

    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);

    try std.testing.expectEqualStrings(expected, pretty);
}

test "parse block with array literal receiver" {
    const allocator = std.testing.allocator;
    const src =
        \\[1, 2, 3].each do |n|
        \\  puts n * 2
        \\end
        \\
    ;
    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);
    const expected =
        \\@ ProgramNode (location: (1,0)-(3,3))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(3,3))
        \\    +-- body: (length: 1)
        \\        +-- @ CallNode (location: (1,0)-(3,3))
        \\            +-- CallNodeFlags: nil
        \\            +-- receiver:
        \\            |   @ ArrayNode (location: (1,0)-(1,9))
        \\            |   +-- ArrayNodeFlags: nil
        \\            |   +-- elements: (length: 3)
        \\            |   |   +-- @ IntegerNode (location: (1,1)-(1,2))
        \\            |   |   |   +-- IntegerBaseFlags: decimal
        \\            |   |   |   +-- value: 1
        \\            |   |   +-- @ IntegerNode (location: (1,4)-(1,5))
        \\            |   |   |   +-- IntegerBaseFlags: decimal
        \\            |   |   |   +-- value: 2
        \\            |   |   +-- @ IntegerNode (location: (1,7)-(1,8))
        \\            |   |       +-- IntegerBaseFlags: decimal
        \\            |   |       +-- value: 3
        \\            |   +-- opening_loc: (1,0)-(1,1) = "["
        \\            |   +-- closing_loc: (1,8)-(1,9) = "]"
        \\            +-- call_operator_loc: (1,9)-(1,10) = "."
        \\            +-- name: :each
        \\            +-- message_loc: (1,10)-(1,14) = "each"
        \\            +-- opening_loc: nil
        \\            +-- arguments: nil
        \\            +-- closing_loc: nil
        \\            +-- block:
        \\                @ BlockNode (location: (1,15)-(3,3))
        \\                +-- locals: [:n]
        \\                +-- parameters:
        \\                |   @ BlockParametersNode (location: (1,18)-(1,21))
        \\                |   +-- parameters:
        \\                |   |   @ ParametersNode (location: (1,19)-(1,20))
        \\                |   |   +-- requireds: (length: 1)
        \\                |   |   |   +-- @ RequiredParameterNode (location: (1,19)-(1,20))
        \\                |   |   |       +-- ParameterFlags: nil
        \\                |   |   |       +-- name: :n
        \\                |   |   +-- optionals: (length: 0)
        \\                |   |   +-- rest: nil
        \\                |   |   +-- posts: (length: 0)
        \\                |   |   +-- keywords: (length: 0)
        \\                |   |   +-- keyword_rest: nil
        \\                |   |   +-- block: nil
        \\                |   +-- locals: (length: 0)
        \\                |   +-- opening_loc: (1,18)-(1,19) = "|"
        \\                |   +-- closing_loc: (1,20)-(1,21) = "|"
        \\                +-- body:
        \\                |   @ StatementsNode (location: (2,2)-(2,12))
        \\                |   +-- body: (length: 1)
        \\                |       +-- @ CallNode (location: (2,2)-(2,12))
        \\                |           +-- CallNodeFlags: ignore_visibility
        \\                |           +-- receiver: nil
        \\                |           +-- call_operator_loc: nil
        \\                |           +-- name: :puts
        \\                |           +-- message_loc: (2,2)-(2,6) = "puts"
        \\                |           +-- opening_loc: nil
        \\                |           +-- arguments:
        \\                |           |   @ ArgumentsNode (location: (2,7)-(2,12))
        \\                |           |   +-- ArgumentsNodeFlags: nil
        \\                |           |   +-- arguments: (length: 1)
        \\                |           |       +-- @ CallNode (location: (2,7)-(2,12))
        \\                |           |           +-- CallNodeFlags: nil
        \\                |           |           +-- receiver:
        \\                |           |           |   @ LocalVariableReadNode (location: (2,7)-(2,8))
        \\                |           |           |   +-- name: :n
        \\                |           |           |   +-- depth: 0
        \\                |           |           +-- call_operator_loc: nil
        \\                |           |           +-- name: :*
        \\                |           |           +-- message_loc: (2,9)-(2,10) = "*"
        \\                |           |           +-- opening_loc: nil
        \\                |           |           +-- arguments:
        \\                |           |           |   @ ArgumentsNode (location: (2,11)-(2,12))
        \\                |           |           |   +-- ArgumentsNodeFlags: nil
        \\                |           |           |   +-- arguments: (length: 1)
        \\                |           |           |       +-- @ IntegerNode (location: (2,11)-(2,12))
        \\                |           |           |           +-- IntegerBaseFlags: decimal
        \\                |           |           |           +-- value: 2
        \\                |           |           +-- closing_loc: nil
        \\                |           |           +-- block: nil
        \\                |           +-- closing_loc: nil
        \\                |           +-- block: nil
        \\                +-- opening_loc: (1,15)-(1,17) = "do"
        \\                +-- closing_loc: (3,0)-(3,3) = "end"
        \\
    ;
    try std.testing.expectEqualStrings(expected, pretty);
}

test "class with include extend and define_method" {
    const allocator = std.testing.allocator;
    const src =
        \\module Helpers
        \\  def helper; :helper end
        \\end
        \\
        \\class Greeter
        \\  include Helpers
        \\  extend Helpers
        \\
        \\  define_method(:greet) do |name|
        \\    puts "hi #{name}"
        \\  end
        \\
        \\  class << self
        \\    include Helpers
        \\  end
        \\end
        \\
    ;

    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);

    const expected =
        \\@ ProgramNode (location: (1,0)-(16,3))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(16,3))
        \\    +-- body: (length: 2)
        \\        +-- @ ModuleNode (location: (1,0)-(3,3))
        \\        |   +-- locals: []
        \\        |   +-- module_keyword_loc: (1,0)-(1,6) = "module"
        \\        |   +-- constant_path:
        \\        |   |   @ ConstantReadNode (location: (1,7)-(1,14))
        \\        |   |   +-- name: :Helpers
        \\        |   +-- body:
        \\        |   |   @ StatementsNode (location: (2,2)-(2,25))
        \\        |   |   +-- body: (length: 1)
        \\        |   |       +-- @ DefNode (location: (2,2)-(2,25))
        \\        |   |           +-- name: :helper
        \\        |   |           +-- name_loc: (2,6)-(2,12) = "helper"
        \\        |   |           +-- receiver: nil
        \\        |   |           +-- parameters: nil
        \\        |   |           +-- body:
        \\        |   |           |   @ StatementsNode (location: (2,14)-(2,21))
        \\        |   |           |   +-- body: (length: 1)
        \\        |   |           |       +-- @ SymbolNode (location: (2,14)-(2,21))
        \\        |   |           |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |           |           +-- opening_loc: (2,14)-(2,15) = ":"
        \\        |   |           |           +-- value_loc: (2,15)-(2,21) = "helper"
        \\        |   |           |           +-- closing_loc: nil
        \\        |   |           |           +-- unescaped: "helper"
        \\        |   |           +-- locals: []
        \\        |   |           +-- def_keyword_loc: (2,2)-(2,5) = "def"
        \\        |   |           +-- operator_loc: nil
        \\        |   |           +-- lparen_loc: nil
        \\        |   |           +-- rparen_loc: nil
        \\        |   |           +-- equal_loc: nil
        \\        |   |           +-- end_keyword_loc: (2,22)-(2,25) = "end"
        \\        |   +-- end_keyword_loc: (3,0)-(3,3) = "end"
        \\        |   +-- name: :Helpers
        \\        +-- @ ClassNode (location: (5,0)-(16,3))
        \\            +-- locals: []
        \\            +-- class_keyword_loc: (5,0)-(5,5) = "class"
        \\            +-- constant_path:
        \\            |   @ ConstantReadNode (location: (5,6)-(5,13))
        \\            |   +-- name: :Greeter
        \\            +-- inheritance_operator_loc: nil
        \\            +-- superclass: nil
        \\            +-- body:
        \\            |   @ StatementsNode (location: (6,2)-(15,5))
        \\            |   +-- body: (length: 4)
        \\            |       +-- @ CallNode (location: (6,2)-(6,17))
        \\            |       |   +-- CallNodeFlags: ignore_visibility
        \\            |       |   +-- receiver: nil
        \\            |       |   +-- call_operator_loc: nil
        \\            |       |   +-- name: :include
        \\            |       |   +-- message_loc: (6,2)-(6,9) = "include"
        \\            |       |   +-- opening_loc: nil
        \\            |       |   +-- arguments:
        \\            |       |   |   @ ArgumentsNode (location: (6,10)-(6,17))
        \\            |       |   |   +-- ArgumentsNodeFlags: nil
        \\            |       |   |   +-- arguments: (length: 1)
        \\            |       |   |       +-- @ ConstantReadNode (location: (6,10)-(6,17))
        \\            |       |   |           +-- name: :Helpers
        \\            |       |   +-- closing_loc: nil
        \\            |       |   +-- block: nil
        \\            |       +-- @ CallNode (location: (7,2)-(7,16))
        \\            |       |   +-- CallNodeFlags: ignore_visibility
        \\            |       |   +-- receiver: nil
        \\            |       |   +-- call_operator_loc: nil
        \\            |       |   +-- name: :extend
        \\            |       |   +-- message_loc: (7,2)-(7,8) = "extend"
        \\            |       |   +-- opening_loc: nil
        \\            |       |   +-- arguments:
        \\            |       |   |   @ ArgumentsNode (location: (7,9)-(7,16))
        \\            |       |   |   +-- ArgumentsNodeFlags: nil
        \\            |       |   |   +-- arguments: (length: 1)
        \\            |       |   |       +-- @ ConstantReadNode (location: (7,9)-(7,16))
        \\            |       |   |           +-- name: :Helpers
        \\            |       |   +-- closing_loc: nil
        \\            |       |   +-- block: nil
        \\            |       +-- @ CallNode (location: (9,2)-(11,5))
        \\            |       |   +-- CallNodeFlags: ignore_visibility
        \\            |       |   +-- receiver: nil
        \\            |       |   +-- call_operator_loc: nil
        \\            |       |   +-- name: :define_method
        \\            |       |   +-- message_loc: (9,2)-(9,15) = "define_method"
        \\            |       |   +-- opening_loc: (9,15)-(9,16) = "("
        \\            |       |   +-- arguments:
        \\            |       |   |   @ ArgumentsNode (location: (9,16)-(9,22))
        \\            |       |   |   +-- ArgumentsNodeFlags: nil
        \\            |       |   |   +-- arguments: (length: 1)
        \\            |       |   |       +-- @ SymbolNode (location: (9,16)-(9,22))
        \\            |       |   |           +-- SymbolFlags: forced_us_ascii_encoding
        \\            |       |   |           +-- opening_loc: (9,16)-(9,17) = ":"
        \\            |       |   |           +-- value_loc: (9,17)-(9,22) = "greet"
        \\            |       |   |           +-- closing_loc: nil
        \\            |       |   |           +-- unescaped: "greet"
        \\            |       |   +-- closing_loc: (9,22)-(9,23) = ")"
        \\            |       |   +-- block:
        \\            |       |       @ BlockNode (location: (9,24)-(11,5))
        \\            |       |       +-- locals: [:name]
        \\            |       |       +-- parameters:
        \\            |       |       |   @ BlockParametersNode (location: (9,27)-(9,33))
        \\            |       |       |   +-- parameters:
        \\            |       |       |   |   @ ParametersNode (location: (9,28)-(9,32))
        \\            |       |       |   |   +-- requireds: (length: 1)
        \\            |       |       |   |   |   +-- @ RequiredParameterNode (location: (9,28)-(9,32))
        \\            |       |       |   |   |       +-- ParameterFlags: nil
        \\            |       |       |   |   |       +-- name: :name
        \\            |       |       |   |   +-- optionals: (length: 0)
        \\            |       |       |   |   +-- rest: nil
        \\            |       |       |   |   +-- posts: (length: 0)
        \\            |       |       |   |   +-- keywords: (length: 0)
        \\            |       |       |   |   +-- keyword_rest: nil
        \\            |       |       |   |   +-- block: nil
        \\            |       |       |   +-- locals: (length: 0)
        \\            |       |       |   +-- opening_loc: (9,27)-(9,28) = "|"
        \\            |       |       |   +-- closing_loc: (9,32)-(9,33) = "|"
        \\            |       |       +-- body:
        \\            |       |       |   @ StatementsNode (location: (10,4)-(10,21))
        \\            |       |       |   +-- body: (length: 1)
        \\            |       |       |       +-- @ CallNode (location: (10,4)-(10,21))
        \\            |       |       |           +-- CallNodeFlags: ignore_visibility
        \\            |       |       |           +-- receiver: nil
        \\            |       |       |           +-- call_operator_loc: nil
        \\            |       |       |           +-- name: :puts
        \\            |       |       |           +-- message_loc: (10,4)-(10,8) = "puts"
        \\            |       |       |           +-- opening_loc: nil
        \\            |       |       |           +-- arguments:
        \\            |       |       |           |   @ ArgumentsNode (location: (10,9)-(10,21))
        \\            |       |       |           |   +-- ArgumentsNodeFlags: nil
        \\            |       |       |           |   +-- arguments: (length: 1)
        \\            |       |       |           |       +-- @ InterpolatedStringNode (location: (10,9)-(10,21))
        \\            |       |       |           |           +-- InterpolatedStringNodeFlags: nil
        \\            |       |       |           |           +-- opening_loc: (10,9)-(10,10) = "\""
        \\            |       |       |           |           +-- parts: (length: 2)
        \\            |       |       |           |           |   +-- @ StringNode (location: (10,10)-(10,13))
        \\            |       |       |           |           |   |   +-- StringFlags: frozen
        \\            |       |       |           |           |   |   +-- opening_loc: nil
        \\            |       |       |           |           |   |   +-- content_loc: (10,10)-(10,13) = "hi "
        \\            |       |       |           |           |   |   +-- closing_loc: nil
        \\            |       |       |           |           |   |   +-- unescaped: "hi "
        \\            |       |       |           |           |   +-- @ EmbeddedStatementsNode (location: (10,13)-(10,20))
        \\            |       |       |           |           |       +-- opening_loc: (10,13)-(10,15) = "\#{"
        \\            |       |       |           |           |       +-- statements:
        \\            |       |       |           |           |       |   @ StatementsNode (location: (10,15)-(10,19))
        \\            |       |       |           |           |       |   +-- body: (length: 1)
        \\            |       |       |           |           |       |       +-- @ LocalVariableReadNode (location: (10,15)-(10,19))
        \\            |       |       |           |           |       |           +-- name: :name
        \\            |       |       |           |           |       |           +-- depth: 0
        \\            |       |       |           |           |       +-- closing_loc: (10,19)-(10,20) = "}"
        \\            |       |       |           |           +-- closing_loc: (10,20)-(10,21) = "\""
        \\            |       |       |           +-- closing_loc: nil
        \\            |       |       |           +-- block: nil
        \\            |       |       +-- opening_loc: (9,24)-(9,26) = "do"
        \\            |       |       +-- closing_loc: (11,2)-(11,5) = "end"
        \\            |       +-- @ SingletonClassNode (location: (13,2)-(15,5))
        \\            |           +-- locals: []
        \\            |           +-- class_keyword_loc: (13,2)-(13,7) = "class"
        \\            |           +-- operator_loc: (13,8)-(13,10) = "<<"
        \\            |           +-- expression:
        \\            |           |   @ SelfNode (location: (13,11)-(13,15))
        \\            |           +-- body:
        \\            |           |   @ StatementsNode (location: (14,4)-(14,19))
        \\            |           |   +-- body: (length: 1)
        \\            |           |       +-- @ CallNode (location: (14,4)-(14,19))
        \\            |           |           +-- CallNodeFlags: ignore_visibility
        \\            |           |           +-- receiver: nil
        \\            |           |           +-- call_operator_loc: nil
        \\            |           |           +-- name: :include
        \\            |           |           +-- message_loc: (14,4)-(14,11) = "include"
        \\            |           |           +-- opening_loc: nil
        \\            |           |           +-- arguments:
        \\            |           |           |   @ ArgumentsNode (location: (14,12)-(14,19))
        \\            |           |           |   +-- ArgumentsNodeFlags: nil
        \\            |           |           |   +-- arguments: (length: 1)
        \\            |           |           |       +-- @ ConstantReadNode (location: (14,12)-(14,19))
        \\            |           |           |           +-- name: :Helpers
        \\            |           |           +-- closing_loc: nil
        \\            |           |           +-- block: nil
        \\            |           +-- end_keyword_loc: (15,2)-(15,5) = "end"
        \\            +-- end_keyword_loc: (16,0)-(16,3) = "end"
        \\            +-- name: :Greeter
        \\
    ;
    try std.testing.expectEqualStrings(expected, pretty);
}
test "singleton class define_singleton_method and define_method" {
    const allocator = std.testing.allocator;
    const src =
        \\class << self
        \\  define_singleton_method(:foo) { :foo }
        \\end
        \\
        \\def self.make_method(name)
        \\  define_method(name) { puts name }
        \\end
        \\
    ;

    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);

    const expected =
        \\@ ProgramNode (location: (1,0)-(7,3))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(7,3))
        \\    +-- body: (length: 2)
        \\        +-- @ SingletonClassNode (location: (1,0)-(3,3))
        \\        |   +-- locals: []
        \\        |   +-- class_keyword_loc: (1,0)-(1,5) = "class"
        \\        |   +-- operator_loc: (1,6)-(1,8) = "<<"
        \\        |   +-- expression:
        \\        |   |   @ SelfNode (location: (1,9)-(1,13))
        \\        |   +-- body:
        \\        |   |   @ StatementsNode (location: (2,2)-(2,40))
        \\        |   |   +-- body: (length: 1)
        \\        |   |       +-- @ CallNode (location: (2,2)-(2,40))
        \\        |   |           +-- CallNodeFlags: ignore_visibility
        \\        |   |           +-- receiver: nil
        \\        |   |           +-- call_operator_loc: nil
        \\        |   |           +-- name: :define_singleton_method
        \\        |   |           +-- message_loc: (2,2)-(2,25) = "define_singleton_method"
        \\        |   |           +-- opening_loc: (2,25)-(2,26) = "("
        \\        |   |           +-- arguments:
        \\        |   |           |   @ ArgumentsNode (location: (2,26)-(2,30))
        \\        |   |           |   +-- ArgumentsNodeFlags: nil
        \\        |   |           |   +-- arguments: (length: 1)
        \\        |   |           |       +-- @ SymbolNode (location: (2,26)-(2,30))
        \\        |   |           |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |           |           +-- opening_loc: (2,26)-(2,27) = ":"
        \\        |   |           |           +-- value_loc: (2,27)-(2,30) = "foo"
        \\        |   |           |           +-- closing_loc: nil
        \\        |   |           |           +-- unescaped: "foo"
        \\        |   |           +-- closing_loc: (2,30)-(2,31) = ")"
        \\        |   |           +-- block:
        \\        |   |               @ BlockNode (location: (2,32)-(2,40))
        \\        |   |               +-- locals: []
        \\        |   |               +-- parameters: nil
        \\        |   |               +-- body:
        \\        |   |               |   @ StatementsNode (location: (2,34)-(2,38))
        \\        |   |               |   +-- body: (length: 1)
        \\        |   |               |       +-- @ SymbolNode (location: (2,34)-(2,38))
        \\        |   |               |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |               |           +-- opening_loc: (2,34)-(2,35) = ":"
        \\        |   |               |           +-- value_loc: (2,35)-(2,38) = "foo"
        \\        |   |               |           +-- closing_loc: nil
        \\        |   |               |           +-- unescaped: "foo"
        \\        |   |               +-- opening_loc: (2,32)-(2,33) = "{"
        \\        |   |               +-- closing_loc: (2,39)-(2,40) = "}"
        \\        |   +-- end_keyword_loc: (3,0)-(3,3) = "end"
        \\        +-- @ DefNode (location: (5,0)-(7,3))
        \\            +-- name: :make_method
        \\            +-- name_loc: (5,9)-(5,20) = "make_method"
        \\            +-- receiver:
        \\            |   @ SelfNode (location: (5,4)-(5,8))
        \\            +-- parameters:
        \\            |   @ ParametersNode (location: (5,21)-(5,25))
        \\            |   +-- requireds: (length: 1)
        \\            |   |   +-- @ RequiredParameterNode (location: (5,21)-(5,25))
        \\            |   |       +-- ParameterFlags: nil
        \\            |   |       +-- name: :name
        \\            |   +-- optionals: (length: 0)
        \\            |   +-- rest: nil
        \\            |   +-- posts: (length: 0)
        \\            |   +-- keywords: (length: 0)
        \\            |   +-- keyword_rest: nil
        \\            |   +-- block: nil
        \\            +-- body:
        \\            |   @ StatementsNode (location: (6,2)-(6,35))
        \\            |   +-- body: (length: 1)
        \\            |       +-- @ CallNode (location: (6,2)-(6,35))
        \\            |           +-- CallNodeFlags: ignore_visibility
        \\            |           +-- receiver: nil
        \\            |           +-- call_operator_loc: nil
        \\            |           +-- name: :define_method
        \\            |           +-- message_loc: (6,2)-(6,15) = "define_method"
        \\            |           +-- opening_loc: (6,15)-(6,16) = "("
        \\            |           +-- arguments:
        \\            |           |   @ ArgumentsNode (location: (6,16)-(6,20))
        \\            |           |   +-- ArgumentsNodeFlags: nil
        \\            |           |   +-- arguments: (length: 1)
        \\            |           |       +-- @ LocalVariableReadNode (location: (6,16)-(6,20))
        \\            |           |           +-- name: :name
        \\            |           |           +-- depth: 0
        \\            |           +-- closing_loc: (6,20)-(6,21) = ")"
        \\            |           +-- block:
        \\            |               @ BlockNode (location: (6,22)-(6,35))
        \\            |               +-- locals: []
        \\            |               +-- parameters: nil
        \\            |               +-- body:
        \\            |               |   @ StatementsNode (location: (6,24)-(6,33))
        \\            |               |   +-- body: (length: 1)
        \\            |               |       +-- @ CallNode (location: (6,24)-(6,33))
        \\            |               |           +-- CallNodeFlags: ignore_visibility
        \\            |               |           +-- receiver: nil
        \\            |               |           +-- call_operator_loc: nil
        \\            |               |           +-- name: :puts
        \\            |               |           +-- message_loc: (6,24)-(6,28) = "puts"
        \\            |               |           +-- opening_loc: nil
        \\            |               |           +-- arguments:
        \\            |               |           |   @ ArgumentsNode (location: (6,29)-(6,33))
        \\            |               |           |   +-- ArgumentsNodeFlags: nil
        \\            |               |           |   +-- arguments: (length: 1)
        \\            |               |           |       +-- @ LocalVariableReadNode (location: (6,29)-(6,33))
        \\            |               |           |           +-- name: :name
        \\            |               |           |           +-- depth: 1
        \\            |               |           +-- closing_loc: nil
        \\            |               |           +-- block: nil
        \\            |               +-- opening_loc: (6,22)-(6,23) = "{"
        \\            |               +-- closing_loc: (6,34)-(6,35) = "}"
        \\            +-- locals: [:name]
        \\            +-- def_keyword_loc: (5,0)-(5,3) = "def"
        \\            +-- operator_loc: (5,8)-(5,9) = "."
        \\            +-- lparen_loc: (5,20)-(5,21) = "("
        \\            +-- rparen_loc: (5,25)-(5,26) = ")"
        \\            +-- equal_loc: nil
        \\            +-- end_keyword_loc: (7,0)-(7,3) = "end"
        \\
    ;
    try std.testing.expectEqualStrings(expected, pretty);
}
test "module_function prepend alias and undef usage" {
    const allocator = std.testing.allocator;
    const src =
        \\module Helpers
        \\  def helper; :helper end
        \\  module_function :helper
        \\end
        \\
        \\class Example < Object
        \\  prepend Helpers
        \\  alias_method :greet, :helper
        \\  undef :old_method
        \\end
        \\
        \\Example.extend Helpers
        \\Example.module_function(:helper)
        \\
    ;

    const pretty = try parseRubyAst(allocator, src);
    defer allocator.free(pretty);

    const expected =
        \\@ ProgramNode (location: (1,0)-(13,32))
        \\+-- locals: []
        \\+-- statements:
        \\    @ StatementsNode (location: (1,0)-(13,32))
        \\    +-- body: (length: 4)
        \\        +-- @ ModuleNode (location: (1,0)-(4,3))
        \\        |   +-- locals: []
        \\        |   +-- module_keyword_loc: (1,0)-(1,6) = "module"
        \\        |   +-- constant_path:
        \\        |   |   @ ConstantReadNode (location: (1,7)-(1,14))
        \\        |   |   +-- name: :Helpers
        \\        |   +-- body:
        \\        |   |   @ StatementsNode (location: (2,2)-(3,25))
        \\        |   |   +-- body: (length: 2)
        \\        |   |       +-- @ DefNode (location: (2,2)-(2,25))
        \\        |   |       |   +-- name: :helper
        \\        |   |       |   +-- name_loc: (2,6)-(2,12) = "helper"
        \\        |   |       |   +-- receiver: nil
        \\        |   |       |   +-- parameters: nil
        \\        |   |       |   +-- body:
        \\        |   |       |   |   @ StatementsNode (location: (2,14)-(2,21))
        \\        |   |       |   |   +-- body: (length: 1)
        \\        |   |       |   |       +-- @ SymbolNode (location: (2,14)-(2,21))
        \\        |   |       |   |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |       |   |           +-- opening_loc: (2,14)-(2,15) = ":"
        \\        |   |       |   |           +-- value_loc: (2,15)-(2,21) = "helper"
        \\        |   |       |   |           +-- closing_loc: nil
        \\        |   |       |   |           +-- unescaped: "helper"
        \\        |   |       |   +-- locals: []
        \\        |   |       |   +-- def_keyword_loc: (2,2)-(2,5) = "def"
        \\        |   |       |   +-- operator_loc: nil
        \\        |   |       |   +-- lparen_loc: nil
        \\        |   |       |   +-- rparen_loc: nil
        \\        |   |       |   +-- equal_loc: nil
        \\        |   |       |   +-- end_keyword_loc: (2,22)-(2,25) = "end"
        \\        |   |       +-- @ CallNode (location: (3,2)-(3,25))
        \\        |   |           +-- CallNodeFlags: ignore_visibility
        \\        |   |           +-- receiver: nil
        \\        |   |           +-- call_operator_loc: nil
        \\        |   |           +-- name: :module_function
        \\        |   |           +-- message_loc: (3,2)-(3,17) = "module_function"
        \\        |   |           +-- opening_loc: nil
        \\        |   |           +-- arguments:
        \\        |   |           |   @ ArgumentsNode (location: (3,18)-(3,25))
        \\        |   |           |   +-- ArgumentsNodeFlags: nil
        \\        |   |           |   +-- arguments: (length: 1)
        \\        |   |           |       +-- @ SymbolNode (location: (3,18)-(3,25))
        \\        |   |           |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |           |           +-- opening_loc: (3,18)-(3,19) = ":"
        \\        |   |           |           +-- value_loc: (3,19)-(3,25) = "helper"
        \\        |   |           |           +-- closing_loc: nil
        \\        |   |           |           +-- unescaped: "helper"
        \\        |   |           +-- closing_loc: nil
        \\        |   |           +-- block: nil
        \\        |   +-- end_keyword_loc: (4,0)-(4,3) = "end"
        \\        |   +-- name: :Helpers
        \\        +-- @ ClassNode (location: (6,0)-(10,3))
        \\        |   +-- locals: []
        \\        |   +-- class_keyword_loc: (6,0)-(6,5) = "class"
        \\        |   +-- constant_path:
        \\        |   |   @ ConstantReadNode (location: (6,6)-(6,13))
        \\        |   |   +-- name: :Example
        \\        |   +-- inheritance_operator_loc: (6,14)-(6,15) = "<"
        \\        |   +-- superclass:
        \\        |   |   @ ConstantReadNode (location: (6,16)-(6,22))
        \\        |   |   +-- name: :Object
        \\        |   +-- body:
        \\        |   |   @ StatementsNode (location: (7,2)-(9,19))
        \\        |   |   +-- body: (length: 3)
        \\        |   |       +-- @ CallNode (location: (7,2)-(7,17))
        \\        |   |       |   +-- CallNodeFlags: ignore_visibility
        \\        |   |       |   +-- receiver: nil
        \\        |   |       |   +-- call_operator_loc: nil
        \\        |   |       |   +-- name: :prepend
        \\        |   |       |   +-- message_loc: (7,2)-(7,9) = "prepend"
        \\        |   |       |   +-- opening_loc: nil
        \\        |   |       |   +-- arguments:
        \\        |   |       |   |   @ ArgumentsNode (location: (7,10)-(7,17))
        \\        |   |       |   |   +-- ArgumentsNodeFlags: nil
        \\        |   |       |   |   +-- arguments: (length: 1)
        \\        |   |       |   |       +-- @ ConstantReadNode (location: (7,10)-(7,17))
        \\        |   |       |   |           +-- name: :Helpers
        \\        |   |       |   +-- closing_loc: nil
        \\        |   |       |   +-- block: nil
        \\        |   |       +-- @ CallNode (location: (8,2)-(8,30))
        \\        |   |       |   +-- CallNodeFlags: ignore_visibility
        \\        |   |       |   +-- receiver: nil
        \\        |   |       |   +-- call_operator_loc: nil
        \\        |   |       |   +-- name: :alias_method
        \\        |   |       |   +-- message_loc: (8,2)-(8,14) = "alias_method"
        \\        |   |       |   +-- opening_loc: nil
        \\        |   |       |   +-- arguments:
        \\        |   |       |   |   @ ArgumentsNode (location: (8,15)-(8,30))
        \\        |   |       |   |   +-- ArgumentsNodeFlags: nil
        \\        |   |       |   |   +-- arguments: (length: 2)
        \\        |   |       |   |       +-- @ SymbolNode (location: (8,15)-(8,21))
        \\        |   |       |   |       |   +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |       |   |       |   +-- opening_loc: (8,15)-(8,16) = ":"
        \\        |   |       |   |       |   +-- value_loc: (8,16)-(8,21) = "greet"
        \\        |   |       |   |       |   +-- closing_loc: nil
        \\        |   |       |   |       |   +-- unescaped: "greet"
        \\        |   |       |   |       +-- @ SymbolNode (location: (8,23)-(8,30))
        \\        |   |       |   |           +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |       |   |           +-- opening_loc: (8,23)-(8,24) = ":"
        \\        |   |       |   |           +-- value_loc: (8,24)-(8,30) = "helper"
        \\        |   |       |   |           +-- closing_loc: nil
        \\        |   |       |   |           +-- unescaped: "helper"
        \\        |   |       |   +-- closing_loc: nil
        \\        |   |       |   +-- block: nil
        \\        |   |       +-- @ UndefNode (location: (9,2)-(9,19))
        \\        |   |           +-- names: (length: 1)
        \\        |   |           |   +-- @ SymbolNode (location: (9,8)-(9,19))
        \\        |   |           |       +-- SymbolFlags: forced_us_ascii_encoding
        \\        |   |           |       +-- opening_loc: (9,8)-(9,9) = ":"
        \\        |   |           |       +-- value_loc: (9,9)-(9,19) = "old_method"
        \\        |   |           |       +-- closing_loc: nil
        \\        |   |           |       +-- unescaped: "old_method"
        \\        |   |           +-- keyword_loc: (9,2)-(9,7) = "undef"
        \\        |   +-- end_keyword_loc: (10,0)-(10,3) = "end"
        \\        |   +-- name: :Example
        \\        +-- @ CallNode (location: (12,0)-(12,22))
        \\        |   +-- CallNodeFlags: nil
        \\        |   +-- receiver:
        \\        |   |   @ ConstantReadNode (location: (12,0)-(12,7))
        \\        |   |   +-- name: :Example
        \\        |   +-- call_operator_loc: (12,7)-(12,8) = "."
        \\        |   +-- name: :extend
        \\        |   +-- message_loc: (12,8)-(12,14) = "extend"
        \\        |   +-- opening_loc: nil
        \\        |   +-- arguments:
        \\        |   |   @ ArgumentsNode (location: (12,15)-(12,22))
        \\        |   |   +-- ArgumentsNodeFlags: nil
        \\        |   |   +-- arguments: (length: 1)
        \\        |   |       +-- @ ConstantReadNode (location: (12,15)-(12,22))
        \\        |   |           +-- name: :Helpers
        \\        |   +-- closing_loc: nil
        \\        |   +-- block: nil
        \\        +-- @ CallNode (location: (13,0)-(13,32))
        \\            +-- CallNodeFlags: nil
        \\            +-- receiver:
        \\            |   @ ConstantReadNode (location: (13,0)-(13,7))
        \\            |   +-- name: :Example
        \\            +-- call_operator_loc: (13,7)-(13,8) = "."
        \\            +-- name: :module_function
        \\            +-- message_loc: (13,8)-(13,23) = "module_function"
        \\            +-- opening_loc: (13,23)-(13,24) = "("
        \\            +-- arguments:
        \\            |   @ ArgumentsNode (location: (13,24)-(13,31))
        \\            |   +-- ArgumentsNodeFlags: nil
        \\            |   +-- arguments: (length: 1)
        \\            |       +-- @ SymbolNode (location: (13,24)-(13,31))
        \\            |           +-- SymbolFlags: forced_us_ascii_encoding
        \\            |           +-- opening_loc: (13,24)-(13,25) = ":"
        \\            |           +-- value_loc: (13,25)-(13,31) = "helper"
        \\            |           +-- closing_loc: nil
        \\            |           +-- unescaped: "helper"
        \\            +-- closing_loc: (13,31)-(13,32) = ")"
        \\            +-- block: nil
        \\
    ;
    try std.testing.expectEqualStrings(expected, pretty);
}


