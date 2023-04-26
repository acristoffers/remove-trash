const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const path = try std.fs.realpathAlloc(allocator, if (args.len > 1) args[1] else ".");
    var cwd = try std.fs.openIterableDirAbsolute(path, .{});
    defer allocator.free(path);
    defer cwd.close();

    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    var size: u64 = 0;
    var err: usize = 0;
    while (err < 3) {
        const next = walker.next() catch {
            std.log.info("Could not walk\n", .{});
            err += 1;
            continue;
        };

        if (next == null) {
            break;
        }

        const entry = next.?;
        const last_four = if (entry.basename.len > 4) entry.basename.len - 4 else 0;
        const conditions = [_]bool{
            std.mem.eql(u8, entry.basename, ".DS_Store"),
            std.mem.eql(u8, entry.basename, "Thumbs.db"),
            std.mem.eql(u8, entry.basename, ".sass-cache"),
            std.mem.eql(u8, entry.basename, "__pycache__"),
            std.mem.eql(u8, entry.basename, ".mypy_cache"),
            std.mem.eql(u8, entry.basename, ".textpadtmp"),
            std.mem.eql(u8, entry.basename, ".gradle"),
            std.mem.eql(u8, entry.basename, ".cache"),
            std.mem.eql(u8, entry.basename, "build"),
            std.mem.eql(u8, entry.basename[last_four..], ".bak"),
            entry.basename[0] == '~',
        };

        if (@reduce(.Or, @as(@Vector(11, bool), conditions))) {
            const entry_path = entry.dir.realpathAlloc(allocator, entry.basename) catch {
                std.log.info("Could not get path for {s}\n", .{entry.path});
                continue;
            };
            defer allocator.free(entry_path);

            if (entry.kind == .File) {
                var file = entry.dir.statFile(entry.basename) catch {
                    std.log.info("Could not stat {s}\n", .{entry_path});
                    continue;
                };

                size += file.size;

                entry.dir.deleteFile(entry.basename) catch {
                    std.log.info("Could not delete {s}\n", .{entry_path});
                };
            } else if (entry.kind == .Directory) {
                var sub_iter = entry.dir.openIterableDir(".", .{}) catch {
                    std.log.info("Could not open iterable for {s}\n", .{entry_path});
                    continue;
                };
                var sub_walker = sub_iter.walk(allocator) catch {
                    std.log.info("Could not walk {s}\n", .{entry_path});
                    continue;
                };
                defer sub_iter.close();
                defer sub_walker.deinit();

                var err_sub: usize = 0;
                while (err_sub < 3) {
                    const sub_next = sub_walker.next() catch {
                        std.log.info("Could not walk next {s}\n", .{entry_path});
                        err_sub += 1;
                        continue;
                    };

                    if (sub_next == null) {
                        break;
                    }

                    const sub_entry = sub_next.?;

                    const sub_entry_path = sub_entry.dir.realpathAlloc(allocator, sub_entry.basename) catch {
                        std.log.info("Could not get path for {s}\n", .{sub_entry.path});
                        continue;
                    };
                    defer allocator.free(sub_entry_path);

                    if (sub_entry.kind == .File) {
                        var file = sub_entry.dir.statFile(sub_entry.basename) catch {
                            std.log.info("Could not stat {s}\n", .{sub_entry_path});
                            continue;
                        };

                        size += file.size;
                    }
                }

                entry.dir.deleteTree(entry.basename) catch {
                    std.log.info("Could not delete {s}\n", .{entry_path});
                };
            }
        }
    }

    try std.io.getStdOut().writer().print("Freed {:.2}\n", .{std.fmt.fmtIntSizeBin(size)});
}
