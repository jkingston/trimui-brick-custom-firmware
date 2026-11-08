// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");

pub const Sample = struct {
    duration_seconds: u32,
    energy_milliwatt_hours: u32,

    pub fn averageMilliwatts(self: Sample) ?u32 {
        if (self.duration_seconds == 0) return null;
        return @intCast((@as(u64, self.energy_milliwatt_hours) * 3600 + self.duration_seconds / 2) / self.duration_seconds);
    }
};

pub const Result = enum {
    missing_measurement,
    measurement_too_short,
    improvement_not_repeatable,
    no_material_improvement,
    measured_improvement,
};

pub const Comparison = struct {
    result: Result,
    saving_percent: i16 = 0,
};

/// Evaluate paired baseline/candidate runs. A setting is not called an
/// improvement until every pair is at least ten minutes long, every candidate
/// beats its baseline, and aggregate power falls by the requested threshold.
pub fn compare(baselines: []const Sample, candidates: []const Sample, minimum_saving_percent: u8) Comparison {
    if (baselines.len < 3 or baselines.len != candidates.len) return .{ .result = .missing_measurement };

    var baseline_power: u64 = 0;
    var candidate_power: u64 = 0;
    for (baselines, candidates) |baseline, candidate| {
        if (baseline.duration_seconds < 600 or candidate.duration_seconds < 600) return .{ .result = .measurement_too_short };
        const before = baseline.averageMilliwatts() orelse return .{ .result = .missing_measurement };
        const after = candidate.averageMilliwatts() orelse return .{ .result = .missing_measurement };
        if (after >= before) return .{ .result = .improvement_not_repeatable };
        baseline_power += before;
        candidate_power += after;
    }

    const signed_change = @as(i64, @intCast(baseline_power)) - @as(i64, @intCast(candidate_power));
    const saving: i16 = @intCast(@divTrunc(signed_change * 100, @as(i64, @intCast(baseline_power))));
    return .{
        .result = if (saving >= minimum_saving_percent) .measured_improvement else .no_material_improvement,
        .saving_percent = saving,
    };
}

test "average power normalizes trials of different duration" {
    try std.testing.expectEqual(@as(?u32, 600), (Sample{ .duration_seconds = 1800, .energy_milliwatt_hours = 300 }).averageMilliwatts());
    try std.testing.expectEqual(@as(?u32, null), (Sample{ .duration_seconds = 0, .energy_milliwatt_hours = 300 }).averageMilliwatts());
}

test "a repeatable material reduction qualifies" {
    const baseline = [_]Sample{
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 500 },
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 510 },
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 490 },
    };
    const candidate = [_]Sample{
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 420 },
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 430 },
        .{ .duration_seconds = 1800, .energy_milliwatt_hours = 410 },
    };
    const result = compare(&baseline, &candidate, 10);
    try std.testing.expectEqual(Result.measured_improvement, result.result);
    try std.testing.expectEqual(@as(i16, 16), result.saving_percent);
}

test "noise and undersized trials cannot be called savings" {
    const baseline = [_]Sample{
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 300 },
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 300 },
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 300 },
    };
    const noisy = [_]Sample{
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 290 },
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 310 },
        .{ .duration_seconds = 900, .energy_milliwatt_hours = 280 },
    };
    try std.testing.expectEqual(Result.improvement_not_repeatable, compare(&baseline, &noisy, 5).result);
    try std.testing.expectEqual(Result.missing_measurement, compare(baseline[0..2], noisy[0..2], 5).result);

    var short = noisy;
    short[0].duration_seconds = 599;
    try std.testing.expectEqual(Result.measurement_too_short, compare(&baseline, &short, 5).result);
}
