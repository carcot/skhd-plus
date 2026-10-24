//! Server-side handling of one IPC client session.
//!
//! Reads framed JSON messages, dispatches by `type`, writes back
//! `ok`/`error`/`warn` responses. Synchronous, single-threaded — D5
//! revisits this when per-uid lifecycle lands.

const std = @import("std");

const protocol = @import("grabber_protocol");
const ForegroundUpdate = @import("ForegroundUpdate.zig");

const log = std.log.scoped(.grabber_ipc);

/// This grabber's build version, returned in the hello-ok reply so
/// `skhd --status` can show the running grabber's version over IPC.
const grabber_version = std.mem.trimEnd(u8, @embedFile("VERSION"), "\n\r\t ");

/// Owned (deep-copied) rules and remaps from one apply_rules
/// message. Caller takes ownership and is responsible for freeing
/// each Rule's hold_layer slice plus the rules and remaps slices
/// themselves (see `freeApplied` below).
pub const AppliedRules = struct {
    uid: u32,
    rules: []protocol.Rule,
    remaps: []protocol.Remap,
    app_id: ?[]const u8 = null,
    /// Mirror of macOS's "Use F1, F2 … as standard function keys" pref
    /// (NSGlobalDomain `com.apple.keyboard.fnState`), read by the
    /// per-user agent and forwarded so the grabber can flip its F-row
    /// translation policy without doing a privileged prefs read itself.
    /// false = bare F-row → media keys (the OS default).
    fkeys_as_standard: bool = false,

    pub fn free(self: AppliedRules, allocator: std.mem.Allocator) void {
        for (self.rules) |r| {
            if (r.hold_layer) |l| allocator.free(l);
            if (r.app_id) |app_id| allocator.free(app_id);
        }
        allocator.free(self.rules);
        allocator.free(self.remaps);
        if (self.app_id) |app_id| allocator.free(app_id);
    }
};

/// Result of one client session.
pub const ServeResult = union(enum) {
    /// Client disconnected (sent bye, or closed) without leaving rules
    /// active. Caller should drop the connection.
    closed,
    /// Client sent apply_rules with at least one rule. Caller takes
    /// ownership of the parsed rules + remaps and the live socket;
    /// keeping the socket open lets the grabber detect agent death
    /// via EOS and tear down that subscription's rules.
    rules_applied: AppliedRules,
};

/// Single typed envelope for everything the agent can send. All
/// payload fields are optional so the same parse handles hello /
/// apply_rules / bye in one pass — `type` selects which fields the
/// handler consults. Slices borrow from the parse arena and must be
/// deep-copied if they need to outlive the parse.
const Inbound = struct {
    type: []const u8,
    uid: ?u32 = null,
    version: ?u32 = null,
    rules: ?[]const protocol.Rule = null,
    remaps: ?[]const protocol.Remap = null,
    app_id: ?[]const u8 = null,
    /// See AppliedRules.fkeys_as_standard. Optional so older agents
    /// (without the field) still parse — they get the OS default.
    fkeys_as_standard: ?bool = null,
};

pub fn serve(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, allow_app_scoped_rules: bool) !ServeResult {
    // Per-session state: the protocol expects hello first; record the
    // client uid for subsequent messages and reject anything else
    // before hello.
    var client_uid: ?u32 = null;

    // Match protocol.max_frame_bytes so the server accepts every frame
    // the shared protocol declares valid.
    var buf: [protocol.max_frame_bytes]u8 = undefined;

    var rbuf: [4096]u8 = undefined;
    var sr = stream.reader(io, &rbuf);
    var wbuf: [4096]u8 = undefined;
    var sw = stream.writer(io, &wbuf);

    while (true) {
        const n = protocol.readFrame(&sr.interface, &buf) catch |err| switch (err) {
            error.EndOfStream => return .closed, // peer closed; end of session
            else => return err,
        };

        var parsed = std.json.parseFromSlice(Inbound, allocator, buf[0..n], .{
            .ignore_unknown_fields = true,
        }) catch |err| {
            try sendError(allocator, &sw, "bad_json", @errorName(err));
            return err;
        };
        defer parsed.deinit();

        const msg = parsed.value;
        const kind = msg.type;

        if (std.mem.eql(u8, kind, "hello")) {
            client_uid = try handleHello(allocator, &sw, msg);
        } else if (std.mem.eql(u8, kind, "apply_rules")) {
            if (client_uid == null) {
                try sendError(allocator, &sw, "no_hello", "send hello before apply_rules");
                return error.ProtocolViolation;
            }
            const applied = try handleApplyRules(allocator, &sw, msg, client_uid.?, allow_app_scoped_rules);
            if (applied) |a| {
                // Hand the parsed rules back to the daemon along with
                // ownership of the connection. The daemon turns this
                // into a Subscription it can later GC when the socket
                // goes EOS.
                return .{ .rules_applied = a };
            }
            // Empty apply_rules clears the rule set. Continue
            // handling further messages on the same connection.
        } else if (std.mem.eql(u8, kind, "bye")) {
            try sendOk(allocator, &sw);
            return .closed;
        } else {
            try sendError(allocator, &sw, "unknown_type", kind);
            return error.UnknownMessageType;
        }
    }
}

