// SPDX-License-Identifier: GPL-2.0-only

pub const Kind = enum { libretro, standalone, port };
pub const Spec = struct {
    kind: Kind,
    executable: []const u8,
    content: []const u8,
    core: []const u8 = "",
    base_config: []const u8 = "",
    system_config: []const u8 = "",
};
pub const Plan = struct {
    argv: [12][]const u8 = undefined,
    len: usize = 0,
    fn add(self: *Plan, value: []const u8) void {
        self.argv[self.len] = value;
        self.len += 1;
    }
    pub fn slice(self: *const Plan) []const []const u8 {
        return self.argv[0..self.len];
    }
};

/// Builds argv without a command shell. A content path containing spaces or
/// shell metacharacters remains one argument.
pub fn plan(spec: Spec) !Plan {
    var result = Plan{};
    switch (spec.kind) {
        .libretro => {
            if (spec.core.len == 0 or spec.content.len == 0) return error.IncompleteLibretroSpec;
            result.add(spec.executable);
            if (spec.base_config.len != 0) {
                result.add("--config");
                result.add(spec.base_config);
            }
            if (spec.system_config.len != 0) {
                result.add("--appendconfig");
                result.add(spec.system_config);
            }
            result.add("-L");
            result.add(spec.core);
            result.add(spec.content);
        },
        .standalone => {
            if (spec.content.len == 0) return error.IncompleteStandaloneSpec;
            result.add(spec.executable);
            result.add(spec.content);
        },
        .port => {
            if (spec.content.len == 0) return error.IncompletePortSpec;
            result.add("/bin/sh");
            result.add(spec.content);
        },
    }
    return result;
}

test "libretro launch preserves a content path as one argument" {
    const testing = @import("std").testing;
    const content = "/roms/GBA/Metroid Zero Mission (USA).gba";
    const result = try plan(.{ .kind = .libretro, .executable = "/usr/bin/retroarch", .content = content, .core = "/usr/lib/libretro/mgba_libretro.so", .base_config = "/etc/retroarch.cfg", .system_config = "/etc/brick/retroarch/gba.cfg" });
    try testing.expectEqual(@as(usize, 8), result.len);
    try testing.expectEqualStrings(content, result.slice()[7]);
}

test "port plan invokes only the manifest script through sh" {
    const testing = @import("std").testing;
    const result = try plan(.{ .kind = .port, .executable = "", .content = "/userdata/ports/celeste/launch.sh" });
    try testing.expectEqualSlices([]const u8, &.{ "/bin/sh", "/userdata/ports/celeste/launch.sh" }, result.slice());
}
