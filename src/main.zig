const std = @import("std");
const parser = @import("parser.zig");
const finder = @import("finder.zig");

const CLASS_KIND = parser.nodeKindFromC(parser.prism.PM_CLASS_NODE);
const DEF_KIND = parser.nodeKindFromC(parser.prism.PM_DEF_NODE);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var ruby_files = if (args.len > 1) blk: {
        const user_args = args[1..];
        const path_slices: []const []const u8 = user_args;
        break :blk try finder.readFilesFromPaths(gpa, path_slices);
    } else try finder.readFiles(gpa, ".");
    defer ruby_files.deinit();

    if (ruby_files.files.len == 0) {
        std.debug.print("No Ruby files found under current directory.\n", .{});
        return;
    }

    for (ruby_files.files) |ruby_file| {
        var tree = try parser.parseRubyAst(gpa, ruby_file.contents);
        defer tree.deinit();

        var counts = Counts{};
        gatherCounts(&tree.root, &counts);

        std.debug.print(
            "Parse OK: {s} | root={s} | total_nodes={d} | classes={d} | defs={d}\n",
            .{
                ruby_file.path,
                parser.nodeKindName(tree.root.kind),
                counts.total,
                counts.classes,
                counts.defs,
            },
        );

        if (counts.defs > 0) {
            var report = std.ArrayListUnmanaged(DefinitionSummary){};
            defer {
                for (report.items) |summary| {
                    gpa.free(summary.name);
                }
                report.deinit(gpa);
            }
            try collectDefinitions(gpa, &tree.root, &report, ruby_file.contents);
            try printDefinitionReport(report.items);
        }
    }
}

const Counts = struct {
    total: usize = 0,
    classes: usize = 0,
    defs: usize = 0,
};

fn gatherCounts(node: *const parser.AstNode, counts: *Counts) void {
    counts.total += 1;

    const node_kind_value = node.kind;
    if (node_kind_value == CLASS_KIND) {
        counts.classes += 1;
    } else if (node_kind_value == DEF_KIND) {
        counts.defs += 1;
    }

    for (node.children) |child| {
        gatherCounts(&child, counts);
    }
}

const DefinitionSummary = struct {
    name: []u8,
    span: parser.Span,
};

fn collectDefinitions(allocator: std.mem.Allocator, node: *const parser.AstNode, list: *std.ArrayListUnmanaged(DefinitionSummary), source: []const u8) !void {
    if (node.kind == DEF_KIND) {
        const name = extractDefName(node, source) catch "definition";
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

fn extractDefName(node: *const parser.AstNode, source: []const u8) ![]const u8 {
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

fn printDefinitionReport(defs: []const DefinitionSummary) !void {
    if (defs.len == 0) return;

    std.debug.print("  Definitions:\n", .{});
    for (defs) |def| {
        std.debug.print(
            "    {s} @ line {d} column {d}\n",
            .{ def.name, def.span.start.line + 1, def.span.start.column + 1 },
        );
    }
}
