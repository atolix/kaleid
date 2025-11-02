const std = @import("std");
const parser = @import("parser.zig");

pub const Counts = struct {
    total: usize = 0,
    classes: usize = 0,
    defs: usize = 0,
};

pub const DefinitionSummary = struct {
    name: []u8,
    span: parser.Span,
};

pub const FileSummary = struct {
    allocator: std.mem.Allocator,
    counts: Counts,
    definitions: []DefinitionSummary,

    pub fn deinit(self: *FileSummary) void {
        for (self.definitions) |defn| {
            self.allocator.free(defn.name);
        }
        self.allocator.free(self.definitions);
    }
};

/// Generates aggregate stats and collected definitions for the supplied AST.
pub fn summarize(allocator: std.mem.Allocator, tree: *const parser.ParseTree, source: []const u8) !FileSummary {
    var counts = Counts{};
    gatherCounts(&tree.root, &counts);

    var defs = std.ArrayListUnmanaged(DefinitionSummary){};
    errdefer defs.deinit(allocator);

    try collectDefinitions(allocator, &tree.root, &defs, source);

    const items = try defs.toOwnedSlice(allocator);
    return FileSummary{
        .allocator = allocator,
        .counts = counts,
        .definitions = items,
    };
}

pub fn gatherCounts(node: *const parser.AstNode, counts: *Counts) void {
    counts.total += 1;

    const node_kind_value = node.kind;
    if (node_kind_value == parser.nodeKindFromC(parser.prism.PM_CLASS_NODE)) {
        counts.classes += 1;
    } else if (node_kind_value == parser.nodeKindFromC(parser.prism.PM_DEF_NODE)) {
        counts.defs += 1;
    }

    for (node.children) |child| {
        gatherCounts(&child, counts);
    }
}

fn collectDefinitions(allocator: std.mem.Allocator, node: *const parser.AstNode, list: *std.ArrayListUnmanaged(DefinitionSummary), source: []const u8) !void {
    if (node.kind == parser.nodeKindFromC(parser.prism.PM_DEF_NODE)) {
        const name = extractDefHeader(node, source) catch "definition";
        const owned_name = try allocator.dupe(u8, name);
        try list.append(allocator, .{
            .name = owned_name,
            .span = node.span,
        });
    }

    for (node.children) |child| {
        try collectDefinitions(allocator, &child, list, source);
    }
}

fn extractDefHeader(node: *const parser.AstNode, source: []const u8) ![]const u8 {
    const start = node.span.start.offset;
    if (start >= source.len) return error.NoName;

    const remaining = source[start..];
    const rel_end = std.mem.indexOfScalar(u8, remaining, '\n') orelse blk: {
        if (node.span.end.offset > start and node.span.end.offset <= source.len) {
            break :blk node.span.end.offset - start;
        }
        break :blk remaining.len;
    };
    const end = start + @min(rel_end, remaining.len);
    if (end <= start) return error.NoName;

    const header = source[start..end];
    const trimmed = std.mem.trim(u8, header, " \t\r\n");
    if (trimmed.len == 0) return error.NoName;
    return trimmed;
}

pub fn printSummary(summary: *const FileSummary, file_path: []const u8, root_kind: parser.NodeKind) void {
    std.debug.print(
        "Parse OK: {s} | root={s} | total_nodes={d} | classes={d} | defs={d}\n",
        .{
            file_path,
            parser.nodeKindName(root_kind),
            summary.counts.total,
            summary.counts.classes,
            summary.counts.defs,
        },
    );

    // if (summary.definitions.len == 0) return;

    // std.debug.print("  Definitions:\n", .{});
    // for (summary.definitions) |defn| {
    //     std.debug.print(
    //         "    {s} @ line {d} column {d}\n",
    //         .{ defn.name, defn.span.start.line + 1, defn.span.start.column + 1 },
    //     );
    // }
}

test "summarize captures counts and definitions" {
    const allocator = std.testing.allocator;
    const src =
        \\class Foo
        \\  def hello(name)
        \\    puts name
        \\  end
        \\end
        \\
    ;

    var tree = try parser.parseRubyAst(allocator, src);
    defer tree.deinit();

    var summary = try summarize(allocator, &tree, src);
    defer summary.deinit();

    try std.testing.expectEqual(@as(usize, 1), summary.counts.classes);
    try std.testing.expectEqual(@as(usize, 1), summary.counts.defs);
    try std.testing.expect(summary.counts.total > 0);
    try std.testing.expectEqual(@as(usize, 1), summary.definitions.len);
    try std.testing.expect(std.mem.startsWith(u8, summary.definitions[0].name, "def hello"));
}
