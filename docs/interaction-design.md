# Brick interaction design

This is the minimum product contract for new shell UI. It is deliberately
short: values live in code, behavior lives in reusable components, and this
document explains the decisions they enforce.

## Product principles

1. **Respond before completing.** A press gets visible acknowledgement before
   an action, service, or emulator finishes.
2. **Preserve causality and context.** The object that caused navigation remains
   the visual and focus anchor. Returning restores the previous selection.
3. **Keep control with the player.** Motion is interruptible and retargets from
   its currently visible value. Never queue decorative animation ahead of input.
4. **Make state explicit.** Busy, disabled, failed, and boundary states must not
   look like ignored input.
5. **Use feedback for meaning.** Visuals are authoritative. Sound and haptics
   reinforce semantic events and remain independently optional.
6. **Compose behavior.** Screens declare content, geometry, identity, and
   destination. They do not invent timings, easing, repeat, press behavior, or
   feedback hardware policy.

## Sources of truth

| Concern | Code owner |
| --- | --- |
| Typography, geometry, semantic motion roles | `src/design.zig` |
| Interruptible scalar motion and frame deadlines | `src/motion.zig` |
| Connected page transitions and source anchors | `src/navigation_motion.zig` |
| Stable-ID viewport scrolling | `src/layout_motion.zig` |
| Animated meters and value retargeting | `src/meter_motion.zig` |
| Indeterminate activity cadence | `src/activity_motion.zig` |
| Identity, control lifecycle, focus boundaries | `src/interaction.zig` |
| Sound/haptic event policy | `src/feedback.zig` |
| Selectable controls and notice lifecycle | `src/ui_components.zig` |
| Renderer-neutral state and post-build interaction | `src/ui_scene.zig` |
| Input collection and device integration | `src/linux_backend.zig` |

Raw durations and easing curves outside `design.zig` are defects. Components
select a `MotionRole`; they do not construct private motion styles.

## Interaction states

All selectable components use `interaction.State`.

| State | Required presentation | Input contract |
| --- | --- | --- |
| `idle` | Resting content | May receive focus |
| `focused` | Unambiguous focus without moving layout | Direction and confirm accepted |
| `pressed` | Immediate depression/inversion | Release activates; cancellation restores focus |
| `activating` | Press remains acknowledged | Duplicate activation suppressed |
| `busy` | Work is shown at its source | Cancel where the operation is safely cancellable |
| `succeeded` | Completion is visible in place | Returns to focused or idle |
| `failed` | Error and recovery path are visible | Focus remains usable |
| `disabled` | Intentionally unavailable | Confirm does nothing; explain when non-obvious |

Use `interaction.Control` for the action lifecycle. Do not encode busy or error
as unrelated booleans in a view.

## Component recipes

### Selectable row or tile

Use `ui_components.selectable(scope, index, focused, bounds, label)`. Add a
stable `interaction.Id.Scope` and use the logical item index, then set fields and call
`menu()`, `overlay()`, or `frame()` for artwork tiles. The logical index must identify the item, not its
temporary visible slot in a scrolling window.

```zig
var row = components.selectable(.settings, setting_id, selected, bounds, label);
row.detail = detail;
row.value = value;
row.overlay(&tree);
```

### Focus group

Use `interaction.FocusGroup` for one-dimensional movement. A `boundary` result
is distinct from `moved` and `empty`; route it to semantic boundary feedback.
Grid navigation may calculate its spatial destination, but must preserve the
same result contract and held-input controller.

`focus_motion.Controller` owns the visible focus rail. Feed each rebuilt scene
to it before presentation; it retargets from the rail's currently visible
position. Focus uses the restrained surface treatment and rail, while press is
the stronger inversion. Do not reproduce either treatment inside a screen.

When a supported direction cannot move farther, call the controller's
`boundary()` response. It nudges toward the attempted direction and strengthens
the rail briefly; reduced motion keeps the rail pulse without moving content.
Irrelevant axes remain silent, so feedback means “the end” rather than “that
control does not use this button.”

### Meter or slider

Use `ui_components.meter()` with a stable ID and a normalized 0–1000 value.
Feed rebuilt scenes through `meter_motion.Controller`; repeated adjustments
retarget the thumb from its visible value. Screens must not draw private tracks,
thumbs, or raw value bars. Reduced motion updates the meter immediately.

