pub const WriteError = error{
    FileExist,
    CannotAccess,
};

pub fn writeGuard(io: std.Io, sub_path: []const u8, cwd: Dir) WriteError!void {
    if (Dir.path.dirname(sub_path)) |parent_path| {
        var parent = cwd.openDir(io, parent_path, .{}) catch return WriteError.CannotAccess;
        parent.close(io);
    }

    if (cwd.statFile(io, sub_path, .{})) |_| {
        return WriteError.FileExist;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return WriteError.CannotAccess,
    }
}

/// Rename the extention of path.
///
/// Result will allways be a file path.
pub fn renameExt(alloc: std.mem.Allocator, path: []const u8, ext: []const u8) ![]const u8 {
    const filename = Dir.path.basename(path);

    var ext_idx = std.mem.findScalarLast(u8, filename, '.') orelse filename.len;
    if (ext_idx == 0) ext_idx = filename.len;

    const ext_len = filename.len - ext_idx;

    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ path[0 .. path.len - ext_len], ext });
}

const std = @import("std");
const Dir = std.Io.Dir;
