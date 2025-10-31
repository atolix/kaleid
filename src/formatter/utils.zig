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
