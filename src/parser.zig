const std = @import("std");

const c = @cImport({
    @cInclude("prism.h");
});

pub const prism = c;

pub const NodeKind = c.pm_node_type;

pub const Position = struct {
    /// Byte offset from the beginning of the source.
    offset: usize,
    /// Zero-based line number.
    line: u32,
    /// Zero-based column number.
    column: u32,
};

pub const Span = struct {
    start: Position,
    end: Position,
};

pub const AstNode = struct {
    kind: prism.pm_node_type_t,
    flags: u32,
    span: Span,
    children: []AstNode,

    pub fn deinit(self: *AstNode, allocator: std.mem.Allocator) void {
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

pub const ParseTree = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    root: AstNode,

    pub fn deinit(self: *ParseTree) void {
        self.root.deinit(self.allocator);
    }
};

pub fn nodeKindName(kind: prism.pm_node_type_t) []const u8 {
    return std.mem.span(c.pm_node_type_to_str(kind));
}

pub fn nodeKindFromC(value: anytype) prism.pm_node_type_t {
    return @as(prism.pm_node_type_t, @intCast(value));
}

pub fn parseRubyAst(allocator: std.mem.Allocator, source: []const u8) !ParseTree {
    var parser: c.pm_parser_t = undefined;
    c.pm_parser_init(&parser, source.ptr, source.len, null);
    defer c.pm_parser_free(&parser);

    const node = c.pm_parse(&parser);
    if (node == null) return error.ParseFailed;
    defer c.pm_node_destroy(&parser, node);

    if (!c.pm_list_empty_p(&parser.error_list)) return error.ParseFailed;

    const root = try buildNode(allocator, &parser, node);
    return ParseTree{
        .allocator = allocator,
        .source = source,
        .root = root,
    };
}

fn buildNode(allocator: std.mem.Allocator, parser: *const c.pm_parser_t, node: *const c.pm_node_t) !AstNode {
    var children_list = std.ArrayListUnmanaged(AstNode){};
    errdefer {
        for (children_list.items) |*child| {
            child.deinit(allocator);
        }
        children_list.deinit(allocator);
    }

    var context = BuildContext{
        .allocator = allocator,
        .parser = parser,
        .list = &children_list,
    };

    const raw_context: *anyopaque = @ptrCast(&context);
    c.pm_visit_child_nodes(node, collectChildCallback, raw_context);
    if (context.err) |err| return err;

    const children = try children_list.toOwnedSlice(allocator);

    const span = makeSpan(parser, node);

    return AstNode{
        .kind = node.*.type,
        .flags = @as(u32, @intCast(node.*.flags)),
        .span = span,
        .children = children,
    };
}

const BuildContext = struct {
    allocator: std.mem.Allocator,
    parser: *const c.pm_parser_t,
    list: *std.ArrayListUnmanaged(AstNode),
    err: ?anyerror = null,
};

const ChildPtr = ?*const c.pm_node_t;

fn collectChildCallback(child_ptr: ChildPtr, context_ptr: ?*anyopaque) callconv(.c) bool {
    if (child_ptr == null or context_ptr == null) return false;

    const context: *BuildContext = @ptrCast(@alignCast(context_ptr.?));
    if (context.err != null) return false;

    const child = child_ptr.?;
    const result = buildNode(context.allocator, context.parser, child) catch |err| {
        context.err = err;
        return false;
    };

    context.list.append(context.allocator, result) catch |err| {
        context.err = err;
        // result owns children; clean them up immediately.
        var temp = result;
        temp.deinit(context.allocator);
        return false;
    };

    // We already recursed by calling buildNode, so stop traversal here.
    return false;
}

fn makeSpan(parser: *const c.pm_parser_t, node: *const c.pm_node_t) Span {
    return Span{
        .start = makePosition(parser, node.*.location.start),
        .end = makePosition(parser, node.*.location.end),
    };
}

fn makePosition(parser: *const c.pm_parser_t, ptr_opt: ?*const u8) Position {
    if (ptr_opt == null) {
        return Position{ .offset = 0, .line = 0, .column = 0 };
    }

    const ptr = ptr_opt.?;
    std.debug.assert(@intFromPtr(ptr) >= @intFromPtr(parser.start));
    const offset = @intFromPtr(ptr) - @intFromPtr(parser.start);

    const line_column = c.pm_newline_list_line_column(&parser.newline_list, ptr, 0);
    const line_value = if (line_column.line < 0) 0 else @as(u32, @intCast(line_column.line));

    return Position{
        .offset = offset,
        .line = line_value,
        .column = @as(u32, line_column.column),
    };
}

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

    const program_kind = nodeKindFromC(c.PM_PROGRAM_NODE);
    const statements_kind = nodeKindFromC(c.PM_STATEMENTS_NODE);
    const class_kind = nodeKindFromC(c.PM_CLASS_NODE);
    const def_kind = nodeKindFromC(c.PM_DEF_NODE);
    const call_kind = nodeKindFromC(c.PM_CALL_NODE);
    const interpolated_kind = nodeKindFromC(c.PM_INTERPOLATED_STRING_NODE);

    try std.testing.expectEqual(program_kind, tree.root.kind);

    const statements = findChild(&tree.root, statements_kind) orelse return error.MissingStatements;
    const class_node = findChild(statements, class_kind) orelse return error.MissingClass;
    const class_body = findChild(class_node, statements_kind) orelse return error.MissingClassBody;
    const def_node = findChild(class_body, def_kind) orelse return error.MissingDef;
    const def_body = findChild(def_node, statements_kind) orelse return error.MissingDefBody;
    const call_node = findChild(def_body, call_kind) orelse return error.MissingCall;

    try std.testing.expect(hasNode(call_node, interpolated_kind));
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

    const statements_kind = nodeKindFromC(c.PM_STATEMENTS_NODE);
    const def_kind = nodeKindFromC(c.PM_DEF_NODE);

    const statements = findChild(&tree.root, statements_kind) orelse return error.MissingStatements;
    const def_node = findChild(statements, def_kind) orelse return error.MissingDef;

    try std.testing.expectEqual(@as(usize, 0), def_node.span.start.offset);
    try std.testing.expectEqual(@as(u32, 0), def_node.span.start.line);
    try std.testing.expectEqual(@as(u32, 0), def_node.span.start.column);

    try std.testing.expect(def_node.span.end.offset > 0);
    try std.testing.expectEqual(@as(u32, 2), def_node.span.end.line);
}

fn findChild(node: *const AstNode, kind: prism.pm_node_type_t) ?*const AstNode {
    for (node.children, 0..) |child, index| {
        if (child.kind == kind) {
            return &node.children[index];
        }
    }
    return null;
}

fn hasNode(node: *const AstNode, kind: prism.pm_node_type_t) bool {
    if (node.kind == kind) return true;
    for (node.children) |child| {
        if (hasNode(&child, kind)) return true;
    }
    return false;
}
