const std = @import("std");

pub const max_payload_bytes: usize = 1024;
pub const max_body_bytes: usize = 1 + 8 + max_payload_bytes;
pub const client_protocol_version: u16 = 7;

pub const MessageType = enum(u8) {
    heartbeat = 0,
    user_data = 1,
    health_check = 2,
    health_check_response = 3,
    request = 4,
    response = 5,
    _,
};

pub const Frame = struct {
    message_type: MessageType,
    request_id: ?u64,
    payload: []const u8,
    total_bytes: usize,
};

pub fn encodeFrame(buffer: []u8, message_type: MessageType, request_id: ?u64, payload: []const u8) ![]const u8 {
    const has_id = message_type == .request or message_type == .response;
    if (has_id != (request_id != null)) return error.InvalidRequestId;
    const body_len = 1 + @as(usize, if (has_id) 8 else 0) + payload.len;
    if (body_len > max_body_bytes) return error.FrameTooLarge;
    const total_len = 4 + body_len;
    if (buffer.len < total_len) return error.BufferTooSmall;

    std.mem.writeInt(u32, buffer[0..4], @intCast(body_len), .big);
    buffer[4] = @intFromEnum(message_type);
    const payload_start: usize = if (has_id) 13 else 5;
    if (request_id) |identifier| std.mem.writeInt(u64, buffer[5..13], identifier, .big);
    @memcpy(buffer[payload_start..total_len], payload);
    return buffer[0..total_len];
}

pub fn encodeDriverRequest(buffer: []u8, request_id: u64, request: u8, payload: []const u8) ![]const u8 {
    var body: [max_body_bytes]u8 = undefined;
    if (payload.len > max_payload_bytes - 3) return error.FrameTooLarge;
    std.mem.writeInt(u16, body[0..2], client_protocol_version, .little);
    body[2] = request;
    @memcpy(body[3 .. 3 + payload.len], payload);
    return encodeFrame(buffer, .request, request_id, body[0 .. 3 + payload.len]);
}

pub fn decodeFrame(buffer: []const u8) !?Frame {
    if (buffer.len < 4) return null;
    const body_len = std.mem.readInt(u32, buffer[0..4], .big);
    if (body_len == 0) return error.MalformedFrame;
    if (body_len > max_body_bytes) return error.FrameTooLarge;
    const total_len = 4 + @as(usize, body_len);
    if (buffer.len < total_len) return null;

    const message_type: MessageType = @enumFromInt(buffer[4]);
    const has_id = message_type == .request or message_type == .response;
    if (has_id and body_len < 9) return error.MalformedFrame;
    const payload_start: usize = if (has_id) 13 else 5;
    return .{
        .message_type = message_type,
        .request_id = if (has_id) std.mem.readInt(u64, buffer[5..13], .big) else null,
        .payload = buffer[payload_start..total_len],
        .total_bytes = total_len,
    };
}

fn setSendTimeout(fd: std.posix.fd_t) !void {
    const send_timeout: std.posix.timeval = .{ .sec = 0, .usec = 500_000 };
    if (std.c.setsockopt(fd, std.c.SOL.SOCKET, std.c.SO.SNDTIMEO, std.mem.asBytes(&send_timeout).ptr, @sizeOf(std.posix.timeval)) != 0) return error.SetSockOptFailed;
}

