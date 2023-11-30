const std = @import("std");
const pcre2 = @cImport({
    @cDefine("PCRE2_STATIC", "");
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

const StringLIFO = std.SinglyLinkedList([]const u8);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena.deinit();
    const allocator = arena.allocator();

    const args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const path = std.fs.realpathAlloc(allocator, if (args.len > 1) args[1] else ".") catch {
        if (args.len > 1 and std.mem.eql(u8, "--version", args[1])) {
            try std.io.getStdOut().writer().print("git-master", .{});
        } else {
            try std.io.getStdOut().writer().print("Removes trash files and folders recursively.\n", .{});
            try std.io.getStdOut().writer().print("Usage: remove-trash [folder]\n", .{});
        }
        return;
    };
    var cwd = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    defer allocator.free(path);
    defer cwd.close();

    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    var filesToDelete = StringLIFO{};
    var foldersToDelete = StringLIFO{};
    var specialFilesToDelete = StringLIFO{};

    const conditions = [_][]const u8{
        "\\/\\.DS_Store$",
        "\\/\\.cache(\\/|$)",
        "\\/\\.gradle(\\/|$)",
        "\\/\\.mypy_cache(\\/|$)",
        "\\/\\.sass-cache(\\/|$)",
        "\\/\\.textpadtmp(\\/|$)",
        "\\/Thumbs.db$",
        "\\/__pycache__(\\/|$)",
        "\\/_build(\\/|$)",
        "\\/build(\\/|$)",
        "\\/slprj(\\/|$)",
        "\\/zig-cache(\\/|$)",
        "\\/zig-out(\\/|$)",
        "\\/\\.slxc$",
        "\\/\\.bak$",
        "~[^\\/]+$",
    };

    var regexes = std.ArrayList(?*pcre2.struct_pcre2_real_code_8).init(allocator);
    for (conditions) |condition| {
        var error_number: c_int = 0;
        var error_offset: usize = 0;
        const regex = pcre2.pcre2_compile_8(condition.ptr, condition.len, 0, &error_number, &error_offset, null);
        if (regex == null) {
            std.log.err("Could not compile regex {s}.", .{condition});
            std.os.exit(1);
        }
        try regexes.append(regex);
    }

    blk: while (true) {
        const next = walker.next() catch {
            continue;
        };

        if (next == null) {
            break;
        }

        const entry = next.?;

        const dirPath = entry.dir.realpathAlloc(allocator, ".") catch |err| {
            std.log.warn("Could not get path for {s}, {}", .{ entry.path, err });
            continue;
        };
        defer allocator.free(dirPath);
        const entry_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dirPath, entry.basename });

        for (regexes.items) |regex| {
            const match_data = pcre2.pcre2_match_data_create_from_pattern_8(regex, null);
            defer pcre2.pcre2_match_data_free_8(match_data);

            if (match_data == null) {
                std.log.err("Could not create match data.", .{});
                std.os.exit(1);
            }

            const rc = pcre2.pcre2_match_8(regex, entry_path.ptr, entry_path.len, 0, 0, match_data.?, null);
            if (rc > 0) {
                const node = try allocator.create(StringLIFO.Node);
                node.* = StringLIFO.Node{ .data = entry_path };
                switch (entry.kind) {
                    .directory => foldersToDelete.prepend(node),
                    .file => filesToDelete.prepend(node),
                    else => specialFilesToDelete.prepend(node),
                }
                continue :blk;
            }
        }

        allocator.free(entry_path);
    }

    var size: usize = 0;
    while (filesToDelete.popFirst()) |node| {
        const filePath = node.data;
        const file = std.fs.openFileAbsolute(filePath, .{ .mode = .read_write }) catch |err| {
            std.log.warn("Cannot open {s} as read/write ({})", .{ filePath, err });
            continue;
        };
        const stat = file.stat() catch {
            std.log.warn("Cannot stat {s}", .{filePath});
            file.close();
            continue;
        };
        size += stat.size;
        file.close();
        std.fs.deleteFileAbsolute(filePath) catch {
            std.log.warn("Could not delete {s}", .{filePath});
        };
    }

    while (specialFilesToDelete.popFirst()) |node| {
        const filePath = node.data;
        std.fs.deleteFileAbsolute(filePath) catch {
            std.log.warn("Could not delete {s}", .{filePath});
        };
    }

    while (foldersToDelete.popFirst()) |node| {
        const filePath = node.data;
        std.fs.deleteDirAbsolute(filePath) catch {
            std.log.warn("Could not delete {s}", .{filePath});
        };
    }

    try std.io.getStdOut().writer().print("Freed {:.2}\n", .{std.fmt.fmtIntSizeBin(size)});
}
