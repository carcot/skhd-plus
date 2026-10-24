const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Stream = @import("VhiddStream.zig");

const log = std.log.scoped(.vhidd);

/// Vhidd recovery backoff bounds. After a transport failure, the
/// grabber retries reconnect on this schedule: first attempt fires
/// immediately, then each failed attempt doubles the wait until it
/// caps at `recovery_backoff_max_ms`. Matches Karabiner's 1s
/// reconnect baseline.
pub const recovery_backoff_initial_ms: u32 = 1000;
pub const recovery_backoff_max_ms: u32 = 10_000;

/// Progress the backoff one step. Pure helper so the recovery state
/// machine is testable without spinning up CFRunLoop timers.
pub fn nextBackoffMs(current: u32) u32 {
    const next = if (current == 0) recovery_backoff_initial_ms else current * 2;
    return @min(next, recovery_backoff_max_ms);
}

/// Whether a failed `Client.postKeyboardReport` (or sibling) means the
/// transport is dead and we should tear down the seize + reconnect.
///
/// Default-true: a post that didn't go through leaves the pipe in an
/// unknown state, so we treat *any* error as transport-fatal — the
/// exact errno the OS surfaces varies (`SendFailed`, `ShortWrite`,
/// `ConnectionResetByPeer` when the Karabiner daemon closes the socket,
/// `BrokenPipe`, `Unexpected`, …) and an over-narrow allowlist is what
/// let the grabber keep the keyboard seized while every replay was
/// silently dropped. The only exclusions are our-side logic bugs that a
/// reconnect cannot fix: a malformed/oversized report would otherwise
/// drive an endless recover loop.
pub fn isTransportError(err: anyerror) bool {
    return switch (err) {
        error.PayloadTooLarge, error.TooManyKeys => false,
        else => true,
    };
}

/// `pqrs::karabiner::driverkit::virtual_hid_device_service::request`.
pub const Request = enum(u8) {
    virtual_hid_keyboard_initialize = 0,
    virtual_hid_keyboard_terminate = 1,
    virtual_hid_keyboard_reset = 2,
    virtual_hid_pointing_initialize = 3,
    virtual_hid_pointing_terminate = 4,
    virtual_hid_pointing_reset = 5,
    post_keyboard_input_report = 6,
    post_consumer_input_report = 7,
    post_apple_vendor_keyboard_input_report = 8,
    post_apple_vendor_top_case_input_report = 9,
    post_generic_desktop_input_report = 10,
    post_pointing_input_report = 11,
};

/// `pqrs::karabiner::driverkit::virtual_hid_device_service::response`.
pub const Response = enum(u8) {
    none = 0,
    driver_activated = 1,
    driver_connected = 2,
    driver_version_mismatched = 3,
    virtual_hid_keyboard_ready = 4,
    virtual_hid_pointing_ready = 5,
    _,
};

/// Modifier byte layout for `keyboard_input.modifiers`. Bit values
/// match HID Usage Page 0x07 modifier semantics.
pub const Modifier = packed struct(u8) {
    left_control: bool = false,
    left_shift: bool = false,
    left_option: bool = false,
    left_command: bool = false,
    right_control: bool = false,
    right_shift: bool = false,
    right_option: bool = false,
    right_command: bool = false,
};

/// vhidd `virtual_hid_keyboard_parameters`. Byte-level layout matches
/// `__attribute__((packed))` in C++ (3 × u64 LE = 24 bytes).
pub const KeyboardParameters = struct {
    vendor_id: u64 = 0x05ac,
    product_id: u64 = 0x024f,
    /// HID Usage Page 0x07 country code; 0 = "not supported".
    country_code: u64 = 0,
};

