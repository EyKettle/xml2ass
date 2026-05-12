pub const AssError = error{ WriteFailed, TooManyTracks, OutOfMemory };

pub fn writeAll(
    io: std.Io,
    alloc: std.mem.Allocator,
    config: *const Config,
    atomic: File.Atomic,
    danmakus: []const Danmaku,
) AssError!void {
    var buffer: [64 * 1024]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    const writer = &file_writer.interface;

    try writer.print(
        \\[Script Info]
        \\ScriptType: v4.00+
        \\WrapStyle: 2
        \\PlayResX: {d}
        \\PlayResY: {d}
        \\ScaledBorderAndShadow: yes
        \\YCbCr Matrix: None
        \\
        \\[V4+ Styles]
        \\Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        \\Style: Default,Microsoft YaHei,{d},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1,0,2,20,20,10,1
        \\
        \\[Events]
        \\Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        \\
    , .{ config.screen_width, config.screen_height, config.font_size });

    var scroll_tracks: ArrayList(Track) = try .initCapacity(alloc, 1);
    var top_tracks: ArrayList(Track) = try .initCapacity(alloc, 1);
    var bottom_tracks: ArrayList(Track) = try .initCapacity(alloc, 1);
    defer {
        for (scroll_tracks.items) |*track| track.deinit();
        for (top_tracks.items) |*track| track.deinit();
        for (bottom_tracks.items) |*track| track.deinit();

        scroll_tracks.deinit(alloc);
        top_tracks.deinit(alloc);
        bottom_tracks.deinit(alloc);
    }

    for (danmakus) |danmaku| {
        var time_buf: [32]u8 = undefined;

        const width = (estimateWidth(danmaku.content, danmaku.font_size orelse config.font_size) catch {
            std.debug.print("Skipped. Invalid utf8: {s}\n", .{danmaku.content});
            continue;
        }) + config.font_margin * 2;
        const start_time = secondsToAssTime(danmaku.time, time_buf[0..16]);
        const color = toAssColor(danmaku.color);

        const SizeFs = struct {
            size: ?u32,
            pub fn format(
                self: @This(),
                w: *std.Io.Writer,
            ) std.Io.Writer.Error!void {
                if (self.size) |size| {
                    try w.print("\\fs{d}", .{size});
                }
            }
        };

        switch (danmaku.mode) {
            .scroll, .reverse => {
                const movement: f64 = @floatFromInt(config.screen_width + width);
                const speed: f64 = @floatFromInt(config.scroll_speed);
                const duration = movement / speed;
                const end_time = secondsToAssTime(danmaku.time + duration, time_buf[16..32]);

                const free_duration = @as(f64, @floatFromInt(width + 64)) / speed;
                const result = try findTracks(alloc, config, &scroll_tracks, &danmaku, free_duration);
                try writer.print("Dialogue:{d},{s},{s},Default,,0,0,0,,{{\\an7\\c&H{x:0>6}&{f}\\move({s}{d},{d},{s}{d},{d})}}{s}\n", .{
                    result.track_id,
                    start_time,
                    end_time,
                    color,
                    SizeFs{ .size = danmaku.font_size },
                    if (danmaku.mode == .reverse) "-" else "",
                    if (danmaku.mode == .reverse) width else config.screen_width,
                    result.y,
                    if (danmaku.mode == .reverse) "" else "-",
                    if (danmaku.mode == .reverse) config.screen_width else width,
                    result.y,
                    danmaku.content,
                });
            },
            .top, .bottom => {
                const duration = @as(f64, @floatFromInt(config.stay_duration)) / std.time.ms_per_s;
                const end_time = secondsToAssTime(danmaku.time + duration, time_buf[16..32]);

                const result = try findTracks(alloc, config, &(if (danmaku.mode == .top) top_tracks else bottom_tracks), &danmaku, duration);
                try writer.print("Dialogue:{d},{s},{s},Default,,0,0,0,,{{\\an{c}\\c&H{x:0>6}&{f}\\pos({d},{d})}}{s}\n", .{
                    config.track_limit + 1 + result.track_id,
                    start_time,
                    end_time,
                    @as(u8, if (danmaku.mode == .top) '8' else '2'),
                    color,
                    SizeFs{ .size = danmaku.font_size },
                    config.screen_width / 2,
                    if (danmaku.mode == .top) result.y else config.screen_height - result.y,
                    danmaku.content,
                });
            },
        }
    }

    try writer.flush();
}

const FindResult = struct {
    track_id: usize,
    y: u32,
};

fn findTracks(alloc: std.mem.Allocator, config: *const Config, track_list: *ArrayList(Track), danmaku: *const Danmaku, duration: f64) AssError!FindResult {
    for (track_list.items, 0..) |*track, i| {
        return .{ .track_id = i, .y = track.findTrackY(danmaku, duration) catch |err| switch (err) {
            error.OutOfTrack => continue,
            error.OutOfMemory => return AssError.OutOfMemory,
        } };
    }

    if (track_list.items.len >= config.track_limit - 1) return AssError.TooManyTracks;

    var track = Track.init(alloc, config) catch return AssError.OutOfMemory;
    try track_list.append(alloc, track);

    return .{ .track_id = track_list.items.len - 1, .y = track.findTrackY(danmaku, duration) catch |err| switch (err) {
        error.OutOfTrack => unreachable,
        error.OutOfMemory => return AssError.OutOfMemory,
    } };
}

fn estimateWidth(text: []const u8, font_size: u32) !u32 {
    var total_width: f32 = 0;

    const view = try std.unicode.Utf8View.init(text);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |cp| {
        if (cp < 128) {
            total_width += @as(f32, @floatFromInt(font_size)) * 0.55;
        } else {
            total_width += @as(f32, @floatFromInt(font_size));
        }
    }

    return @intFromFloat(total_width);
}

/// Convert seconds to ASS time slice (`H:MM:SS.cc`).
///
/// Buffer must has at least 12 bytes.
pub fn secondsToAssTime(sec: f64, buf: []u8) []u8 {
    const total_cs: u64 = @intFromFloat(@round(sec * 100.0));

    const hours = total_cs / 360000;
    const rem = total_cs % 360000;
    const minutes = rem / 6000;
    const seconds = (rem % 6000) / 100;
    const centiseconds = rem % 100;

    return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}.{d:0>2}", .{
        hours, minutes, seconds, centiseconds,
    }) catch unreachable;
}

/// Convert RGB color to ASS BGR color
pub fn toAssColor(rgb: u32) u32 {
    const r = (rgb >> 16) & 0xff;
    const g = (rgb >> 8) & 0xff;
    const b = rgb & 0xff;
    const bgr = (@as(u32, b) << 16) | @as(u32, g) << 8 | r;
    return bgr;
}

const std = @import("std");
const mod = @import("model.zig");

const ArrayList = std.ArrayList;

const Config = @import("Config.zig");
const File = std.Io.File;
const Danmaku = mod.Danmaku;
const Track = @import("Track.zig");
