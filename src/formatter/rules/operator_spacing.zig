const std = @import("std");

pub const Result = struct {
    changed: bool,
    buffer: []u8,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        if (self.changed) allocator.free(self.buffer);
    }
};

const Operator = struct {
    text: []const u8,
    require_binary_context: bool,
};

const operators = [_]Operator{
    .{ .text = "==", .require_binary_context = true },
    .{ .text = "!=", .require_binary_context = true },
    .{ .text = "<=", .require_binary_context = true },
    .{ .text = ">=", .require_binary_context = true },
    .{ .text = "+=", .require_binary_context = true },
    .{ .text = "-=", .require_binary_context = true },
    .{ .text = "*=", .require_binary_context = true },
    .{ .text = "/=", .require_binary_context = true },
    .{ .text = "%=", .require_binary_context = true },
    .{ .text = "&&", .require_binary_context = true },
    .{ .text = "||", .require_binary_context = true },
    .{ .text = "=", .require_binary_context = true },
    .{ .text = "+", .require_binary_context = true },
    .{ .text = "-", .require_binary_context = true },
    .{ .text = "*", .require_binary_context = true },
    .{ .text = "/", .require_binary_context = true },
    .{ .text = "%", .require_binary_context = true },
};

const StringState = enum { none, single, double };

/// Ensures binary operators are surrounded by single spaces (e.g. `a+b` -> `a + b`).
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

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

        if (in_comment) {
            try builder.append(allocator, ch);
            if (ch == '\n') {
                in_comment = false;
            }
            i += 1;
            continue;
        }

        if (ch == '#') {
            in_comment = true;
            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        if (ch == '\'' or ch == '"') {
            string_state = if (ch == '"') .double else .single;
            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        if (try handleOperator(allocator, source, &builder, &i)) {
            continue;
        }

        try builder.append(allocator, ch);
        i += 1;
    }

    if (builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn handleOperator(
    allocator: std.mem.Allocator,
    source: []const u8,
    builder: *std.ArrayListUnmanaged(u8),
    index: *usize,
) !bool {
    for (operators) |op| {
        if (matchesOperator(source, op.text, index.*)) {
            if (op.require_binary_context and !hasBinaryContext(builder.items, source, index.*, op.text.len)) {
                continue;
            }

            try normalizeSpaceBeforeOperator(allocator, builder);
            try builder.appendSlice(allocator, op.text);

            index.* += op.text.len;

            skipSpaces(source, index);

            if (needsTrailingSpace(source, index.*)) {
                try builder.append(allocator, ' ');
            }

            return true;
        }
    }
    return false;
}

fn matchesOperator(source: []const u8, op: []const u8, index: usize) bool {
    if (index + op.len > source.len) return false;
    return std.mem.eql(u8, source[index .. index + op.len], op);
}

fn hasBinaryContext(builder_items: []u8, source: []const u8, index: usize, op_len: usize) bool {
    const left = findPrevNonWhitespace(builder_items);
    const right = findNextNonWhitespace(source, index + op_len);

    if (left == null or right == null) return false;
    return isBinaryLeftChar(left.?) and isBinaryRightChar(right.?);
}

fn isBinaryLeftChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == ')' or ch == ']' or ch == '"' or ch == '\'' or ch == '`';
}

fn isBinaryRightChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '(' or ch == '[' or ch == '"' or ch == '\'' or ch == '`';
}

fn findPrevNonWhitespace(buffer: []u8) ?u8 {
    if (buffer.len == 0) return null;
    var idx: usize = buffer.len;
    while (idx > 0) {
        idx -= 1;
        const ch = buffer[idx];
        if (ch != ' ' and ch != '\t') {
            return ch;
        }
    }
    return null;
}

fn findNextNonWhitespace(source: []const u8, start: usize) ?u8 {
    var idx = start;
    while (idx < source.len) {
        const ch = source[idx];
        if (ch != ' ' and ch != '\t') {
            return ch;
        }
        idx += 1;
    }
    return null;
}

fn skipSpaces(source: []const u8, index: *usize) void {
    while (index.* < source.len) : (index.* += 1) {
        const ch = source[index.*];
        if (ch != ' ' and ch != '\t') break;
    }
}

fn needsTrailingSpace(source: []const u8, index: usize) bool {
    if (index >= source.len) return false;
    const ch = source[index];
    return ch != ' ' and ch != '\n' and ch != '\t' and ch != '\r';
}

fn normalizeSpaceBeforeOperator(allocator: std.mem.Allocator, builder: *std.ArrayListUnmanaged(u8)) !void {
    const left_char = findPrevNonWhitespace(builder.items);
    if (left_char == null) return;
    if (left_char.? == '\n') return;

    const trailing = countTrailingSpaces(builder.items);
    if (trailing > 0) {
        builder.shrinkRetainingCapacity(builder.items.len - trailing);
    }

    try builder.append(allocator, ' ');
}

fn countTrailingSpaces(buffer: []const u8) usize {
    var count: usize = 0;
    var idx = buffer.len;
    while (idx > 0) {
        const ch = buffer[idx - 1];
        if (ch == ' ' or ch == '\t') {
            idx -= 1;
            count += 1;
            continue;
        }
        break;
    }
    return count;
}

test "operator spacing inserts spaces around equals and arithmetic" {
    const allocator = std.testing.allocator;
    const input = "x=5-2";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("x = 5 - 2", result.buffer);
}

test "operator spacing leaves already spaced operators untouched" {
    const allocator = std.testing.allocator;
    const input = "result = left + right";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "operator spacing ignores unary minus" {
    const allocator = std.testing.allocator;
    const input = "value = -5";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "operator spacing handles compound operators" {
    const allocator = std.testing.allocator;
    const input = "sum+=value";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("sum += value", result.buffer);
}
