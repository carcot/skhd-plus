const std = @import("std");

pub const Candidate = struct {
    src_usage: u32,
    device_vendor: u32,
    device_product: u32,
    app_id: ?[]const u8 = null,
    passthrough: bool = false,
};

pub fn choose(candidates: []const Candidate, device_vendor: u32, device_product: u32, src_usage: u32, app_id: ?[]const u8) ?usize {
    const active_app = app_id orelse return null;
    var fallback: ?usize = null;
    for (candidates, 0..) |candidate, index| {
        if (candidate.src_usage != src_usage or candidate.device_vendor != device_vendor or candidate.device_product != device_product) continue;
        if (candidate.app_id) |rule_app| {
            if (std.mem.eql(u8, rule_app, active_app)) return if (candidate.passthrough) null else index;
        } else {
            fallback = if (candidate.passthrough) null else index;
        }
    }
    return fallback;
}

pub fn hasScopedSource(candidates: []const Candidate, device_vendor: u32, device_product: u32, src_usage: u32) bool {
    for (candidates) |candidate| {
        if (candidate.src_usage == src_usage and candidate.device_vendor == device_vendor and candidate.device_product == device_product and candidate.app_id != null) return true;
    }
    return false;
}

const HeldSource = struct {
    device_id: u64,
    src_usage: u32,
    selected: ?usize,
};

pub const Latches = struct {
    entries: [64]?HeldSource = @splat(null),

    pub fn press(self: *Latches, device_id: u64, src_usage: u32, selected: ?usize) ?usize {
        for (&self.entries) |*entry| {
            if (entry.*) |held| {
                if (held.device_id == device_id and held.src_usage == src_usage) return held.selected;
            }
        }
        for (&self.entries) |*entry| {
            if (entry.* == null) {
                entry.* = .{ .device_id = device_id, .src_usage = src_usage, .selected = selected };
                return selected;
            }
        }
        return null;
    }

    pub fn release(self: *Latches, device_id: u64, src_usage: u32) ?usize {
        for (&self.entries) |*entry| {
            if (entry.*) |held| {
                if (held.device_id == device_id and held.src_usage == src_usage) {
                    entry.* = null;
                    return held.selected;
                }
            }
        }
        return null;
    }

    pub fn clear(self: *Latches) void {
        self.* = .{};
    }

    pub fn isSelected(self: *const Latches, device_id: u64, index: usize) bool {
        for (self.entries) |entry| {
            if (entry) |held| {
                if (held.device_id == device_id and held.selected == index) return true;
            }
        }
        return false;
    }
};

pub const Route = struct {
    is_source: bool,
    scoped_source: bool,
    selected: ?usize,
};

pub fn route(
    candidates: []const Candidate,
    latches: *Latches,
    device_id: u64,
    device_vendor: u32,
    device_product: u32,
    usage: u32,
    pressed: bool,
    app_id: ?[]const u8,
) Route {
    var is_source = false;
    for (candidates) |candidate| {
        if (candidate.src_usage == usage and candidate.device_vendor == device_vendor and candidate.device_product == device_product) {
            is_source = true;
            break;
        }
    }
    const scoped_source = hasScopedSource(candidates, device_vendor, device_product, usage);
    if (!scoped_source) return .{ .is_source = is_source, .scoped_source = false, .selected = null };
    const selected = if (pressed)
        latches.press(device_id, usage, choose(candidates, device_vendor, device_product, usage, app_id))
    else
        latches.release(device_id, usage);
    return .{ .is_source = true, .scoped_source = true, .selected = selected };
}

pub fn shouldFeed(
    candidates: []const Candidate,
    latches: *const Latches,
    event_route: Route,
    device_id: u64,
    device_vendor: u32,
    device_product: u32,
    usage: u32,
    candidate_index: usize,
    engine_active: bool,
) bool {
    const candidate = candidates[candidate_index];
    if (candidate.device_vendor != device_vendor or candidate.device_product != device_product) return false;
    if (event_route.is_source) {
        if (candidate.src_usage != usage) return false;
        return !event_route.scoped_source or event_route.selected == candidate_index;
    }
    if (!engine_active) return false;
    return !hasScopedSource(candidates, device_vendor, device_product, candidate.src_usage) or
        latches.isSelected(device_id, candidate_index);
}

test "specific app overrides fallback regardless of declaration order" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "com.mitchellh.ghostty" },
    };
    try std.testing.expectEqual(@as(?usize, 1), choose(&candidates, 5, 6, 0x39, "com.mitchellh.ghostty"));
    try std.testing.expectEqual(@as(?usize, 0), choose(&candidates, 5, 6, 0x39, "com.apple.finder"));
    try std.testing.expectEqual(@as(?usize, null), choose(&candidates, 5, 6, 0x39, null));
    try std.testing.expectEqual(@as(?usize, null), choose(&candidates, 9, 6, 0x39, "com.apple.finder"));
}

