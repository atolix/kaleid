const std = @import("std");
const parser = @import("parser.zig");
const finder = @import("finder.zig");
const output = @import("output.zig");
const formatter = @import("formatter.zig");

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

        var summary = try output.summarize(gpa, &tree, ruby_file.contents);
        defer summary.deinit();

        output.printSummary(&summary, ruby_file.path, tree.root.kind);

        var format_result = try formatter.applyRules(gpa, ruby_file.contents);
        defer format_result.deinit(gpa);

        if (format_result.changed) {
            std.debug.print("  (formatted guard clauses)\n", .{});
            std.debug.print("{s}\n", .{format_result.buffer});
        }
    }
}
