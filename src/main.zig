pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    var diag: Diagnostic = .{};
    const config = Config.parse(alloc, init.minimal.args, &diag) catch |err| {
        switch (err) {
            error.UnknownArgument => {
                std.debug.print("Unknown argument: {s}\n", .{diag.by_arg});
            },
            error.MissingValue => {
                std.debug.print("Missing value for: {s}\n- {s}.\n", .{ diag.by_arg, diag.desc });
            },
            error.InvalidValue => {
                std.debug.print("Invalid value for: {s}\n- {s}.\n", .{ diag.by_arg, diag.desc });
            },
            error.OutOfMemory => {
                std.debug.print(
                    \\Program stopped.
                    \\- Out of memory.
                    \\
                , .{});
            },
        }
        return;
    };

    process(io, alloc, &config, &diag) catch |err| switch (err) {
        error.ReadFailed => {
            std.debug.print(
                \\Cannot read xml file.
                \\- Path: {s}
                \\- Accessable Xml for sure?
                \\
            , .{config.input.?});
        },
        error.EmptyInput => {
            std.debug.print(
                \\No input file
                \\- You didn't provide Xml path.
                \\- Please use `-i` or `--input` to select one
                \\- Or use `all` to convert all under this path.
                \\
            , .{});
        },
        error.PathNotAvailable => {
            std.debug.print(
                \\Current working path is not available.
                \\- error.{s}
                \\
            , .{diag.desc});
        },
        error.InvalidPath => {
            std.debug.print(
                \\Invalid path
                \\- Specified working path is not accessable.
                \\
            , .{});
        },
        error.InvalidOutputPath => {
            std.debug.print(
                \\Invalid output path
                \\- Specified output path is invalid.
                \\
            , .{});
        },
        error.InvalidFormat => {
            std.debug.print(
                \\Invalid format: {s}
                \\- Xml file has invalid format.
                \\
            , .{config.input.?});
        },
        error.TokenTooLong => {
            std.debug.print(
                \\Token too long.
                \\- Xml file might be broken.
                \\
            , .{});
        },
        error.OutOfMemory => {
            std.debug.print(
                \\Program stopped.
                \\- Out of memory.
                \\
            , .{});
        },
        error.WriteFailed => {
            std.debug.print(
                \\Cannot write to output file.
                \\- Path: {s}
                \\- error.{s}.
                \\
            , .{ diag.by_arg, diag.desc });
        },
        error.TooManyTracks => {
            std.debug.print(
                \\Danmakus exploded.
                \\- Quantity exceeded expectation.
                \\- Might need to increase `--track-limit`.
                \\
            , .{});
        },
    };
}

const ProcessError = ParseError || AssError || error{
    InvalidOutputPath,
    PathNotAvailable,
};

fn process(io: std.Io, arena: std.mem.Allocator, config: *const Config, diag: ?*Diagnostic) ProcessError!void {
    const working_path = if (config.path) |p|
        if (std.Io.Dir.path.isAbsolute(p))
            std.Io.Dir.openDirAbsolute(io, p, .{ .iterate = config.mode == .all }) catch return ParseError.ReadFailed
        else
            std.Io.Dir.cwd().openDir(io, p, .{ .iterate = config.mode == .all }) catch return ParseError.InvalidPath
    else
        std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = config.mode == .all }) catch return ProcessError.PathNotAvailable;

    defer if (config.path != null) working_path.close(io);

    switch (config.mode) {
        .version => {
            std.debug.print("{s}\n", .{Config.VERSION});
        },
        .help => {
            std.debug.print(
                \\
                \\| Xml2ass
                \\| {s}
                \\
                \\Commands:
                \\  h, help, --help     Show command list
                \\  all                 Convert all xml file under working path
                \\  v,version,--version Show program version
                \\
                \\Options:
                \\  -i, --input     Input file (xml)
                \\  -o, --output    Output path (ass)
                \\  -p, --path      Wokring path
                \\  -r, --replace   Overwrite existing files
                \\
                \\  -w, --width     Default: 960 | Screen width for position calculation
                \\  -h, --height    Default: 540 | Screen height for position calculation
                \\
                \\  --font-size     Default font size
                \\
                \\  --scroll-speed  Default: 100  | Speed of scrolling danmaku (Unit: px/s)
                \\  --stay-duration Default: 2000 | Stay time of top/down Danmaku (Unit: miliseconds)
                \\  --track-limit   Default: 16   | Number of max tracks
                \\
                \\
            , .{Config.VERSION});
        },
        .single => {
            if (config.input == null) return ParseError.EmptyInput;

            const target_path = if (config.output) |output| output else try pth.renameExt(arena, config.input.?, "ass");

            var danmakus: std.ArrayList(Danmaku) = .empty;
            try process_file(arena, io, &working_path, config, config.input.?, target_path, &danmakus, diag);

            std.debug.print(
                \\Conversion finished
                \\- Converted {d} lines to Danmaku.
                \\
            , .{danmakus.items.len});
        },
        .all => {
            var processed_file: usize = 0;
            var processed_danmaku: usize = 0;

            var iter = working_path.iterate();
            while (iter.next(io) catch |err| {
                if (diag) |d| d.desc = @errorName(err);
                return ProcessError.PathNotAvailable;
            }) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".xml")) {
                    var danmakus: std.ArrayList(Danmaku) = .empty;
                    try process_file(arena, io, &working_path, config, entry.name, try pth.renameExt(arena, entry.name, "ass"), &danmakus, diag);

                    processed_file += 1;
                    processed_danmaku += danmakus.items.len;
                }
            }

            std.debug.print(
                \\Conversion finished
                \\- Converted {d} files.
                \\- Total {d} danmakus.
                \\
            , .{ processed_file, processed_danmaku });
        },
    }
}

fn process_file(arena: std.mem.Allocator, io: std.Io, cwd: *const std.Io.Dir, config: *const Config, file_path: []const u8, target_path: []const u8, danmakus: *std.ArrayList(Danmaku), diag: ?*Diagnostic) ProcessError!void {
    var target_file = cwd.createFileAtomic(io, target_path, .{ .replace = config.force }) catch return ProcessError.InvalidOutputPath;
    defer target_file.deinit(io);

    const file = cwd.openFile(io, file_path, .{}) catch return ParseError.ReadFailed;
    defer file.close(io);

    try xml.parseFile(io, arena, config, file, danmakus);

    std.mem.sort(Danmaku, danmakus.items, .{}, struct {
        fn lessThan(_: @TypeOf(.{}), lhs: Danmaku, rhs: Danmaku) bool {
            return lhs.time < rhs.time;
        }
    }.lessThan);

    try ass.writeAll(io, arena, config, target_file, danmakus.items);

    (if (config.force)
        target_file.replace(io)
    else
        target_file.link(io)) catch |err| {
        if (diag) |d| {
            d.by_arg = target_path;
            d.desc = @errorName(err);
        }
        return ProcessError.WriteFailed;
    };
}

const std = @import("std");
const mod = @import("model.zig");
const pth = @import("path.zig");
const xml = @import("xml.zig");
const ass = @import("ass.zig");

const Config = @import("Config.zig");
const Diagnostic = Config.Diagnostic;
const ExecMode = Config.ExecMode;

const ParseError = xml.ParseError;
const AssError = ass.AssError;
const Danmaku = mod.Danmaku;
