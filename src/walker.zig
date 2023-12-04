const std = @import("std");

pub const WalkResult = enum {
    delete,
    ignore,
    verify,
};

pub const Walker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cwd: std.fs.Dir,
    walker: std.fs.Dir.Walker,
    entry: ?std.fs.Dir.Walker.WalkerEntry,

    stackDepth: usize,
    markedPath: []u8,
    markedPathLen: usize,
    action: WalkResult,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        const cwd = try std.fs.openDirAbsolute(path, .{ .iterate = true });
        const walker = try cwd.walk(allocator);
        return .{
            .allocator = allocator,
            .cwd = cwd,
            .entry = null,
            .walker = walker,
            .stackDepth = 0,
            .action = .verify,
            .markedPath = try allocator.alloc(u8, std.fs.MAX_PATH_BYTES),
            .markedPathLen = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.walker.deinit();
        self.cwd.close();
        self.allocator.free(self.markedPath);
    }

    pub fn walk(self: *Self) ?WalkResult {
        while (true) {
            self.entry = self.walker.next() catch continue orelse return null;
            if (self.stackDepth == 0) {
                return .verify;
            } else if (self.stackDepth > self.walker.stack.items.len) {
                self.stackDepth = 0;
                return .verify;
            } else if (self.stackDepth == self.walker.stack.items.len) {
                if (!std.mem.startsWith(u8, self.entry.?.path, self.markedPath[0..self.markedPathLen])) {
                    self.stackDepth = 0;
                    return .verify;
                } else {
                    return self.action;
                }
            } else {
                return self.action;
            }
        }
    }

    pub fn mark(self: *Self, action: WalkResult) void {
        if (self.stackDepth != 0) return;
        self.action = action;
        self.stackDepth = self.walker.stack.items.len;
        @memcpy(self.markedPath[0..self.entry.?.path.len], self.entry.?.path);
        self.markedPathLen = self.entry.?.path.len;
    }
};
