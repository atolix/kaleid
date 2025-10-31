const std = @import("std");

pub const Result = struct {
    changed: bool,
    buffer: []u8,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        if (self.changed) allocator.free(self.buffer);
    }
};

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
            if (!isBlank(line)) {
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
    return hasGuardKeyword(trimmed, "if") or hasGuardKeyword(trimmed, "unless");
}

fn hasGuardKeyword(line: []const u8, keyword: []const u8) bool {
    var search_index: usize = 0;
    while (std.mem.indexOfPos(u8, line, search_index, keyword)) |idx| {
        const before = if (idx == 0) null else line[idx - 1];
        const after_index = idx + keyword.len;
        const after = if (after_index < line.len) line[after_index] else null;

        const before_ok = before == null or std.ascii.isWhitespace(before.?);
        const after_ok = after == null or std.ascii.isWhitespace(after.?);

        if (before_ok and after_ok) return true;

        search_index = idx + 1;
    }
    return false;
}

fn isBlank(line: []const u8) bool {
    for (line) |ch| {
        if (!std.ascii.isWhitespace(ch)) return false;
    }
    return true;
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
