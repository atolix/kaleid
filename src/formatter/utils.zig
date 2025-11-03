const std = @import("std");

/// Returns true if the entire slice consists only of ASCII whitespace characters.
pub fn isBlankLine(line: []const u8) bool {
    for (line) |ch| {
        if (!std.ascii.isWhitespace(ch)) return false;
    }
    return true;
}

/// Checks whether `keyword` appears in `line` as a standalone word (surrounded by whitespace or edges).
pub fn containsKeywordAsWord(line: []const u8, keyword: []const u8) bool {
    if (keyword.len == 0 or line.len < keyword.len) return false;

    var search_index: usize = 0;
    while (std.mem.indexOfPos(u8, line, search_index, keyword)) |idx| {
        const before = if (idx == 0) null else line[idx - 1];
        const after_index = idx + keyword.len;
        const after = if (after_index < line.len) line[after_index] else null;

        const before_ok = before == null or std.ascii.isWhitespace(before.?);
        const after_ok = after == null or std.ascii.isWhitespace(after.?);

        if (before_ok and after_ok) return true;

        search_index = idx + 1;
    }

    return false;
}

/// Returns the last non-space character in `buffer`, ignoring trailing spaces and tabs.
pub fn findPrevNonWhitespace(buffer: []const u8) ?u8 {
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

/// Counts trailing spaces and tabs at the end of `buffer`.
pub fn countTrailingSpaces(buffer: []const u8) usize {
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

/// Advances `index` while the current character in `source` is space or tab.
pub fn skipSpaces(source: []const u8, index: *usize) void {
    while (index.* < source.len) : (index.* += 1) {
        const ch = source[index.*];
        if (ch != ' ' and ch != '\t') break;
    }
}

test "isBlankLine returns true for whitespace" {
    try std.testing.expect(isBlankLine("   \t"));
}

test "isBlankLine returns false when content present" {
    try std.testing.expect(!isBlankLine("foo"));
}

test "containsKeywordAsWord matches surrounded keyword" {
    try std.testing.expect(containsKeywordAsWord("return if foo", "if"));
}

test "containsKeywordAsWord ignores suffix" {
    try std.testing.expect(!containsKeywordAsWord("return suffix", "if"));
}

test "findPrevNonWhitespace finds character" {
    try std.testing.expectEqual(@as(?u8, 'b'), findPrevNonWhitespace("ab  "));
}

test "countTrailingSpaces counts spaces" {
    try std.testing.expectEqual(@as(usize, 3), countTrailingSpaces("foo   "));
}

test "skipSpaces advances past spaces and tabs" {
    const source = "foo  \tbar";
    var index: usize = 3;
    skipSpaces(source, &index);
    try std.testing.expectEqual(@as(usize, 6), index);
}
