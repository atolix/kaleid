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

    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :include") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :extend") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :define_method") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :Helpers") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "@ SingletonClassNode") != null);
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

    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :define_singleton_method") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "@ SingletonClassNode") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :define_method") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :make_method") != null);
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

    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :module_function") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :prepend") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "@ UndefNode") != null);
    try std.testing.expect(std.mem.indexOf(u8, pretty, "name: :alias_method") != null);
}
