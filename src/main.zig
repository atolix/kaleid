const std = @import("std");
const kaleid = @import("kaleid");

const c = @cImport({
    @cInclude("prism.h");
});

pub fn main() !void {
    const src = "def hi; puts 'hello'; end";

    var parser: c.pm_parser_t = undefined;
    c.pm_parser_init(&parser, src, src.len, null);

    const node = c.pm_parse(&parser);
    if (node != null) {
        std.debug.print("Parse OK!\n", .{});

        var buffer: c.pm_buffer_t = undefined;
        _ = c.pm_buffer_init(&buffer);

        c.pm_prettyprint(&buffer, &parser, node);

        const output = c.pm_buffer_value(&buffer);
        std.debug.print("{s}\n", .{output});

        c.pm_buffer_free(&buffer);
    } else {
        std.debug.print("Parse failed.\n", .{});
    }

    c.pm_parser_free(&parser);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
