const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

const default_indent_spaces: usize = 4;

// Example transform:
// record
//       .reload
//     .touch
//
// =>
// record
//     .reload
//     .touch
//
// response.body
//     .strip
//     .split("\n")
//
// =>
// response.body
//         .strip
//         .split("\n")
//
const ChainInfo = struct {
    indent_len: usize,
};

const TargetIndent = struct {
    slice: []const u8,
    needs_free: bool,
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
                const target = try computeTargetIndent(allocator, lines.items, start, end);
                defer if (target.needs_free) allocator.free(target.slice);

                var idx = start;
                while (idx < end) : (idx += 1) {
                    const line = lines.items[idx];
                    const info = getChainInfo(line).?;
                    const current_indent = line[0..info.indent_len];
                    const remainder = line[info.indent_len..];

                    if (!changed and !std.mem.eql(u8, current_indent, target.slice)) {
                        changed = true;
                    }

                    try appendLineParts(allocator, &builder, &first_line, target.slice, remainder);
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

fn computeTargetIndent(
    allocator: std.mem.Allocator,
    lines: []const []const u8,
    start: usize,
    end: usize,
) !TargetIndent {
    if (start > 0) {
        const prev_line = lines[start - 1];
        const prev_indent_len = countLeadingWhitespace(prev_line);

        if (prev_indent_len < prev_line.len) {
            if (std.mem.indexOfScalar(u8, prev_line[prev_indent_len..], '.')) |dot_relative| {
                const additional_spaces = if (dot_relative == 0) default_indent_spaces else dot_relative;
                const buffer = try buildIndentSlice(allocator, prev_line[0..prev_indent_len], additional_spaces);
                return TargetIndent{ .slice = buffer, .needs_free = true };
            } else {
                const indent_step = determineIndentStep(lines, start, end, prev_indent_len);
                const buffer = try buildIndentSlice(allocator, prev_line[0..prev_indent_len], indent_step);
                return TargetIndent{ .slice = buffer, .needs_free = true };
            }
        }
    }

    var min_idx = start;
    var min_indent = getChainInfo(lines[start]).?.indent_len;
    var idx = start + 1;
    while (idx < end) : (idx += 1) {
        const info = getChainInfo(lines[idx]).?;
        if (info.indent_len < min_indent) {
            min_indent = info.indent_len;
            min_idx = idx;
        }
    }

    return TargetIndent{ .slice = lines[min_idx][0..min_indent], .needs_free = false };
}

fn countLeadingWhitespace(line: []const u8) usize {
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        const ch = line[idx];
        if (ch == ' ' or ch == '\t') {
            continue;
        }
        break;
    }
    return idx;
}

fn buildIndentSlice(
    allocator: std.mem.Allocator,
    base_indent: []const u8,
    additional_spaces: usize,
) ![]u8 {
    const total = base_indent.len + additional_spaces;
    var buffer = try allocator.alloc(u8, total);
    if (base_indent.len > 0) std.mem.copyForwards(u8, buffer[0..base_indent.len], base_indent);
    var idx: usize = base_indent.len;
    while (idx < total) : (idx += 1) {
        buffer[idx] = ' ';
    }
    return buffer;
}

fn determineIndentStep(
    lines: []const []const u8,
    start: usize,
    end: usize,
    base_indent_len: usize,
) usize {
    var step: ?usize = null;
    var idx = start;
    while (idx < end) : (idx += 1) {
        const info = getChainInfo(lines[idx]).?;
        if (info.indent_len > base_indent_len) {
            const diff = info.indent_len - base_indent_len;
            if (step == null or diff < step.?) {
                step = diff;
            }
        }
    }
    return step orelse default_indent_spaces;
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

test "aligns to first inline method invocation column" {
    const allocator = std.testing.allocator;
    const input = "response.body\n    .strip\n    .split(\"\\n\")\n";

    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("response.body\n        .strip\n        .split(\"\\n\")\n", result.buffer);
}

test "indents chain when first method starts on new line" {
    const allocator = std.testing.allocator;
    const input = "response\n.body\n        .strip\n    .split(\"\\n\")\n";

    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("response\n    .body\n    .strip\n    .split(\"\\n\")\n", result.buffer);
}

test "derives indent step from existing chain indentation" {
    const allocator = std.testing.allocator;
    const input = "value\n  .map\n    .compact\n";

    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("value\n  .map\n  .compact\n", result.buffer);
}
