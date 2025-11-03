const std = @import("std");
const rule_types = @import("../rule.zig");
const utils = @import("../utils.zig");

pub const Result = rule_types.RuleResult;

const StringState = enum { none, single, double };
const BraceKind = enum { literal, block };

// Example transform:
// values.each{|value| value.strip}
//
// =>
// values.each { |value| value.strip }
//
/// Ensures Ruby blocks using `{ ... }` have spaces before and inside the braces.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var brace_stack = std.ArrayListUnmanaged(BraceKind){};
    errdefer brace_stack.deinit(allocator);

    var i: usize = 0;
    var string_state = StringState.none;
    var escape_in_string = false;
    var in_comment = false;

    while (i < source.len) {
        const ch = source[i];

        if (string_state != .none) {
            try builder.append(allocator, ch);

            if (escape_in_string) {
                escape_in_string = false;
            } else if (ch == '\\') {
                escape_in_string = true;
            } else if ((string_state == .single and ch == '\'') or (string_state == .double and ch == '"')) {
                string_state = .none;
            }

            i += 1;
            continue;
        }

        if (try utils.handleComment(allocator, source, &builder, &i, &in_comment)) {
            continue;
        }

        if (ch == '\'' or ch == '"') {
            string_state = if (ch == '"') .double else .single;
            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        if (try handleOpenBrace(allocator, source, &builder, &brace_stack, &i)) {
            continue;
        }

        if (ch == '}') {
            const kind = popBrace(&brace_stack);
            if (kind == .block) {
                try normalizeSpaceBeforeClosing(allocator, &builder);
            }

            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        try builder.append(allocator, ch);
        i += 1;
    }

    if (builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        brace_stack.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    const buffer = try builder.toOwnedSlice(allocator);
    brace_stack.deinit(allocator);
    return Result{ .changed = true, .buffer = buffer };
}

fn handleOpenBrace(
    allocator: std.mem.Allocator,
    source: []const u8,
    builder: *std.ArrayListUnmanaged(u8),
    brace_stack: *std.ArrayListUnmanaged(BraceKind),
    index: *usize,
) !bool {
    if (source[index.*] != '{') return false;

    const kind = classifyBrace(builder.items);
    if (kind == .block) {
        try ensureSpaceBeforeBrace(allocator, builder);
    }

    try builder.append(allocator, '{');
    index.* += 1;

    if (kind == .block) {
        utils.skipSpaces(source, index);

        if (index.* < source.len) {
            const next = source[index.*];
            if (next == '}') {
                try builder.append(allocator, ' ');
            } else if (next != '\n') {
                try builder.append(allocator, ' ');
            }
        }
    }

    try brace_stack.append(allocator, kind);
    return true;
}

fn classifyBrace(builder_items: []u8) BraceKind {
    const prev_char = utils.findPrevNonWhitespace(builder_items) orelse return .literal;
    return switch (prev_char) {
        '\n', '{', '[', '(', '=', ':', ',', ';' => .literal,
        else => blk: {
            if (std.ascii.isAlphanumeric(prev_char) or prev_char == '_' or prev_char == ')' or prev_char == ']' or prev_char == '?' or prev_char == '!' or prev_char == '\'' or prev_char == '"') {
                break :blk .block;
            }
            break :blk .literal;
        },
    };
}

fn ensureSpaceBeforeBrace(allocator: std.mem.Allocator, builder: *std.ArrayListUnmanaged(u8)) !void {
    const trailing = utils.countTrailingSpaces(builder.items);
    const prefix_len = builder.items.len - trailing;
    if (prefix_len == 0) return;

    const prev_char = builder.items[prefix_len - 1];
    if (prev_char == '\n') {
        if (trailing > 0) {
            builder.shrinkRetainingCapacity(builder.items.len - trailing);
        }
        return;
    }

    if (trailing == 0) {
        try builder.append(allocator, ' ');
    } else if (trailing > 1) {
        builder.shrinkRetainingCapacity(builder.items.len - (trailing - 1));
    }
}

fn normalizeSpaceBeforeClosing(allocator: std.mem.Allocator, builder: *std.ArrayListUnmanaged(u8)) !void {
    const trailing = utils.countTrailingSpaces(builder.items);
    if (trailing > 1) {
        builder.shrinkRetainingCapacity(builder.items.len - (trailing - 1));
    }

    if (builder.items.len == 0) return;

    const last_char = builder.items[builder.items.len - 1];
    if (last_char == '\n' or last_char == '{') return;

    if (trailing == 0) {
        try builder.append(allocator, ' ');
    }
}

fn popBrace(brace_stack: *std.ArrayListUnmanaged(BraceKind)) BraceKind {
    if (brace_stack.items.len == 0) return .literal;
    const value = brace_stack.items[brace_stack.items.len - 1];
    brace_stack.shrinkRetainingCapacity(brace_stack.items.len - 1);
    return value;
}

test "block brace spacing adds spaces for proc" {
    const allocator = std.testing.allocator;
    const input = "handler = proc{foo}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("handler = proc { foo }\n", result.buffer);
}

test "block brace spacing adds spaces for method block" {
    const allocator = std.testing.allocator;
    const input = "values.each{|value| value.strip}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("values.each { |value| value.strip }\n", result.buffer);
}

test "block brace spacing keeps existing spaces" {
    const allocator = std.testing.allocator;
    const input = "handler = proc { foo }\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "block brace spacing handles empty block" {
    const allocator = std.testing.allocator;
    const input = "formatter = proc{}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("formatter = proc { }\n", result.buffer);
}

test "block brace spacing does not change hash literal" {
    const allocator = std.testing.allocator;
    const input = "config = {foo: :bar}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "block brace spacing ignores braces on new line" {
    const allocator = std.testing.allocator;
    const input = "formatter = proc\n{\n  value\n}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "block brace spacing inserts space before brace even when body on new line" {
    const allocator = std.testing.allocator;
    const input = "formatter = proc{\n  value\n}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("formatter = proc {\n  value\n}\n", result.buffer);
}
