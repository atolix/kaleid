const std = @import("std");

pub const RuleResult = struct {
    changed: bool,
    buffer: []u8,

    pub fn deinit(self: *RuleResult, allocator: std.mem.Allocator) void {
        if (self.changed) allocator.free(self.buffer);
    }
};

pub const Rule = struct {
    apply: *const fn (std.mem.Allocator, []const u8) anyerror!RuleResult,
};