pub const Client = struct {
    socket: Stream.Socket,
    fd: posix.fd_t,

    pub fn connect(allocator: std.mem.Allocator, io: std.Io) !Client {
        _ = allocator;
        _ = io;
        const socket = try Stream.Socket.connect();
        return .{ .socket = socket, .fd = socket.fd };
    }

    pub fn close(self: *Client) void {
        self.socket.close();
        self.* = undefined;
    }

    /// Send a vhidd request with no payload.
    pub fn sendRequest(self: *Client, req: Request) !void {
        _ = try self.socket.sendDriverRequest(@intFromEnum(req), &.{});
    }

    /// Send a vhidd request with a fixed-size payload appended.
    pub fn sendRequestWithPayload(self: *Client, req: Request, payload: []const u8) !void {
        _ = try self.socket.sendDriverRequest(@intFromEnum(req), payload);
    }

    /// Send a `virtual_hid_keyboard_initialize` request with the given
    /// (vendor, product, country) tuple.
    pub fn initializeKeyboard(self: *Client, params: KeyboardParameters) !void {
        var payload: [24]u8 = undefined;
        std.mem.writeInt(u64, payload[0..8], params.vendor_id, .little);
        std.mem.writeInt(u64, payload[8..16], params.product_id, .little);
        std.mem.writeInt(u64, payload[16..24], params.country_code, .little);
        try self.sendRequestWithPayload(.virtual_hid_keyboard_initialize, &payload);
    }

    /// Send a `post_keyboard_input_report` with the 67-byte report.
    pub fn postKeyboardReport(self: *Client, modifiers: Modifier, keys: []const u16) !void {
        if (keys.len > 32) return error.TooManyKeys;
        var report: [67]u8 = @splat(0);
        report[0] = 1; // report_id
        report[1] = @bitCast(modifiers);
        report[2] = 0; // reserved
        for (keys, 0..) |k, i| {
            std.mem.writeInt(u16, report[3 + i * 2 ..][0..2], k, .little);
        }
        try self.sendRequestWithPayload(.post_keyboard_input_report, &report);
    }

    /// Reports for non-keyboard pages share an identical shape:
    ///   [u8 report_id][32 × u16 le keys] = 65 bytes
    /// Differs from the keyboard report only by report_id and the
    /// driver-side request that carries it.
    fn postKeysReport(
        self: *Client,
        request: Request,
        report_id: u8,
        keys: []const u16,
    ) !void {
        if (keys.len > 32) return error.TooManyKeys;
        var report: [65]u8 = @splat(0);
        report[0] = report_id;
        for (keys, 0..) |k, i| {
            std.mem.writeInt(u16, report[1 + i * 2 ..][0..2], k, .little);
        }
        try self.sendRequestWithPayload(request, &report);
    }

    /// Consumer page (HID 0x0C) report — volume, play/pause, mute, etc.
    /// On Apple keyboards in the default F-row mode (the "Use F1, F2…
    /// as standard function keys" setting OFF), the F-row keys emit on
    /// this page.
    pub fn postConsumerReport(self: *Client, keys: []const u16) !void {
        try self.postKeysReport(.post_consumer_input_report, 2, keys);
    }

    /// Apple Vendor Top Case page (HID 0xFF). Brightness up/down, the
    /// fn key state, and a few other Apple-specific keys.
    pub fn postAppleVendorTopCaseReport(self: *Client, keys: []const u16) !void {
        try self.postKeysReport(.post_apple_vendor_top_case_input_report, 3, keys);
    }

    /// Apple Vendor Keyboard page (HID 0xFF01). Spotlight, mission
    /// control, dictation, etc. on modern MacBooks.
    pub fn postAppleVendorKeyboardReport(self: *Client, keys: []const u16) !void {
        try self.postKeysReport(.post_apple_vendor_keyboard_input_report, 4, keys);
    }

    /// Generic Desktop page (HID 0x01). Used for `do_not_disturb`
    /// (usage 0x9B) — F6 on modern MacBooks.
    pub fn postGenericDesktopReport(self: *Client, keys: []const u16) !void {
        try self.postKeysReport(.post_generic_desktop_input_report, 7, keys);
    }

    /// Block until the given vhidd response arrives with body byte
    /// non-zero (`true`), or the timeout expires.
    ///
    /// The DriverKit boot is async: after `virtual_hid_keyboard_initialize`,
    /// the server sends `virtual_hid_keyboard_ready=false` once, then
    /// keeps sending status updates as the kernel finishes wiring up
    /// the virtual device. We're only interested in the eventual
    /// `true` arrival. Heartbeats and non-matching responses are
    /// silently consumed.
    pub fn waitForBoolTrue(self: *Client, want: Response, timeout_ms: u32) !void {
        const deadline_ms = nowMillis() + @as(i64, @intCast(timeout_ms));
        while (true) {
            const remaining = deadline_ms - nowMillis();
            if (remaining <= 0) return error.Timeout;

            try setRecvTimeout(self.fd, @intCast(remaining));
            const incoming = (try self.socket.receive(false)) orelse return error.Timeout;
            if (incoming.message_type == .request) try self.socket.sendResponse(incoming.request_id.?);
            if (incoming.message_type == .heartbeat) try self.socket.sendHeartbeat();
            const payload = incoming.payload;
            if (incoming.message_type != .request and incoming.message_type != .response) continue;
            var offset: usize = 0;
            while (offset + 1 < payload.len) : (offset += 2) {
                if (payload[offset] == @intFromEnum(Response.driver_version_mismatched) and payload[offset + 1] != 0) return error.DriverVersionMismatch;
                if (payload[offset] == @intFromEnum(want) and payload[offset + 1] != 0) return;
            }
        }
    }

    pub fn receive(self: *Client) !?Stream.Frame {
        return self.socket.receive(true);
    }

    pub fn sendHeartbeat(self: *Client) !void {
        try self.socket.sendHeartbeat();
    }

    pub fn sendResponse(self: *Client, request_id: u64) !void {
        try self.socket.sendResponse(request_id);
    }
};

