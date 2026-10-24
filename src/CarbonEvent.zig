const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");

const CarbonEvent = @This();
const log = std.log.scoped(.carbon_event);
pub const ChangeCallback = *const fn (ctx: ?*anyopaque, app_id: ?[]const u8) void;

allocator: std.mem.Allocator,
io: std.Io,
handler_ref: c.EventHandlerRef,
event_type: c.EventTypeSpec,
process_buffer: [512]u8 = undefined,
buffer_len: usize = 0,
bundle_buffer: [512]u8 = undefined,
bundle_len: usize = 0,
on_change: ?ChangeCallback = null,
on_change_ctx: ?*anyopaque = null,
mutex: std.Io.Mutex = .init,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !*CarbonEvent {
    const self = try allocator.create(CarbonEvent);
    errdefer allocator.destroy(self);

    self.* = CarbonEvent{
        .allocator = allocator,
        .io = io,
        .handler_ref = undefined,
        .event_type = .{
            .eventClass = c.kEventClassApplication,
            .eventKind = c.kEventAppFrontSwitched,
        },
    };

    // GetFrontProcess + InstallApplicationEventHandler trip TCC's
    // Accessibility prompt on Tahoe for unsigned binaries — every test
    // binary that pulls Skhd.init in transitively would pop the dialog
    // on each rebuild. Skip both under tests; getProcessName() falls back
    // to "unknown", which test configs don't assert against.
    if (builtin.is_test) return self;

    // Get initial process name from the OS — no event payload yet.
    var initial_psn: c.ProcessSerialNumber = undefined;
    if (c.GetFrontProcess(&initial_psn) == c.noErr) {
        self.updateProcessNameFromPsn(&initial_psn);
    }

    // Install event handler
    const status = c.InstallApplicationEventHandler(
        carbonEventHandler,
        1,
        @ptrCast(&self.event_type),
        self,
        &self.handler_ref,
    );

    if (status != c.noErr) {
        return error.CarbonEventInitFailed;
    }

    return self;
}

pub fn deinit(self: *CarbonEvent) void {
    // Mirror the test-mode short-circuit in init() — handler was never
    // installed, so handler_ref is undefined and RemoveEventHandler
    // would dereference garbage.
    if (!builtin.is_test) {
        _ = c.RemoveEventHandler(self.handler_ref);
    }

    // Free self
    self.allocator.destroy(self);
}

/// Get the cached process name (thread-safe)
pub fn getProcessName(self: *CarbonEvent) []const u8 {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    // Return "unknown" if we don't have a process name
    if (self.buffer_len == 0) {
        return "unknown";
    }
    return self.process_buffer[0..self.buffer_len];
}

pub fn getBundleId(self: *CarbonEvent) ?[]const u8 {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (self.bundle_len == 0) return null;
    return self.bundle_buffer[0..self.bundle_len];
}

fn bundleIdFromPsn(psn: *const c.ProcessSerialNumber, buffer: *[512]u8) usize {
    var pid: c.pid_t = 0;
    if (c.GetProcessPID(psn, &pid) != c.noErr or pid <= 0) return 0;
    const pool = c.objc_autoreleasePoolPush();
    defer c.objc_autoreleasePoolPop(pool);
    const app_class = c.objc_getClass("NSRunningApplication") orelse return 0;
    const running_sel = c.sel_registerName("runningApplicationWithProcessIdentifier:");
    const sendPid = @extern(*const fn (c.id, c.SEL, c.pid_t) callconv(.c) c.id, .{ .name = "objc_msgSend" });
    const app = sendPid(app_class, running_sel, pid) orelse return 0;
    const sendObject = @extern(*const fn (c.id, c.SEL) callconv(.c) c.id, .{ .name = "objc_msgSend" });
    const bundle = sendObject(app, c.sel_registerName("bundleIdentifier")) orelse return 0;
    const sendString = @extern(*const fn (c.id, c.SEL) callconv(.c) ?[*:0]const u8, .{ .name = "objc_msgSend" });
    const utf8 = sendString(bundle, c.sel_registerName("UTF8String")) orelse return 0;
    const bytes = std.mem.span(utf8);
    if (bytes.len == 0 or bytes.len > buffer.len) return 0;
    @memcpy(buffer[0..bytes.len], bytes);
    return bytes.len;
}

/// Update the cached process name from a PSN (thread-safe).
fn updateProcessNameFromPsn(self: *CarbonEvent, psn: *const c.ProcessSerialNumber) void {
    self.mutex.lockUncancelable(self.io);
    self.bundle_len = bundleIdFromPsn(psn, &self.bundle_buffer);

    var ref: c.CFStringRef = undefined;
    if (c.CopyProcessName(psn, &ref) == c.noErr) {
        defer c.CFRelease(ref);
        const success = c.CFStringGetCString(
            ref,
            &self.process_buffer,
            self.process_buffer.len,
            c.kCFStringEncodingUTF8,
        );
        if (success != 0) {
            self.buffer_len = std.mem.len(@as([*:0]const u8, @ptrCast(&self.process_buffer)));
            for (self.process_buffer[0..self.buffer_len]) |*char| {
                char.* = std.ascii.toLower(char.*);
            }
        } else {
            self.buffer_len = 0;
        }
    } else {
        self.buffer_len = 0;
    }
    self.mutex.unlock(self.io);
    if (self.on_change) |callback| callback(self.on_change_ctx, self.getBundleId());
}

/// Carbon event handler callback. The new frontmost PSN comes from the
/// event payload — calling GetFrontProcess() here is racy and can return
/// the previous front app.
fn carbonEventHandler(
    _: c.EventHandlerCallRef,
    event: c.EventRef,
    user_data: ?*anyopaque,
) callconv(.c) c.OSStatus {
    if (user_data) |data| {
        const self = @as(*CarbonEvent, @ptrCast(@alignCast(data)));
        var psn: c.ProcessSerialNumber = undefined;
        const status = c.GetEventParameter(
            event,
            c.kEventParamProcessID,
            c.typeProcessSerialNumber,
            null,
            @sizeOf(c.ProcessSerialNumber),
            null,
            &psn,
        );
        if (status != c.noErr) {
            log.err("kEventAppFrontSwitched without process PSN: status={d}", .{status});
            return status;
        }
        self.updateProcessNameFromPsn(&psn);
    }

    return c.noErr;
}

test "bundle ID cache returns unknown or exact identifier" {
    const event = try CarbonEvent.init(std.testing.allocator, std.testing.io);
    defer event.deinit();
    try std.testing.expect(event.getBundleId() == null);
    const bundle_id = "com.mitchellh.ghostty";
    @memcpy(event.bundle_buffer[0..bundle_id.len], bundle_id);
    event.bundle_len = bundle_id.len;
    try std.testing.expectEqualStrings(bundle_id, event.getBundleId().?);
}