test "explicit passthrough overrides fallback" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "org.gnu.Emacs", .passthrough = true },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
    };
    try std.testing.expectEqual(@as(?usize, null), choose(&candidates, 5, 6, 0x39, "org.gnu.Emacs"));
    try std.testing.expectEqual(@as(?usize, 1), choose(&candidates, 5, 6, 0x39, "com.apple.finder"));
}

test "key choice remains latched across app changes and devices" {
    var latches: Latches = .{};
    try std.testing.expectEqual(@as(?usize, 2), latches.press(10, 0x39, 2));
    try std.testing.expectEqual(@as(?usize, 2), latches.press(10, 0x39, 3));
    try std.testing.expectEqual(@as(?usize, 4), latches.press(11, 0x39, 4));
    try std.testing.expect(latches.isSelected(10, 2));
    try std.testing.expect(!latches.isSelected(11, 2));
    try std.testing.expectEqual(@as(?usize, 2), latches.release(10, 0x39));
    try std.testing.expectEqual(@as(?usize, 4), latches.release(11, 0x39));
    try std.testing.expectEqual(@as(?usize, 3), latches.press(10, 0x39, 3));
    latches.clear();
    try std.testing.expectEqual(@as(?usize, null), latches.release(10, 0x39));
}

test "scoped source detection is device-specific" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "org.gnu.Emacs" },
    };
    try std.testing.expect(hasScopedSource(&candidates, 5, 6, 0x39));
    try std.testing.expect(!hasScopedSource(&candidates, 7, 6, 0x39));
    try std.testing.expect(!hasScopedSource(&candidates, 5, 6, 0x2c));
}

test "routing selects one engine and latches through focus changes" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "org.gnu.Emacs" },
        .{ .src_usage = 0x2c, .device_vendor = 5, .device_product = 6 },
    };
    var latches: Latches = .{};
    const down = route(&candidates, &latches, 10, 5, 6, 0x39, true, "org.gnu.Emacs");
    try std.testing.expect(down.scoped_source);
    try std.testing.expectEqual(@as(?usize, 1), down.selected);
    try std.testing.expect(!shouldFeed(&candidates, &latches, down, 10, 5, 6, 0x39, 0, false));
    try std.testing.expect(shouldFeed(&candidates, &latches, down, 10, 5, 6, 0x39, 1, false));
    const other = route(&candidates, &latches, 10, 5, 6, 0x04, true, "com.apple.finder");
    try std.testing.expect(shouldFeed(&candidates, &latches, other, 10, 5, 6, 0x04, 1, true));
    try std.testing.expect(!shouldFeed(&candidates, &latches, other, 11, 5, 6, 0x04, 1, true));
    const up = route(&candidates, &latches, 10, 5, 6, 0x39, false, "com.apple.finder");
    try std.testing.expectEqual(@as(?usize, 1), up.selected);
    try std.testing.expect(shouldFeed(&candidates, &latches, up, 10, 5, 6, 0x39, 1, true));
    try std.testing.expect(!latches.isSelected(10, 1));
}

test "routing fails open for unknown app and preserves legacy sources" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "org.gnu.Emacs" },
        .{ .src_usage = 0x2c, .device_vendor = 5, .device_product = 6 },
    };
    var latches: Latches = .{};
    const unknown = route(&candidates, &latches, 10, 5, 6, 0x39, true, null);
    try std.testing.expect(unknown.scoped_source);
    try std.testing.expect(unknown.selected == null);
    try std.testing.expect(!shouldFeed(&candidates, &latches, unknown, 10, 5, 6, 0x39, 0, false));
    try std.testing.expect(!shouldFeed(&candidates, &latches, unknown, 10, 5, 6, 0x39, 1, false));
    const legacy = route(&candidates, &latches, 10, 5, 6, 0x2c, true, null);
    try std.testing.expect(legacy.is_source);
    try std.testing.expect(!legacy.scoped_source);
    try std.testing.expect(shouldFeed(&candidates, &latches, legacy, 10, 5, 6, 0x2c, 2, false));
}

test "passthrough latches raw source despite later app change" {
    const candidates = [_]Candidate{
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6 },
        .{ .src_usage = 0x39, .device_vendor = 5, .device_product = 6, .app_id = "org.gnu.Emacs", .passthrough = true },
    };
    var latches: Latches = .{};
    const down = route(&candidates, &latches, 10, 5, 6, 0x39, true, "org.gnu.Emacs");
    try std.testing.expect(down.scoped_source);
    try std.testing.expect(down.selected == null);
    try std.testing.expect(!shouldFeed(&candidates, &latches, down, 10, 5, 6, 0x39, 0, false));
    try std.testing.expect(!shouldFeed(&candidates, &latches, down, 10, 5, 6, 0x39, 1, false));
    const repeat = route(&candidates, &latches, 10, 5, 6, 0x39, true, "com.apple.finder");
    try std.testing.expect(repeat.selected == null);
    const up = route(&candidates, &latches, 10, 5, 6, 0x39, false, "com.apple.finder");
    try std.testing.expect(up.selected == null);
}
