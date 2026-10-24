const std = @import("std");

pub const max_bytes: usize = 256;

pub fn valid(id: []const u8) bool {
    if (id.len == 0 or id.len > max_bytes) return false;
    for (id) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '-' and byte != '_') return false;
    }
    return true;
}

test "bundle IDs preserve case but reject malformed values" {
    try std.testing.expect(valid("com.mitchellh.ghostty"));
    try std.testing.expect(valid("org.gnu.Emacs"));
    try std.testing.expect(!valid(""));
    try std.testing.expect(!valid("com.example with space"));
    try std.testing.expect(!valid("com.example/../other"));
    try std.testing.expect(!valid(&([_]u8{'a'} ** (max_bytes + 1))));
}
