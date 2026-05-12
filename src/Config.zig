const Config = @This();

pub const VERSION = "0.1.1";

mode: ExecMode = .help,
force: bool = false,
input: ?[]const u8 = null,
output: ?[]const u8 = null,
path: ?[]const u8 = null,

screen_width: u32 = 960,
screen_height: u32 = 540,

font_size: u32 = 25,
font_margin: u32 = 4,

/// Unit: `px/s`
scroll_speed: u32 = 100,
/// Unit: `miliseconds`
stay_duration: u32 = 2000,
track_limit: u32 = 16,

pub const ExecMode = enum { single, all, help, version };

pub const Diagnostic = struct {
    by_arg: []const u8 = undefined,
    desc: []const u8 = undefined,
};

pub const ParseError = error{
    UnknownArgument,
    MissingValue,
    InvalidValue,
    OutOfMemory,
};

pub fn parse(alloc: std.mem.Allocator, args: std.process.Args, diag: ?*Diagnostic) ParseError!Config {
    var config: Config = .{};

    var iter = try args.iterateAllocator(alloc);
    defer iter.deinit();

    _ = iter.next();

    const IterStatus = enum {
        Check,
        Unknown,
        Missing,
        Invalid,
    };
    const Command = enum {
        input,
        output,
        path,
        height,
        width,
        font_size,
        scroll_speed,
        stay_duration,
        track_limit,
    };
    var cur_arg: ?[]const u8 = null;
    var command: Command = undefined;
    iter: switch (IterStatus.Check) {
        .Check => {
            cur_arg = iter.next() orelse break :iter;
            const arg = cur_arg.?;
            if (std.mem.eql(u8, arg, "h") or std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help")) {
                config.mode = .help;
                break :iter;
            } else if (std.mem.eql(u8, arg, "v") or std.mem.eql(u8, arg, "version") or std.mem.eql(u8, arg, "--version")) {
                config.mode = .version;
            } else if (std.mem.eql(u8, arg, "all")) {
                config.mode = .all;
            } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
                config.mode = .single;
                config.input = iter.next() orelse {
                    command = .input;
                    continue :iter .Missing;
                };
            } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
                config.output = iter.next() orelse {
                    command = .output;
                    continue :iter .Missing;
                };
            } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--path")) {
                config.path = iter.next() orelse {
                    command = .path;
                    continue :iter .Missing;
                };
            } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--replace")) {
                config.force = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--height")) {
                command = .height;
                config.screen_height = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--width")) {
                command = .width;
                config.screen_width = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else if (std.mem.eql(u8, arg, "--font-size")) {
                command = .font_size;
                config.font_size = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else if (std.mem.eql(u8, arg, "--scroll-speed")) {
                command = .scroll_speed;
                config.scroll_speed = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else if (std.mem.eql(u8, arg, "--stay-duration")) {
                command = .stay_duration;
                config.stay_duration = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else if (std.mem.eql(u8, arg, "--track-limit")) {
                command = .track_limit;
                config.track_limit = std.fmt.parseInt(u32, iter.next() orelse {
                    continue :iter .Missing;
                }, 10) catch {
                    continue :iter .Invalid;
                };
            } else {
                continue :iter .Unknown;
            }
            continue :iter .Check;
        },
        .Unknown => {
            if (diag) |d| d.by_arg = cur_arg.?;
            return ParseError.UnknownArgument;
        },
        .Missing => {
            if (diag) |d| {
                d.by_arg = cur_arg.?;
                d.desc = switch (command) {
                    .input => "Expect a xml file path but void",
                    .output => "Expect a output path but void",
                    .path => "Expect a working path but void",
                    .width,
                    .height,
                    .font_size,
                    .scroll_speed,
                    .stay_duration,
                    .track_limit,
                    => "Expect a number but void",
                };
            }
            return ParseError.MissingValue;
        },
        .Invalid => {
            if (diag) |d| {
                d.by_arg = cur_arg.?;
                d.desc = switch (command) {
                    .width,
                    .height,
                    .font_size,
                    .scroll_speed,
                    .stay_duration,
                    .track_limit,
                    => "Provided an invalid value for number",
                    else => unreachable,
                };
            }
            return ParseError.InvalidValue;
        },
    }
    if (cur_arg == null) {
        config.mode = .help;
    }

    return config;
}

const std = @import("std");
