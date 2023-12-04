const std = @import("std");
const clap = @import("clap");

const version = "0.0.1";

pub fn getPath(allocator: std.mem.Allocator) ?[]const u8 {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help      Display this help and exit.
        \\-v, --version   Display the version and exit.
        \\<FOLDER>        Folder to traverse. Defaults to cwd.
    );

    const parsers = comptime .{
        .FOLDER = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{ .diagnostic = &diag }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return null;
    };
    defer res.deinit();

    const writer = std.io.getStdOut().writer();

    if (res.args.help != 0) {
        writer.print("remove-trash version {s}\n\n", .{version}) catch {};
        writer.print("Usage: remove-trash [FOLDER]\n\n", .{}) catch {};
        clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{}) catch {};
        return null;
    } else if (res.args.version != 0) {
        writer.print("{s}\n", .{version}) catch {};
        return null;
    }

    const path = if (res.positionals.len > 0) res.positionals[0] else ".";
    return std.fs.realpathAlloc(allocator, path) catch {
        std.io.getStdErr().writer().print("could not find real path for {s}\n", .{path}) catch {};
        return null;
    };
}
