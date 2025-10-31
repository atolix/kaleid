const std = @import("std");
const parser = @import("parser.zig");

pub fn main() !void {
    const src = "def hi; puts 'hello'; end";

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const pretty = try parser.parseRubyAst(gpa, src);
    defer gpa.free(pretty);

    std.debug.print("Parse OK!\n", .{});
    std.debug.print("{s}\n", .{pretty});
}
