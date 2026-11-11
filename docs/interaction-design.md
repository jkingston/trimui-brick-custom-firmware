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
`menu()` or `overlay()`. The logical index must identify the item, not its
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

### Motion

Use `motion.Scalar`. Call `retarget()` on every new destination, including a
reversal. Use `nextFrameMs()` or `motion.pollTimeout()` when merging motion with
poll/service deadlines. Reduced motion changes the value immediately and does
not remove state acknowledgement.

### Asynchronous action

Transition `focused → pressed → activating`, start the operation, then use
`busy` only if it outlives immediate activation. Finish with `succeeded` or
`failed`; keep errors and recovery at the originating control. Progress feedback
does not auto-dismiss. Completion feedback uses `FeedbackLifecycle`.

### Navigation and overlays

Forward transitions use the selected component as their anchor. Back is the
shorter reverse relationship and restores the previous focus identity. An
in-game overlay preserves the game frame where possible, traps focus while open,
and closes symmetrically. Never add a screen-specific splash between a source
and its destination.

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
- reduced motion, muted sound, and disabled haptics preserve usability;
- deterministic unit tests cover its state transitions and motion endpoints;
- active animation cannot block beyond its next frame deadline;
- the physical-device pass checks frame cadence and button-to-photon latency.

For release qualification, record at least 100 button-to-photon samples with a
high-speed camera or equivalent sensor and report median, p95, and worst case.
Software dispatch timestamps are diagnostic evidence, not photon latency. Also
test rapid direction reversal, long held scrolling, every boundary, cold and
warm game launch, overlay resume, failure recovery, and low-brightness use.
