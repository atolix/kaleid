const std = @import("std");
const common = @import("common.zig");
const types = @import("types.zig");
const builder = @import("builder.zig");

const c = common.c;
const ParseTree = types.ParseTree;

/// Parses `source` into an owned `ParseTree` whose lifetime is tied to `allocator`.
/// Returns `error.ParseFailed` if Prism reports syntax errors.
pub fn parseRubyAst(allocator: std.mem.Allocator, source: []const u8) !ParseTree {
    var parser: c.pm_parser_t = undefined;
    c.pm_parser_init(&parser, source.ptr, source.len, null);
    defer c.pm_parser_free(&parser);

    const node = c.pm_parse(&parser);
    if (node == null) return error.ParseFailed;
    defer c.pm_node_destroy(&parser, node);

    if (!c.pm_list_empty_p(&parser.error_list)) return error.ParseFailed;

    const root = try builder.buildNode(allocator, &parser, node);
    return ParseTree{
        .allocator = allocator,
        .source = source,
        .root = root,
    };
}
