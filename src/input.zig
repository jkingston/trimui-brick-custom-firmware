// SPDX-License-Identifier: GPL-2.0-only

pub const Action = enum { up, down, left, right, select, back, menu, view, filter };

// Hint identity is separate from appearance and from emulated game controls.
pub const HintControl = enum { confirm, back, view, menu, horizontal, filter };