fn handleHello(allocator: std.mem.Allocator, sw: *std.Io.net.Stream.Writer, msg: Inbound) !u32 {
    const uid = msg.uid orelse {
        try sendError(allocator, sw, "bad_hello", "missing 'uid'");
        return error.BadHello;
    };
    const version = msg.version orelse {
        try sendError(allocator, sw, "bad_hello", "missing 'version'");
        return error.BadHello;
    };
    if (version != protocol.protocol_version) {
        try sendError(allocator, sw, "version_mismatch", "agent and grabber differ on protocol version");
        return error.VersionMismatch;
    }
    log.info("hello from uid={d} version={d}", .{ uid, version });
    // Reply ok with our build version so the status path can read the
    // running grabber's version (extra field; older agents ignore it).
    try protocol.writeMessage(&sw.interface, allocator, .{ .type = "ok", .grabber_version = grabber_version });
    try sw.interface.flush();
    return uid;
}

/// Validate the apply_rules payload, deep-copy rules+remaps so they
/// outlive the parse arena, and return them as an `AppliedRules`. On
/// an empty payload (no rules, no remaps) returns null — the caller
/// keeps the connection open and waits for the next message.
fn handleApplyRules(
    allocator: std.mem.Allocator,
    sw: *std.Io.net.Stream.Writer,
    msg: Inbound,
    uid: u32,
    allow_app_scoped_rules: bool,
) !?AppliedRules {
    const rules = msg.rules orelse {
        try sendError(allocator, sw, "bad_apply", "missing 'rules'");
        return error.BadApply;
    };
    const remaps = msg.remaps orelse &[_]protocol.Remap{};

    validateRuntimeRules(rules, allow_app_scoped_rules) catch |err| {
        const code: []const u8 = if (err == error.AppScopedRulesUnsupported) "unsupported_rule" else "invalid_rule";
        try sendError(allocator, sw, code, @errorName(err));
        return err;
    };

    const fkeys_as_standard = msg.fkeys_as_standard orelse false;

    log.info("apply_rules uid={d} rules={d} remaps={d} fkeys_as_standard={}", .{ uid, rules.len, remaps.len, fkeys_as_standard });
    for (rules, 0..) |r, i| {
        log.info(
            "  rule[{d}]: src=0x{X:0>2} tap=0x{X:0>2} hold=0x{X:0>2} timeout={d}ms perm={} hokp={} retro={}",
            .{ i, r.src_usage, r.tap_usage, r.hold_usage, r.timeout_ms, r.permissive_hold, r.hold_on_other_key_press, r.retro_tap },
        );
        if (r.device) |d| {
            log.info("    device: vendor=0x{X:0>4} product=0x{X:0>4}", .{ d.vendor, d.product });
        }
    }
    for (remaps, 0..) |r, i| {
        log.info(
            "  remap[{d}]: src=0x{X:0>2} → dst=0x{X:0>2} on vendor=0x{X:0>4} product=0x{X:0>4}",
            .{ i, r.src_usage, r.dst_usage, r.device.vendor, r.device.product },
        );
    }

    if (rules.len == 0 and remaps.len == 0) {
        try sendOk(allocator, sw);
        return null;
    }

    // Deep-copy out of the JSON arena so the result outlives this
    // function. Caller frees via AppliedRules.free.
    const owned_rules = try allocator.alloc(protocol.Rule, rules.len);
    errdefer allocator.free(owned_rules);
    var i: usize = 0;
    errdefer while (i > 0) : (i -= 1) {
        if (owned_rules[i - 1].hold_layer) |l| allocator.free(l);
        if (owned_rules[i - 1].app_id) |app_id| allocator.free(app_id);
    };
    for (rules) |r| {
        var copy = r;
        if (r.hold_layer) |l| copy.hold_layer = try allocator.dupe(u8, l);
        if (r.app_id) |app_id| {
            copy.app_id = allocator.dupe(u8, app_id) catch |err| {
                if (copy.hold_layer) |l| allocator.free(l);
                return err;
            };
        }
        owned_rules[i] = copy;
        i += 1;
    }

    const owned_remaps = try allocator.alloc(protocol.Remap, remaps.len);
    errdefer allocator.free(owned_remaps);
    @memcpy(owned_remaps, remaps);

    const owned_app_id: ?[]const u8 = if (msg.app_id) |app_id|
        if (ForegroundUpdate.validBundleId(app_id)) try allocator.dupe(u8, app_id) else null
    else
        null;
    errdefer if (owned_app_id) |app_id| allocator.free(app_id);
    try sendOk(allocator, sw);

    return .{
        .uid = uid,
        .rules = owned_rules,
        .remaps = owned_remaps,
        .app_id = owned_app_id,
        .fkeys_as_standard = fkeys_as_standard,
    };
}

