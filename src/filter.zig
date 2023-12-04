const std = @import("std");
const pcre2 = @cImport({
    @cDefine("PCRE2_STATIC", "");
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

pub const Filter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    trashRegexes: std.ArrayList(?*pcre2.struct_pcre2_real_code_8),
    skipFolders: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !Self {
        const conditions = [_][]const u8{
            "^\\.DS_Store$",
            "^\\.cache$",
            "^\\.gradle$",
            "^\\.mypy_cache$",
            "^\\.sass-cache$",
            "^\\.textpadtmp$",
            "^Thumbs.db$",
            "^__pycache__$",
            "^_build$",
            "^build$",
            "^slprj$",
            "^zig-cache$",
            "^zig-out$",
            "\\.slxc$",
            "\\.bak$",
            "^~",
        };

        var trashRegexes = std.ArrayList(?*pcre2.struct_pcre2_real_code_8).init(allocator);
        for (conditions) |condition| {
            var error_number: c_int = 0;
            var error_offset: usize = 0;
            const regex = pcre2.pcre2_compile_8(condition.ptr, condition.len, 0, &error_number, &error_offset, null);
            if (regex == null) {
                try std.io.getStdErr().writer().print("Could not compile regex {s}.\n", .{condition});
                std.os.exit(1);
            }
            try trashRegexes.append(regex);
        }

        var env_map = try std.process.getEnvMap(allocator);
        defer env_map.deinit();

        const userFolder = env_map.get("HOME") orelse {
            try std.io.getStdErr().writer().print("A HOME environment variable is necessary to avoid removing ~/.var\n", .{});
            std.os.exit(1);
        };

        var skipFolders = std.ArrayList([]const u8).init(allocator);
        const sprintf = std.fmt.allocPrint;
        try skipFolders.append(try sprintf(allocator, "{s}/.var", .{userFolder}));
        try skipFolders.append(try sprintf(allocator, "{s}/.local/share/Steam", .{userFolder}));
        try skipFolders.append(try sprintf(allocator, "{s}/.steam", .{userFolder}));

        return Self{
            .allocator = allocator,
            .trashRegexes = trashRegexes,
            .skipFolders = skipFolders,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.trashRegexes.items) |regex| {
            pcre2.pcre2_code_free_8(regex);
        }
        for (self.skipFolders.items) |skip| {
            self.allocator.free(skip);
        }
        self.trashRegexes.deinit();
        self.skipFolders.deinit();
    }

    pub fn shouldDelete(self: Self, path: []const u8) bool {
        for (self.trashRegexes.items) |regex| {
            const match_data = pcre2.pcre2_match_data_create_from_pattern_8(regex, null);
            defer pcre2.pcre2_match_data_free_8(match_data);

            if (match_data == null) {
                std.io.getStdErr().writer().print("Could not create match data.\n", .{}) catch {};
                std.os.exit(1);
            }

            const rc = pcre2.pcre2_match_8(regex, path.ptr, path.len, 0, 0, match_data.?, null);
            if (rc > 0) {
                return true;
            }
        }
        return false;
    }

    pub fn shouldSkip(self: Self, path: []const u8) bool {
        for (self.skipFolders.items) |skip| {
            if (std.mem.startsWith(u8, path, skip)) {
                return true;
            }
        }
        return false;
    }
};
