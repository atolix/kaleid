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

pub const ParseTree = struct {
    /// Owns a complete AST for a single Ruby source file.
    /// Layout overview (ASCII):
    ///   ParseTree
    ///     |- allocator : std.mem.Allocator
    ///     |- source    : []const u8
    ///     \- root ----> AstNode (kind/flags/span/children...)
    /// The tree keeps the allocator used to build every AstNode so that
    /// `deinit` can walk the subtree and free all associated allocations.
    allocator: std.mem.Allocator,
    source: []const u8,
    root: AstNode,

    pub fn deinit(self: *ParseTree) void {
        // Cleans up the entire AST by recursively deinitializing the root node.
        self.root.deinit(self.allocator);
    }
};

pub const AstNode = struct {
    /// Prism node converted into Zig, carrying its kind, flags, span, and children.
    ///
    /// Node metadata mirrored from Prism:
    /// - `kind` stores the pm_node_type_t value describing the node type.
    /// - `flags` carries Prism-specific bit flags for extra attributes.
    /// - `span` records the byte/line range covered by this node.
    /// - `children` owns the recursive subtree.
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



/// Returns the Prism node type name corresponding to the numeric `kind`.
pub fn nodeKindName(kind: NodeKind) []const u8 {
    return std.mem.span(c.pm_node_type_to_str(kind));
}

/// Casts a Prism C enum value into the Zig alias used throughout the parser module.
pub fn nodeKindFromC(value: anytype) NodeKind {
    return @as(NodeKind, @intCast(value));
}
