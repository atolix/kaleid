const std = @import("std");
const guard_blank_line = @import("formatter/rules/guard_blank_line.zig");

pub const FormatResult = struct {
    changed: bool,
    buffer: []u8,

    pub fn deinit(self: *FormatResult, allocator: std.mem.Allocator) void {
        if (self.changed) allocator.free(self.buffer);
    }
};

/// Applies all formatting rules to the provided source.
pub fn applyRules(allocator: std.mem.Allocator, source: []const u8) !FormatResult {
    var current = FormatResult{ .changed = false, .buffer = @constCast(source) };

    var guard = try guard_blank_line.apply(allocator, current.buffer);
    if (guard.changed) {
        if (current.changed) allocator.free(current.buffer);
        current = FormatResult{ .changed = true, .buffer = guard.buffer };
    }

    if (!guard.changed) guard.deinit(allocator);

    return current;
}

/// Applies formatting rules and, when changes are detected, updates the file on disk.
/// Returns `true` if the file was modified.
pub fn applyRulesToFile(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8) !bool {
    var result = try applyRules(allocator, source);
    defer result.deinit(allocator);

    if (!result.changed) return false;

    var file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(result.buffer);
    return true;
}

test "applyRulesToFile writes updates into the file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "guard.rb", .data = "return if foo\nputs 'bar'\n" });

    const file_path = try tmp_dir.dir.realpathAlloc(allocator, "guard.rb");
    defer allocator.free(file_path);

    const original = try tmp_dir.dir.readFileAlloc(allocator, "guard.rb", std.math.maxInt(usize));
    defer allocator.free(original);

    const changed = try applyRulesToFile(allocator, file_path, original);
    try std.testing.expect(changed);

    const updated = try tmp_dir.dir.readFileAlloc(allocator, "guard.rb", std.math.maxInt(usize));
    defer allocator.free(updated);

    try std.testing.expectEqualStrings("return if foo\n\nputs 'bar'\n", updated);
}
