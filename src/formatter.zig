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
