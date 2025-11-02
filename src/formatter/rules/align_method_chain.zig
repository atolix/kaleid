const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

const ChainInfo = struct {
    indent_len: usize,
};

/// Aligns the leading dots of multi-line method chains.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var lines = std.ArrayListUnmanaged([]const u8){};
    defer lines.deinit(allocator);

    var splitter = std.mem.splitScalar(u8, source, '\n');
    while (splitter.next()) |line| {
        try lines.append(allocator, line);
    }

    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var changed = false;
    var first_line = true;

    var i: usize = 0;
    while (i < lines.items.len) {
        const maybe_info = getChainInfo(lines.items[i]);
        if (maybe_info) |_| {
            const start = i;
            var end = i;
            while (end < lines.items.len) {
                if (getChainInfo(lines.items[end])) |_| {
                    end += 1;
                } else {
                    break;
                }
            }

            const chain_len = end - start;
            if (chain_len >= 2) {
                var min_idx = start;
                var min_indent = getChainInfo(lines.items[start]).?.indent_len;
                var idx = start + 1;
                while (idx < end) : (idx += 1) {
                    const info = getChainInfo(lines.items[idx]).?;
                    if (info.indent_len < min_indent) {
                        min_indent = info.indent_len;
                        min_idx = idx;
                    }
                }

                const target_indent = lines.items[min_idx][0..min_indent];

                idx = start;
                while (idx < end) : (idx += 1) {
                    const line = lines.items[idx];
                    const info = getChainInfo(line).?;
                    const current_indent = line[0..info.indent_len];
                    const remainder = line[info.indent_len..];

                    if (!changed and (info.indent_len != min_indent or !std.mem.eql(u8, current_indent, target_indent))) {
                        changed = true;
                    }

                    try appendLineParts(allocator, &builder, &first_line, target_indent, remainder);
                }

                i = end;
                continue;
            }
        }

        try appendRawLine(allocator, &builder, &first_line, lines.items[i]);
        i += 1;
    }

    if (!changed and builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn getChainInfo(line: []const u8) ?ChainInfo {
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        const ch = line[idx];
        if (ch == ' ' or ch == '\t') continue;
        if (ch == '.') return ChainInfo{ .indent_len = idx };
        return null;
    }
    return null;
}

fn appendRawLine(
    allocator: std.mem.Allocator,
    builder: *std.ArrayListUnmanaged(u8),
    first_line: *bool,
    line: []const u8,
) !void {
    if (first_line.*) {
        first_line.* = false;
    } else {
        try builder.append(allocator, '\n');
    }

    try builder.appendSlice(allocator, line);
}

fn appendLineParts(
    allocator: std.mem.Allocator,
    builder: *std.ArrayListUnmanaged(u8),
    first_line: *bool,
    indent: []const u8,
    remainder: []const u8,
) !void {
    if (first_line.*) {
        first_line.* = false;
    } else {
        try builder.append(allocator, '\n');
    }

    try builder.appendSlice(allocator, indent);
    try builder.appendSlice(allocator, remainder);
}

test "aligns multi-line method chain dots" {
    const allocator = std.testing.allocator;
    const input = "record\n      .reload\n    .touch\n";

    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("record\n    .reload\n    .touch\n", result.buffer);
}

test "keeps already aligned method chain untouched" {
    const allocator = std.testing.allocator;
    const input = "record\n    .reload\n    .touch\n";

    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
