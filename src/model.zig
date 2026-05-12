pub const DanmakuMode = enum {
    scroll,
    reverse,
    top,
    bottom,
};

pub const Danmaku = struct {
    time: f64,
    mode: DanmakuMode = .scroll,
    font_size: ?u32 = null,
    color: u32 = 0xFFFFFF,
    content: []const u8,
};