### On-screen keyboard

Use `ui_components.keyboard()` with `KeyboardInput`; do not draw keys directly.
The component owns stable per-key identity, focus travel, boundary response, and
press depression. Always pass `uppercase` and `symbols` from the input model so
the visible key labels match the characters that activation will produce.

### Motion

Use `motion.Scalar`. Call `retarget()` on every new destination, including a
reversal. Use `nextFrameMs()` or `motion.pollTimeout()` when merging motion with
poll/service deadlines. Reduced motion changes the value immediately and does
not remove state acknowledgement.

When a rebuilt list changes its visible window, use `layout_motion.Controller`.
It matches controls by logical `interaction.Id`, keeps shared rows at their
visible positions, and moves incoming rows from the same scroll direction.
Never identify a scrolling item by its temporary visible slot.

### Asynchronous action

Transition `focused → pressed → activating`, start the operation, then use
`busy` only if it outlives immediate activation. Finish with `succeeded` or
`failed`; keep errors and recovery at the originating control. Progress feedback
does not auto-dismiss. Completion feedback uses `FeedbackLifecycle`.

Use progress `Feedback` for indeterminate work; it owns the shared activity
indicator and `activity_motion.Controller` owns its cadence. Screens must not
draw private spinners or choose animation timing. Reduced motion preserves the
busy signal as three static dots rather than removing it. Progress copy omits
trailing ellipses because the activity indicator already communicates continuation.

### Navigation and overlays

Use `navigation_motion.Controller`; screens must not author page-specific
transitions. Forward reveals the complete destination out of the selected
component. Back leaves the restored parent visible while the departing page
collapses into its restored focus. A new input finishes the current transition
at its destination immediately and acts on that destination; input never waits
for decoration. Reduced motion presents the destination directly.

Whole-surface appearance changes use the same forward reveal from the selected
appearance option. Do not hard-cut between light and dark palettes or add a
separate theme-specific animation.

In-game overlay sublayers use the same controller and reduced-motion setting as
shell pages, trap focus while open, and return into the originating row. Never
add a screen-specific splash between a source and its destination.

## Timing and scheduling

The semantic timings in `design.motion_tokens` are the approved defaults:
press, focus, content movement, enter, exit, and feedback. Exit is shorter than
enter. Opacity/effect changes must not overshoot; spatial values may decelerate.

An active motion must contribute a frame deadline to the event loop. Setting a
dirty flag is insufficient if `poll()` can sleep past the next frame. A final
zero-timeout frame paints the exact settled endpoint.

Held direction uses the shared `input_repeat.Controller`. Do not implement
repeat in a screen. Lists do not wrap unless their product semantics are
explicitly circular.

## Sound, haptics, and LEDs

Components emit `feedback.Event`; only device policy maps it to hardware.

- Navigation sound may be subtle; navigation haptics remain off by default.
- The current GPIO vibrator is binary. Boundary, success, failure, and power
  pulses require physical pulse qualification before enabling them.
- The speaker amplifier has a settling interval. Verify that short cues are not
  delayed or clipped before enabling them in the product image.
- LEDs may reflect durable device state, but never substitute for screen
  acknowledgement.

## Definition of done

A new interactive component is not complete until:

- it has stable identity and all applicable interaction states;
- press is visible before activation and release/cancellation is defined;
- rapid reversal retargets instead of queueing;
- held input and boundaries use shared behavior;
- busy, disabled, failure, and recovery are unambiguous;
- forward/back focus restoration is tested;
- page changes use the shared connected-navigation controller and cancel cleanly;
- reduced motion, muted sound, and disabled haptics preserve usability;
- deterministic unit tests cover its state transitions and motion endpoints;
- active animation cannot block beyond its next frame deadline;
- the physical-device pass checks frame cadence and button-to-photon latency.

For release qualification, record at least 100 button-to-photon samples with a
high-speed camera or equivalent sensor and report median, p95, and worst case.
Software dispatch timestamps are diagnostic evidence, not photon latency. Also
test rapid direction reversal, long held scrolling, every boundary, cold and
warm game launch, overlay resume, failure recovery, and low-brightness use.
