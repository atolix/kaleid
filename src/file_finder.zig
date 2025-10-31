const std = @import("std");

const PathList = std.ArrayListUnmanaged([]u8);
const RubyFileList = std.ArrayListUnmanaged(RubyFile);

const ignored_directories = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-out",
    "vendor",
    "prism",
};

pub const FileList = struct {
    allocator: std.mem.Allocator,
    items: [][]u8,

    pub fn deinit(self: *FileList) void {
        for (self.items) |item| {
            self.allocator.free(item);
        }
        self.allocator.free(self.items);
    }
};

pub const RubyFile = struct {
    path: []u8,
    contents: []u8,
};

pub const RubyFileCollection = struct {
    allocator: std.mem.Allocator,
    files: []RubyFile,

    pub fn deinit(self: *RubyFileCollection) void {
        for (self.files) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.contents);
        }
        self.allocator.free(self.files);
    }
};

pub fn findRubyFiles(allocator: std.mem.Allocator, root_path: []const u8) !FileList {
    const absolute_root = if (std.fs.path.isAbsolute(root_path))
        try allocator.dupe(u8, root_path)
    else
        try std.fs.cwd().realpathAlloc(allocator, root_path);
    defer allocator.free(absolute_root);

    var results = PathList{};
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit(allocator);
    }

    try collectRubyFiles(allocator, absolute_root, &results);

    const items = try results.toOwnedSlice(allocator);
    return FileList{
        .allocator = allocator,
        .items = items,
    };
}

pub fn readRubyFiles(allocator: std.mem.Allocator, root_path: []const u8) !RubyFileCollection {
    var paths = try findRubyFiles(allocator, root_path);
    defer paths.deinit();

    var results = RubyFileList{};
    errdefer {
        for (results.items) |file| {
            allocator.free(file.path);
            allocator.free(file.contents);
        }
        results.deinit(allocator);
    }

    for (paths.items) |path| {
        {
            const entry = try loadRubyFile(allocator, path);
            errdefer {
                allocator.free(entry.path);
                allocator.free(entry.contents);
            }
            try results.append(allocator, entry);
        }
    }

    const files = try results.toOwnedSlice(allocator);
    return RubyFileCollection{
        .allocator = allocator,
        .files = files,
    };
}

fn collectRubyFiles(allocator: std.mem.Allocator, dir_path: []const u8, results: *PathList) !void {
    var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                if (shouldSkipDir(entry.name)) {
                    continue;
                }

                const child_dir_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
                defer allocator.free(child_dir_path);
                try collectRubyFiles(allocator, child_dir_path, results);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".rb")) {
                    continue;
                }

                const file_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
                errdefer allocator.free(file_path);
                try results.append(allocator, file_path);
            },
            else => {},
        }
    }
}

fn loadRubyFile(allocator: std.mem.Allocator, path: []const u8) !RubyFile {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    errdefer allocator.free(contents);

    return RubyFile{
        .path = owned_path,
        .contents = contents,
    };
}

fn shouldSkipDir(name: []const u8) bool {
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
        return true;
    }

    for (ignored_directories) |ignored| {
        if (std.mem.eql(u8, name, ignored)) {
            return true;
        }
    }

    // Skip hidden directories starting with '.'.
    if (name.len > 0 and name[0] == '.') {
        return true;
    }

    return false;
}

test "findRubyFiles collects rb files recursively" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "main.rb", .data = "puts 'main'\n" });
    try tmp_dir.dir.makePath("sub");
    try tmp_dir.dir.writeFile(.{ .sub_path = "sub/other.rb", .data = "puts 'sub'\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "sub/ignored.txt", .data = "skip\n" });
    try tmp_dir.dir.makePath("vendor");
    try tmp_dir.dir.writeFile(.{ .sub_path = "vendor/skip.rb", .data = "puts 'skip'\n" });

    const root_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var list = try findRubyFiles(allocator, root_path);
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 2), list.items.len);

    const expected = [_][]const u8{
        "main.rb",
        "sub/other.rb",
    };

    for (expected) |value| {
        var found = false;
        for (list.items) |item| {
            if (std.mem.endsWith(u8, item, value)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "readRubyFiles loads file contents alongside absolute paths" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "first.rb", .data = "puts 'first'\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "skip.txt", .data = "ignore\n" });
    try tmp_dir.dir.makePath("nested");
    try tmp_dir.dir.writeFile(.{ .sub_path = "nested/second.rb", .data = "puts 'second'\n" });
    try tmp_dir.dir.makePath("vendor");
    try tmp_dir.dir.writeFile(.{ .sub_path = "vendor/ignored.rb", .data = "puts 'ignored'\n" });

    const root_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);

    var collection = try readRubyFiles(allocator, root_path);
    defer collection.deinit();

    try std.testing.expectEqual(@as(usize, 2), collection.files.len);

    var saw_first = false;
    var saw_second = false;
    for (collection.files) |file| {
        if (std.mem.endsWith(u8, file.path, "first.rb")) {
            saw_first = true;
            try std.testing.expectEqualStrings("puts 'first'\n", file.contents);
        } else if (std.mem.endsWith(u8, file.path, "nested/second.rb")) {
            saw_second = true;
            try std.testing.expectEqualStrings("puts 'second'\n", file.contents);
        }
    }

    try std.testing.expect(saw_first);
    try std.testing.expect(saw_second);
}
