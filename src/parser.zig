const std = @import("std");

const common = @import("parser/common.zig");
const types = @import("parser/types.zig");
const api = @import("parser/api.zig");
const test_utils = @import("test/utils.zig");

pub const prism = common.prism;
pub const NodeKind = types.NodeKind;

pub const Position = types.Position;
pub const Span = types.Span;
pub const AstNode = types.AstNode;
pub const ParseTree = types.ParseTree;
pub const nodeKindName = types.nodeKindName;
pub const nodeKindFromC = types.nodeKindFromC;
pub const parseRubyAst = api.parseRubyAst;

test "parseRubyAst reports syntax error when def lacks end" {
    const allocator = std.testing.allocator;
    const src = "def hi; puts 'hello'";
    try std.testing.expectError(error.ParseFailed, parseRubyAst(allocator, src));
}

test "parseRubyAst builds nested structure for class definition" {
    const allocator = std.testing.allocator;
    const src =
        \\class Greeter
        \\  def hello(name)
        \\    puts "Hello, #{name}!"
        \\  end
        \\end
        \\
    ;

    var tree = try parseRubyAst(allocator, src);
    defer tree.deinit();

    const c = common.c;
    const program_kind = nodeKindFromC(c.PM_PROGRAM_NODE);
    const statements_kind = nodeKindFromC(c.PM_STATEMENTS_NODE);
    const class_kind = nodeKindFromC(c.PM_CLASS_NODE);
    const def_kind = nodeKindFromC(c.PM_DEF_NODE);
    const call_kind = nodeKindFromC(c.PM_CALL_NODE);
    const interpolated_kind = nodeKindFromC(c.PM_INTERPOLATED_STRING_NODE);

    try std.testing.expectEqual(program_kind, tree.root.kind);

    const statements = test_utils.findChild(&tree.root, statements_kind) orelse return error.MissingStatements;
    const class_node = test_utils.findChild(statements, class_kind) orelse return error.MissingClass;
    const class_body = test_utils.findChild(class_node, statements_kind) orelse return error.MissingClassBody;
    const def_node = test_utils.findChild(class_body, def_kind) orelse return error.MissingDef;
    const def_body = test_utils.findChild(def_node, statements_kind) orelse return error.MissingDefBody;
    const call_node = test_utils.findChild(def_body, call_kind) orelse return error.MissingCall;

    try std.testing.expect(test_utils.hasNode(call_node, interpolated_kind));
}

test "parseRubyAst records byte spans and line information" {
    const allocator = std.testing.allocator;
    const src =
        \\def hi
        \\  puts 'hello'
        \\end
        \\
    ;

    var tree = try parseRubyAst(allocator, src);
    defer tree.deinit();

    const c = common.c;
    const statements_kind = nodeKindFromC(c.PM_STATEMENTS_NODE);
    const def_kind = nodeKindFromC(c.PM_DEF_NODE);

    const statements = test_utils.findChild(&tree.root, statements_kind) orelse return error.MissingStatements;
    const def_node = test_utils.findChild(statements, def_kind) orelse return error.MissingDef;

    try std.testing.expectEqual(@as(usize, 0), def_node.span.start.offset);
    try std.testing.expectEqual(@as(u32, 0), def_node.span.start.line);
    try std.testing.expectEqual(@as(u32, 0), def_node.span.start.column);

    try std.testing.expect(def_node.span.end.offset > 0);
    try std.testing.expectEqual(@as(u32, 2), def_node.span.end.line);
}
