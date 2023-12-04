const std = @import("std");
const args = @import("args.zig");
const Filter = @import("filter.zig").Filter;
const Walker = @import("walker.zig").Walker;

const StringLIFO = std.SinglyLinkedList([]const u8);

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer _ = arena.deinit();
    // const allocator = arena.allocator();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const path = args.getPath(allocator) orelse return;
    defer allocator.free(path);

    var filesToDelete = StringLIFO{};
    var foldersToDelete = StringLIFO{};
    var specialFilesToDelete = StringLIFO{};

    var filter = try Filter.init(allocator);
    defer filter.deinit();

    var walker = try Walker.init(allocator, path);
    defer walker.deinit();

    while (walker.walk()) |action| {
        const entry = walker.entry;
        var delete = false;
        var ignore = false;

        switch (action) {
            .ignore => continue,
            .delete => delete = true,
            .verify => {
                ignore = filter.shouldSkip(entry.?.basename);
                delete = !ignore and filter.shouldDelete(entry.?.basename);
            },
        }

        if (ignore and entry.?.kind == .directory) {
            walker.mark(.ignore);
            continue;
        }

        if (delete) {
            const node = allocator.create(StringLIFO.Node) catch continue;
            const entryPath = allocator.dupe(u8, entry.?.path) catch {
                allocator.destroy(node);
                continue;
            };
            node.* = StringLIFO.Node{ .data = entryPath };
            switch (walker.entry.?.kind) {
                .directory => {
                    walker.mark(.delete);
                    foldersToDelete.prepend(node);
                },
                .file => filesToDelete.prepend(node),
                else => specialFilesToDelete.prepend(node),
            }
        }
    }

    const dir = try std.fs.openDirAbsolute(path, .{});
    var size: usize = 0;
    while (filesToDelete.popFirst()) |node| {
        defer allocator.destroy(node);
        defer allocator.free(node.data);

        const filePath = node.data;
        const file = dir.openFile(filePath, .{ .mode = .read_write }) catch |err| {
            try std.io.getStdErr().writer().print("Cannot open {s} as read/write ({})\n", .{ filePath, err });
            continue;
        };
        const stat = file.stat() catch {
            try std.io.getStdErr().writer().print("Cannot stat {s}\n", .{filePath});
            file.close();
            continue;
        };
        size += stat.size;
        file.close();
        dir.deleteFile(filePath) catch |err| {
            try std.io.getStdErr().writer().print("Could not delete {s} ({})\n", .{ filePath, err });
        };
    }

    while (specialFilesToDelete.popFirst()) |node| {
        defer allocator.destroy(node);
        defer allocator.free(node.data);

        const filePath = node.data;
        dir.deleteFile(filePath) catch {
            try std.io.getStdErr().writer().print("Could not delete {s}\n", .{filePath});
        };
    }

    while (foldersToDelete.popFirst()) |node| {
        defer allocator.destroy(node);
        defer allocator.free(node.data);

        const filePath = node.data;
        dir.deleteDir(filePath) catch {
            try std.io.getStdErr().writer().print("Could not delete {s}\n", .{filePath});
        };
    }

    try std.io.getStdOut().writer().print("Freed {:.2}\n", .{std.fmt.fmtIntSizeBin(size)});
}
