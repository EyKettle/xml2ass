pub const ParseError = error{
    ReadFailed,
    EmptyInput,
    InvalidPath,
    InvalidFormat,
    TokenTooLong,
    OutOfMemory,
};

pub fn parseFile(io: std.Io, alloc: std.mem.Allocator, config: *const Config, file: std.Io.File, list: *std.ArrayList(Danmaku)) ParseError!void {
    var window: [64 * 1024]u8 = undefined;

    var head: usize = 0;
    var tail: usize = 0;

    var file_reader = file.reader(io, &.{});
    const reader = &file_reader.interface;

    scan: switch (ProcessStatus.read) {
        .read => {
            const bytes_read = reader.readSliceShort(window[tail..]) catch return ParseError.ReadFailed;
            if (bytes_read == 0) break :scan;

            // Filter space
            var write_ptr = tail;
            for (window[tail .. tail + bytes_read]) |c| {
                if (c != '\n' and c != '\r') {
                    window[write_ptr] = c;
                    write_ptr += 1;
                }
            }

            tail = write_ptr;
            continue :scan .check;
        },
        .check => {
            const valid_data = window[head..tail];
            const start_idx = std.mem.find(u8, valid_data, "<d ") orelse {
                head = if (tail > 3) tail - 3 else 0;
                continue :scan .sliding;
            };
            const end_idx = (std.mem.findPos(u8, valid_data, start_idx + 3, "</d>") orelse {
                head += start_idx;
                continue :scan .sliding;
            }) + 4;
            head += end_idx;

            const line = valid_data[start_idx..end_idx];
            const danmaku = parseLine(alloc, config, line) catch |err| {
                std.debug.print("[WARN] Skip invalid danmaku with {s}.\n- Source Line:\n  {s}\n", .{ switch (err) {
                    error.InvalidAttr => "broken attributes",
                    error.InvalidContent => "unrecognizable content",
                    error.OutOfMemory => return ParseError.OutOfMemory,
                }, line });
                continue :scan .check;
            };
            list.append(alloc, danmaku) catch return ParseError.OutOfMemory;

            continue :scan .check;
        },
        .sliding => {
            if (head > 0 and head < tail) {
                const remaining = tail - head;
                @memmove(window[0..remaining], window[head..tail]);
                head = 0;
                tail = remaining;
            } else if (head == tail) {
                head = 0;
                tail = 0;
            } else if (tail == window.len and head == 0)
                return ParseError.TokenTooLong;

            continue :scan .read;
        },
    }
}

const ProcessStatus = enum {
    read,
    check,
    sliding,
};

const Danmaku = mod.Danmaku;

const DanmakuError = error{
    InvalidAttr,
    InvalidContent,
    OutOfMemory,
};

fn parseLine(alloc: std.mem.Allocator, config: *const Config, line: []u8) DanmakuError!Danmaku {
    var danmaku: Danmaku = .{
        .content = undefined,
        .time = undefined,
    };

    var valid_data = line[3 .. line.len - 4];

    const attr_start = (std.mem.find(u8, valid_data, "p=\"") orelse return DanmakuError.InvalidAttr) + 3;
    const attr_end = std.mem.findScalarPos(u8, valid_data, attr_start + 3, '\"') orelse return DanmakuError.InvalidAttr;

    var attrs_iter = std.mem.splitScalar(u8, valid_data[attr_start..attr_end], ',');
    var index: usize = 0;
    while (attrs_iter.next()) |raw_attr| : (index += 1) {
        const attr = std.mem.trim(u8, raw_attr, " ");
        switch (index) {
            0 => danmaku.time = std.fmt.parseFloat(f64, attr) catch return DanmakuError.InvalidAttr,
            1 => danmaku.mode = switch (std.fmt.parseInt(u8, attr, 10) catch return DanmakuError.InvalidAttr) {
                1...3 => .scroll,
                4 => .bottom,
                5 => .top,
                6 => .reverse,
                else => .scroll,
            },
            2 => {
                const parsed_size = std.fmt.parseInt(u32, attr, 10) catch continue;
                if (parsed_size != config.font_size)
                    danmaku.font_size = parsed_size;
            },
            3 => danmaku.color = std.fmt.parseInt(u32, attr, 10) catch continue,
            else => break,
        }
    }

    const cont_start = (std.mem.findScalarPos(u8, valid_data, attr_end + 1, '>') orelse return DanmakuError.InvalidContent) + 1;
    const cont_end = cont_start + decodeXmlEntities(valid_data[cont_start..]);

    const content = alloc.dupe(u8, valid_data[cont_start..cont_end]) catch return DanmakuError.OutOfMemory;
    danmaku.content = content;

    return danmaku;
}

const Entity = enum { lt, gt, amp, quot, apos };

fn decodeXmlEntities(raw_content: []u8) usize {
    const Status = enum { move, match, fallback };
    var src = raw_content;
    var write_idx: usize = 0;
    var tag: []const u8 = undefined;

    scan: switch (Status.move) {
        .move => {
            if (std.mem.findScalar(u8, src, '&')) |offset| {
                if (offset > 0) {
                    if (src.ptr != raw_content[write_idx..].ptr)
                        @memmove(raw_content[write_idx .. write_idx + offset], src[0..offset]);
                    write_idx += offset;
                    src = src[offset..];
                }

                const max_len = @min(src.len, 10);
                const tag_end = std.mem.findScalar(u8, src[0..max_len], ';') orelse continue :scan .fallback;
                tag = src[1..tag_end];

                continue :scan .match;
            } else {
                if (src.ptr != raw_content[write_idx..].ptr)
                    @memmove(raw_content[write_idx .. write_idx + src.len], src);
                write_idx += src.len;
            }
        },
        .match => {
            if (std.meta.stringToEnum(Entity, tag)) |e| {
                raw_content[write_idx] = switch (e) {
                    .lt => '<',
                    .gt => '>',
                    .amp => '&',
                    .quot => '"',
                    .apos => '\'',
                };
                write_idx += 1;
                src = src[tag.len + 2 ..];
                continue :scan .move;
            } else if (tag.len > 1 and tag[0] == '#') {
                const is_hex = tag[1] == 'x';
                if (is_hex and tag.len < 3) continue :scan .fallback;

                const raw_code = tag[if (is_hex) 2 else 1..];
                const code = std.fmt.parseInt(u21, raw_code, if (is_hex) 16 else 10) catch continue :scan .fallback;

                var code_buf: [4]u8 = undefined;
                const code_len = std.unicode.utf8Encode(code, &code_buf) catch continue :scan .fallback;

                @memcpy(raw_content[write_idx .. write_idx + code_len], code_buf[0..code_len]);
                src = src[tag.len + 2 ..];
                write_idx += code_len;
                continue :scan .move;
            }
            continue :scan .fallback;
        },
        .fallback => {
            raw_content[write_idx] = src[0];
            src = src[1..];
            write_idx += 1;
            continue :scan .move;
        },
    }

    return write_idx;
}

const std = @import("std");
const mod = @import("model.zig");

const Config = @import("Config.zig");