pub const Socket = struct {
    fd: std.posix.fd_t,
    incoming: [4 + max_body_bytes]u8 = undefined,
    incoming_len: usize = 0,
    pending_consume: usize = 0,
    next_request_id: u64 = 0,

    pub fn connect() !Socket {
        const fd = std.c.socket(std.c.AF.UNIX, std.c.SOCK.STREAM, 0);
        if (fd < 0) return error.SocketFailed;
        errdefer _ = std.c.close(fd);
        _ = std.c.fcntl(fd, std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC));
        const no_sigpipe: c_int = 1;
        if (std.c.setsockopt(fd, std.c.SOL.SOCKET, std.c.SO.NOSIGPIPE, std.mem.asBytes(&no_sigpipe).ptr, @sizeOf(c_int)) != 0) return error.SetSockOptFailed;
        try setSendTimeout(fd);

        var address: std.posix.sockaddr.un = .{
            .family = std.posix.AF.UNIX,
            .path = @splat(0),
        };
        const path = "/Library/Application Support/org.pqrs/tmp/rootonly/karabiner_virtual_hid_device_service.sock";
        if (path.len >= address.path.len) return error.PathTooLong;
        @memcpy(address.path[0..path.len], path);
        if (std.c.connect(fd, @ptrCast(&address), @sizeOf(@TypeOf(address))) != 0) return error.ConnectFailed;
        return .{ .fd = fd };
    }

    pub fn close(self: *Socket) void {
        _ = std.c.close(self.fd);
        self.* = undefined;
    }

    pub fn sendDriverRequest(self: *Socket, request: u8, payload: []const u8) !u64 {
        self.next_request_id += 1;
        var buffer: [4 + max_body_bytes]u8 = undefined;
        const frame = try encodeDriverRequest(&buffer, self.next_request_id, request, payload);
        try self.sendAll(frame);
        return self.next_request_id;
    }

    pub fn sendHeartbeat(self: *Socket) !void {
        try self.sendSimple(.heartbeat, null);
    }

    pub fn sendResponse(self: *Socket, request_id: u64) !void {
        try self.sendSimple(.response, request_id);
    }

    fn sendSimple(self: *Socket, message_type: MessageType, request_id: ?u64) !void {
        var buffer: [16]u8 = undefined;
        const frame = try encodeFrame(&buffer, message_type, request_id, &.{});
        try self.sendAll(frame);
    }

    fn sendAll(self: *Socket, frame: []const u8) !void {
        var sent_total: usize = 0;
        while (sent_total < frame.len) {
            const sent = std.c.send(self.fd, frame[sent_total..].ptr, frame.len - sent_total, 0);
            if (sent <= 0) return error.SendFailed;
            sent_total += @intCast(sent);
        }
    }

    pub fn receive(self: *Socket, nonblocking: bool) !?Frame {
        if (self.pending_consume > 0) {
            const remaining = self.incoming_len - self.pending_consume;
            std.mem.copyForwards(u8, self.incoming[0..remaining], self.incoming[self.pending_consume..self.incoming_len]);
            self.incoming_len = remaining;
            self.pending_consume = 0;
        }

        while (true) {
            if (try decodeFrame(self.incoming[0..self.incoming_len])) |frame| {
                self.pending_consume = frame.total_bytes;
                return frame;
            }
            if (self.incoming_len == self.incoming.len) return error.FrameTooLarge;
            const flags: c_int = if (nonblocking) std.c.MSG.DONTWAIT else 0;
            const received = std.c.recv(self.fd, self.incoming[self.incoming_len..].ptr, self.incoming.len - self.incoming_len, flags);
            if (received < 0) {
                if (std.c.errno(@as(c_int, @intCast(received))) == .AGAIN) return null;
                return error.RecvFailed;
            }
            if (received == 0) return error.EndOfStream;
            self.incoming_len += @intCast(received);
        }
    }
};

test "socket send timeout is bounded" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    defer _ = std.c.close(descriptors[0]);
    defer _ = std.c.close(descriptors[1]);

    try setSendTimeout(descriptors[0]);
    var actual: std.posix.timeval = undefined;
    var actual_len: std.c.socklen_t = @sizeOf(std.posix.timeval);
    try std.testing.expectEqual(@as(c_int, 0), std.c.getsockopt(descriptors[0], std.c.SOL.SOCKET, std.c.SO.SNDTIMEO, &actual, &actual_len));
    try std.testing.expectEqual(@as(@TypeOf(actual_len), @sizeOf(std.posix.timeval)), actual_len);
    try std.testing.expectEqual(@as(@TypeOf(actual.sec), 0), actual.sec);
    try std.testing.expectEqual(@as(@TypeOf(actual.usec), 500_000), actual.usec);
}