/// `clock_gettime(REALTIME)` in milliseconds. std.time.milliTimestamp
/// was removed in Zig 0.16.
fn nowMillis() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @as(i64, @intCast(ts.sec)) * std.time.ms_per_s +
        @divFloor(@as(i64, @intCast(ts.nsec)), std.time.ns_per_ms);
}

fn setRecvTimeout(fd: posix.fd_t, ms: u32) !void {
    const tv: posix.timeval = .{
        .sec = @intCast(ms / 1000),
        .usec = @intCast((ms % 1000) * 1000),
    };
    if (std.c.setsockopt(fd, std.c.SOL.SOCKET, std.c.SO.RCVTIMEO, std.mem.asBytes(&tv).ptr, @sizeOf(@TypeOf(tv))) != 0) {
        return error.SetSockOptFailed;
    }
}

test "nextBackoffMs grows from 0 → initial → 2× → cap" {
    try std.testing.expectEqual(@as(u32, 1000), nextBackoffMs(0));
    try std.testing.expectEqual(@as(u32, 2000), nextBackoffMs(1000));
    try std.testing.expectEqual(@as(u32, 4000), nextBackoffMs(2000));
    try std.testing.expectEqual(@as(u32, 8000), nextBackoffMs(4000));
    try std.testing.expectEqual(@as(u32, 10_000), nextBackoffMs(8000));
    try std.testing.expectEqual(@as(u32, 10_000), nextBackoffMs(10_000));
}

