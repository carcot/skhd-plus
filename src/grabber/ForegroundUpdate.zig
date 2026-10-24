const std = @import("std");
const BundleId = @import("BundleId.zig");

pub const max_frame_bytes: usize = 4096;
pub const max_app_id_bytes: usize = BundleId.max_bytes;

pub const Update = struct {
    total_bytes: usize,
    app_id: [max_app_id_bytes]u8 = undefined,
    app_id_len: usize = 0,

    pub fn bundleId(self: *const Update) ?[]const u8 {
        if (self.app_id_len == 0) return null;
        return self.app_id[0..self.app_id_len];
    }
};

pub const validBundleId = BundleId.valid;

pub fn decode(allocator: std.mem.Allocator, buffer: []const u8) !?Update {
    if (buffer.len < 4) return null;
    const body_len = std.mem.readInt(u32, buffer[0..4], .big);
    if (body_len == 0 or body_len > max_frame_bytes - 4) return error.InvalidFrameLength;
    const total_len = 4 + @as(usize, body_len);
    if (buffer.len < total_len) return null;

    const Message = struct { type: []const u8, app_id: ?[]const u8 = null };
    var parsed = try std.json.parseFromSlice(Message, allocator, buffer[4..total_len], .{ .ignore_unknown_fields = false });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.type, "foreground_app")) return error.UnexpectedMessage;

    var update: Update = .{ .total_bytes = total_len };
    if (parsed.value.app_id) |id| {
        if (validBundleId(id)) {
            @memcpy(update.app_id[0..id.len], id);
            update.app_id_len = id.len;
        }
    }
    return update;
}

test "foreground update handles partial and consecutive frames" {
    const first = "{\"type\":\"foreground_app\",\"app_id\":\"com.mitchellh.ghostty\"}";
    const second = "{\"type\":\"foreground_app\",\"app_id\":null}";
    var buffer: [256]u8 = undefined;
    std.mem.writeInt(u32, buffer[0..4], first.len, .big);
    @memcpy(buffer[4 .. 4 + first.len], first);
    const first_end = 4 + first.len;
    std.mem.writeInt(u32, buffer[first_end..][0..4], second.len, .big);
    @memcpy(buffer[first_end + 4 .. first_end + 4 + second.len], second);

    for (0..first_end) |end| try std.testing.expect((try decode(std.testing.allocator, buffer[0..end])) == null);
    const first_update = (try decode(std.testing.allocator, buffer[0 .. first_end + 4 + second.len])).?;
    try std.testing.expectEqualStrings("com.mitchellh.ghostty", first_update.bundleId().?);
    const second_update = (try decode(std.testing.allocator, buffer[first_update.total_bytes .. first_end + 4 + second.len])).?;
    try std.testing.expect(second_update.bundleId() == null);
}

test "invalid identity fails open and invalid frame fails closed" {
    try std.testing.expect(!validBundleId("com.example with space"));
    try std.testing.expect(!validBundleId(""));
    try std.testing.expect(validBundleId("org.gnu.Emacs"));
    try std.testing.expectError(error.InvalidFrameLength, decode(std.testing.allocator, &.{ 0, 0, 0, 0 }));
    const body = "{\"type\":\"unexpected\"}";
    var buffer: [64]u8 = undefined;
    std.mem.writeInt(u32, buffer[0..4], body.len, .big);
    @memcpy(buffer[4 .. 4 + body.len], body);
    try std.testing.expectError(error.UnexpectedMessage, decode(std.testing.allocator, buffer[0 .. 4 + body.len]));
}