fn validateRuntimeRules(rules: []const protocol.Rule, allow_app_scoped_rules: bool) !void {
    for (rules, 0..) |rule, index| {
        if (rule.tap_modifier_usage != 0 and (rule.tap_modifier_usage < 0xE0 or rule.tap_modifier_usage > 0xE7)) return error.InvalidTapModifier;
        if (rule.app_id == null and !rule.passthrough) continue;
        if (!allow_app_scoped_rules) return error.AppScopedRulesUnsupported;
        const device = rule.device orelse return error.AppScopedRuleRequiresDevice;
        if (rule.app_id) |app_id| {
            if (!ForegroundUpdate.validBundleId(app_id)) return error.InvalidAppScopedBundleId;
        } else if (rule.passthrough) {
            return error.AppScopedPassthroughRequiresApp;
        }
        for (rules[0..index]) |previous| {
            const previous_device = previous.device orelse continue;
            if (previous.src_usage != rule.src_usage or previous_device.vendor != device.vendor or previous_device.product != device.product) continue;
            if (previous.app_id) |previous_app| {
                if (rule.app_id) |app_id| {
                    if (std.mem.eql(u8, previous_app, app_id)) return error.DuplicateAppScopedRule;
                }
            }
        }
    }
}

test "app-scoped rules require explicit runtime opt-in" {
    const base: protocol.Rule = .{ .src_usage = 0x39, .tap_usage = 0x29, .hold_usage = 0xE0 };
    try validateRuntimeRules(&.{base}, false);
    var modified = base;
    modified.tap_modifier_usage = 0xE7;
    try validateRuntimeRules(&.{modified}, false);
    modified.tap_modifier_usage = 0x04;
    try std.testing.expectError(error.InvalidTapModifier, validateRuntimeRules(&.{modified}, false));
    var scoped = base;
    scoped.app_id = "com.mitchellh.ghostty";
    try std.testing.expectError(error.AppScopedRulesUnsupported, validateRuntimeRules(&.{scoped}, false));
    var passthrough = base;
    passthrough.passthrough = true;
    try std.testing.expectError(error.AppScopedRulesUnsupported, validateRuntimeRules(&.{passthrough}, false));
    try std.testing.expectError(error.AppScopedRuleRequiresDevice, validateRuntimeRules(&.{scoped}, true));
    scoped.device = .{ .vendor = 5, .product = 6 };
    try validateRuntimeRules(&.{scoped}, true);
    try std.testing.expectError(error.DuplicateAppScopedRule, validateRuntimeRules(&.{ scoped, scoped }, true));
    passthrough.device = scoped.device;
    try std.testing.expectError(error.AppScopedPassthroughRequiresApp, validateRuntimeRules(&.{passthrough}, true));
    passthrough.app_id = "org.gnu.Emacs";
    try validateRuntimeRules(&.{ scoped, passthrough }, true);
    scoped.app_id = "not a bundle id";
    try std.testing.expectError(error.InvalidAppScopedBundleId, validateRuntimeRules(&.{scoped}, true));
}

fn sendOk(allocator: std.mem.Allocator, sw: *std.Io.net.Stream.Writer) !void {
    try protocol.writeMessage(&sw.interface, allocator, .{ .type = "ok" });
    try sw.interface.flush();
}

fn sendError(allocator: std.mem.Allocator, sw: *std.Io.net.Stream.Writer, code: []const u8, message: []const u8) !void {
    log.warn("error: code={s} message={s}", .{ code, message });
    try protocol.writeMessage(&sw.interface, allocator, .{
        .type = "error",
        .code = code,
        .message = message,
    });
    try sw.interface.flush();
}