test "driver request matches DriverKit v8 stream framing" {
    var buffer: [64]u8 = undefined;
    const bytes = try encodeDriverRequest(&buffer, 0x0102030405060708, 6, &.{ 0xaa, 0xbb });
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 14, 4, 1, 2, 3, 4, 5, 6, 7, 8, 7, 0, 6, 0xaa, 0xbb }, bytes);
    const decoded = (try decodeFrame(bytes)).?;
    try std.testing.expectEqual(MessageType.request, decoded.message_type);
    try std.testing.expectEqual(@as(?u64, 0x0102030405060708), decoded.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 6, 0xaa, 0xbb }, decoded.payload);
}

test "decode waits for a complete stream frame" {
    var buffer: [32]u8 = undefined;
    const bytes = try encodeFrame(&buffer, .response, 23, &.{ 4, 1 });
    for (0..bytes.len) |end| try std.testing.expect((try decodeFrame(bytes[0..end])) == null);
    const decoded = (try decodeFrame(bytes)).?;
    try std.testing.expectEqual(@as(?u64, 23), decoded.request_id);
    try std.testing.expectEqual(bytes.len, decoded.total_bytes);
}

test "heartbeat and malformed frames" {
    var buffer: [8]u8 = undefined;
    const bytes = try encodeFrame(&buffer, .heartbeat, null, &.{});
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 1, 0 }, bytes);
    const decoded = (try decodeFrame(bytes)).?;
    try std.testing.expectEqual(MessageType.heartbeat, decoded.message_type);
    try std.testing.expectEqual(@as(?u64, null), decoded.request_id);
    try std.testing.expectError(error.InvalidRequestId, encodeFrame(&buffer, .request, null, &.{}));
    try std.testing.expectError(error.MalformedFrame, decodeFrame(&.{ 0, 0, 0, 0 }));
    try std.testing.expectError(error.MalformedFrame, decodeFrame(&.{ 0, 0, 0, 1, 4 }));
}

test "socket buffers partial frames and sends requests" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    var socket: Socket = .{ .fd = descriptors[0] };
    defer socket.close();
    defer _ = std.c.close(descriptors[1]);

    var buffer: [32]u8 = undefined;
    const frame = try encodeFrame(&buffer, .heartbeat, null, &.{});
    try std.testing.expectEqual(@as(isize, 2), std.c.send(descriptors[1], frame.ptr, 2, 0));
    try std.testing.expect((try socket.receive(true)) == null);
    try std.testing.expectEqual(@as(isize, 3), std.c.send(descriptors[1], frame[2..].ptr, 3, 0));
    try std.testing.expectEqual(MessageType.heartbeat, (try socket.receive(true)).?.message_type);

    const request_id = try socket.sendDriverRequest(6, &.{0xaa});
    try std.testing.expectEqual(@as(u64, 1), request_id);
    var received: [32]u8 = undefined;
    const received_len = std.c.recv(descriptors[1], &received, received.len, 0);
    try std.testing.expect(received_len > 0);
    const request = (try decodeFrame(received[0..@intCast(received_len)])).?;
    try std.testing.expectEqual(MessageType.request, request.message_type);
    try std.testing.expectEqual(@as(?u64, 1), request.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 7, 0, 6, 0xaa }, request.payload);
}

test "socket preserves consecutive frames from one read" {
    var descriptors: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &descriptors));
    var socket: Socket = .{ .fd = descriptors[0] };
    defer socket.close();
    defer _ = std.c.close(descriptors[1]);

    var buffer: [32]u8 = undefined;
    const first = try encodeFrame(buffer[0..], .heartbeat, null, &.{});
    const first_len = first.len;
    const second = try encodeFrame(buffer[first_len..], .response, 9, &.{ 4, 1 });
    const total_len = first_len + second.len;
    try std.testing.expectEqual(@as(isize, @intCast(total_len)), std.c.send(descriptors[1], &buffer, total_len, 0));

    const received_first = (try socket.receive(true)).?;
    try std.testing.expectEqual(MessageType.heartbeat, received_first.message_type);
    const received_second = (try socket.receive(true)).?;
    try std.testing.expectEqual(MessageType.response, received_second.message_type);
    try std.testing.expectEqual(@as(?u64, 9), received_second.request_id);
    try std.testing.expectEqualSlices(u8, &.{ 4, 1 }, received_second.payload);
    try std.testing.expect((try socket.receive(true)) == null);
}
