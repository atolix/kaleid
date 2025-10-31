const std = @import("std");
const parser = @import("parser.zig");
const file_finder = @import("file_finder.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var ruby_files = try file_finder.readRubyFiles(gpa, ".");
    defer ruby_files.deinit();

    if (ruby_files.files.len == 0) {
        std.debug.print("No Ruby files found under current directory.\n", .{});
        return;
    }

    for (ruby_files.files) |ruby_file| {
        const pretty = try parser.parseRubyAst(gpa, ruby_file.contents);
        defer gpa.free(pretty);

        std.debug.print("Parse OK: {s}\n", .{ruby_file.path});
        // std.debug.print("{s}\n", .{pretty});
    }
}
