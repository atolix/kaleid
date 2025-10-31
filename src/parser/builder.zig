const std = @import("std");
const common = @import("common.zig");
const types = @import("types.zig");

const c = common.c;
const prism = common.prism;
const AstNode = types.AstNode;
const Span = types.Span;
const Position = types.Position;

pub fn buildNode(allocator: std.mem.Allocator, parser: *const c.pm_parser_t, node: *const c.pm_node_t) !AstNode {
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

/// Bridges Prism's child traversal into Zig, building children and recording failures.
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
        var temp = result;
        temp.deinit(context.allocator);
        return false;
    };

    // We already recursed by calling buildNode, so stop traversal here.
    return false;
}

/// Derives byte/line span information for a Prism node.
fn makeSpan(parser: *const c.pm_parser_t, node: *const c.pm_node_t) Span {
    return Span{
        .start = makePosition(parser, node.*.location.start),
        .end = makePosition(parser, node.*.location.end),
    };
}

/// Converts a Prism pointer into byte offset and line/column coordinates.
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
