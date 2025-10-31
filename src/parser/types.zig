const std = @import("std");
const common = @import("common.zig");
const c = common.c;
const prism = common.prism;

pub const NodeKind = prism.pm_node_type_t;

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
    kind: NodeKind,
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

/// Returns the Prism node type name corresponding to the numeric `kind`.
pub fn nodeKindName(kind: NodeKind) []const u8 {
    return std.mem.span(c.pm_node_type_to_str(kind));
}

/// Casts a Prism C enum value into the Zig alias used throughout the parser module.
pub fn nodeKindFromC(value: anytype) NodeKind {
    return @as(NodeKind, @intCast(value));
}
