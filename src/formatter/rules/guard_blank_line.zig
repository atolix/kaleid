const std = @import("std");
const utils = @import("../utils.zig");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

/// Ensures guard clauses like `return if condition` are followed by a blank line.
/// Returns either the original buffer or a newly allocated formatted copy.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var pending_guard = false;
    var line_index: usize = 0;
    var changed = false;

    while (lines.next()) |line| : (line_index += 1) {
        if (pending_guard) {
            if (!utils.isBlankLine(line)) {
                try builder.append(allocator, '\n');
                changed = true;
            }
            pending_guard = false;
        }

        if (line_index != 0) try builder.append(allocator, '\n');
        try builder.appendSlice(allocator, line);

        if (isGuardReturn(line)) {
            pending_guard = true;
        }
    }

    if (pending_guard) {
        try builder.append(allocator, '\n');
        changed = true;
    }

    if (!changed and builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = changed or !std.mem.eql(u8, builder.items, source), .buffer = try builder.toOwnedSlice(allocator) };
}

fn isGuardReturn(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "return")) return false;
    return utils.containsKeywordAsWord(trimmed, "if") or utils.containsKeywordAsWord(trimmed, "unless");
}

test "guard blank line inserts blank line after guard" {
    const allocator = std.testing.allocator;
    const input = "return if foo\nputs 'bar'";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("return if foo\n\nputs 'bar'", result.buffer);
}

test "guard blank line supports unless" {
    const allocator = std.testing.allocator;
    const input = "return unless foo\nputs 'bar'";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("return unless foo\n\nputs 'bar'", result.buffer);
}

test "guard blank line leaves existing blank line" {
    const allocator = std.testing.allocator;
    const input = "return if foo\n\nputs 'bar'";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "guard blank line handles trailing guard" {
    const allocator = std.testing.allocator;
    const input = "return if foo";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("return if foo\n", result.buffer);
}