test "isTransportError treats any post error as transport-fatal except our-side logic bugs" {
    // A failed post means the pipe is unusable — reconnect, regardless
    // of which errno the OS surfaced. The original list was too narrow:
    // `ConnectionResetByPeer` (Karabiner daemon closed the socket) and
    // friends slipped through, so `markVhiddBroken` never fired and the
    // grabber kept the keyboard seized while every replay was dropped.
    try std.testing.expect(isTransportError(error.SendFailed));
    try std.testing.expect(isTransportError(error.ShortWrite));
    try std.testing.expect(isTransportError(error.ConnectionResetByPeer));
    try std.testing.expect(isTransportError(error.BrokenPipe));
    try std.testing.expect(isTransportError(error.Unexpected));

    // Our-side logic bugs: a reconnect can't fix a malformed report, so
    // these must NOT trigger an endless recover loop.
    try std.testing.expect(!isTransportError(error.PayloadTooLarge));
    try std.testing.expect(!isTransportError(error.TooManyKeys));
}

test "Modifier packs to 8 bits matching Karabiner enum" {
    const m = Modifier{ .left_control = true, .right_command = true };
    const byte: u8 = @bitCast(m);
    // bit 0 (left_control) | bit 7 (right_command) = 0b10000001 = 0x81
    try std.testing.expectEqual(@as(u8, 0x81), byte);
}

test "v8 client sends keyboard initialize and accepts ready response" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    var client: Client = .{ .socket = .{ .fd = descriptors[0] }, .fd = descriptors[0] };
    defer client.close();
    defer _ = std.c.close(descriptors[1]);

    var response_storage: [32]u8 = undefined;
    const response = try Stream.encodeFrame(&response_storage, .response, 1, &.{ 4, 1 });
    try std.testing.expectEqual(@as(isize, @intCast(response.len)), std.c.send(descriptors[1], response.ptr, response.len, 0));

    try client.initializeKeyboard(.{});
    try client.waitForBoolTrue(.virtual_hid_keyboard_ready, 1000);

    var request_storage: [64]u8 = undefined;
    const received = std.c.recv(descriptors[1], &request_storage, request_storage.len, 0);
    try std.testing.expect(received > 0);
    const request = (try Stream.decodeFrame(request_storage[0..@intCast(received)])).?;
    try std.testing.expectEqual(Stream.MessageType.request, request.message_type);
    try std.testing.expectEqual(@as(?u64, 1), request.request_id);
    try std.testing.expectEqual(@as(usize, 27), request.payload.len);
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 0 }, request.payload[0..3]);
    try std.testing.expectEqual(@as(u64, 0x05ac), std.mem.readInt(u64, request.payload[3..11], .little));
    try std.testing.expectEqual(@as(u64, 0x024f), std.mem.readInt(u64, request.payload[11..19], .little));
}

test "v8 client rejects driver version mismatch" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    var client: Client = .{ .socket = .{ .fd = descriptors[0] }, .fd = descriptors[0] };
    defer client.close();
    defer _ = std.c.close(descriptors[1]);

    var response_storage: [32]u8 = undefined;
    const response = try Stream.encodeFrame(&response_storage, .response, 1, &.{ 3, 1 });
    try std.testing.expectEqual(@as(isize, @intCast(response.len)), std.c.send(descriptors[1], response.ptr, response.len, 0));
    try std.testing.expectError(error.DriverVersionMismatch, client.waitForBoolTrue(.virtual_hid_keyboard_ready, 1000));
}

test "v8 keyboard report matches DriverKit keyboard_input layout" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    var client: Client = .{ .socket = .{ .fd = descriptors[0] }, .fd = descriptors[0] };
    defer client.close();
    defer _ = std.c.close(descriptors[1]);

    try client.postKeyboardReport(.{ .right_shift = true }, &.{0x0004});

    var request_storage: [128]u8 = undefined;
    const received = std.c.recv(descriptors[1], &request_storage, request_storage.len, 0);
    try std.testing.expect(received > 0);
    const request = (try Stream.decodeFrame(request_storage[0..@intCast(received)])).?;
    try std.testing.expectEqual(@as(usize, 70), request.payload.len);
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 6, 1, 0x20, 0, 4, 0 }, request.payload[0..8]);
    for (request.payload[8..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}
