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

test "parse Ruby source into pretty-printed AST" {
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

test "parseRubyAst returns ParseFailed on invalid source" {
    const allocator = std.testing.allocator;
    const src = "def hi; puts 'hello'";
    try std.testing.expectError(error.ParseFailed, parseRubyAst(allocator, src));
}
