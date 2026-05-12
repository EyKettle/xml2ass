const Track = @This();

const ActiveItem = struct {
    y: u32,
    height: u32,
    end_time: f64,
};

const TrackError = error{ OutOfTrack, OutOfMemory };

alloc: std.mem.Allocator,
config: *const Config,
actives: ArrayList(ActiveItem),

pub fn init(alloc: std.mem.Allocator, config: *const Config) TrackError!Track {
    return .{
        .alloc = alloc,
        .config = config,
        .actives = ArrayList(ActiveItem).initCapacity(alloc, 16) catch return TrackError.OutOfMemory,
    };
}

pub fn deinit(self: *Track) void {
    self.actives.deinit(self.alloc);
}

/// Get the y position for a new danmaku.
///
/// By default, appearance times are assumed to be `increasing`.
pub fn findTrackY(self: *Track, danmaku: *const Danmaku, duration: f64) TrackError!u32 {
    var write_idx: usize = 0;
    for (self.actives.items) |active| {
        if (active.end_time > danmaku.time) {
            self.actives.items[write_idx] = active;
            write_idx += 1;
        }
    }
    self.actives.shrinkRetainingCapacity(write_idx);

    const height = (danmaku.font_size orelse self.config.font_size) + self.config.font_margin * 2;

    var current_y: u32 = 0;
    var insert_idx: usize = self.actives.items.len;
    for (self.actives.items, 0..) |*active, i| {
        if (current_y + height <= active.y) {
            insert_idx = i;
            break;
        }
        current_y = active.y + active.height;
        if (current_y + height >= self.config.screen_height) return TrackError.OutOfTrack;
    }

    const new: ActiveItem = .{
        .end_time = danmaku.time + duration,
        .y = current_y,
        .height = height,
    };
    try self.actives.insert(self.alloc, insert_idx, new);

    return current_y;
}

const std = @import("std");
const mod = @import("model.zig");

const ArrayList = std.ArrayList;

const Config = @import("Config.zig");
const Danmaku = mod.Danmaku;
