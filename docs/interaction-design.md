# Brick product interface contract

This is the minimum product contract for new shell UI. It is deliberately
short: values live in code, behavior lives in reusable components, and this
document explains the decisions they enforce.

## Product model

Brick is a game that can reveal a system, not a system that happens to launch
games. There is no routine universal home screen.

1. A resumable game is the boot destination. The automatic state is loaded by
   the emulator before the shell asks the player to navigate anything.
2. Menu from a game reveals the **Quick system** over a retained representation
   of that game. Resume is the first focus and Menu closes the layer from every
   depth.
3. Leaving a game enters one **Library** whose density changes progressively:
   **Recent** is editorial and immediate, **Browse** is spatial, and **All
   games** is a compact typographic index. These are modes of one collection,
   not separately themed screens.
4. Device settings are entered intentionally from the library or quick system.
5. A foyer is permitted only when no game can be resumed, the library is empty,
   or recovery is required. It must not become the normal navigation hub.

The current emulator owns DRM while running and exits before the shell opens
Quick system. Therefore the component accepts a retained game representation;
today its guaranteed fallback is authored game identity. A future framebuffer
capture or compositor may supply the actual last frame without changing the
component or its interaction model.

Cross-device accounts, transfer, conflicts, and remote handoff are outside this
contract. Do not let speculative continuity add latency or hierarchy to local
play.

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
| Game identity across every library density | `src/game_object.zig` |
| Wi-Fi/Bluetooth initialization and recovery | `src/radio_surface.zig` |
| Renderer-neutral state and post-build interaction | `src/ui_scene.zig` |
| Input collection and device integration | `src/linux_backend.zig` |

Raw durations and easing curves outside `design.zig` are defects. Components
select a `MotionRole`; they do not construct private motion styles.

## Visual language

- Immersive and minimal are the same constraint: the game, physical-media
  object, or current device state owns the scene while controls recede. Empty
  chrome is not minimalism, and extra panels are not immersion. Prefer one
  subject, one spatial relationship, and one immediate action.
- Hierarchy comes from scale, spacing, weight, and composition—not decorative
  markers. Selection rails, glowing edges, nested pills, and ornamental cards
  are not part of Brick's language.
- Selection never changes text metrics. Sparse editorial choices use the shared
  `editorialChoice` component: contrast and weight may change, while size,
  line-height, bounds, and wrapping remain stable under rapid D-pad movement.
- Treat the device as a compact game instrument, not a settings application.
  The exceptional foyer is a stage, the library changes density without losing
  identity, device controls pair a moving index with a stable value stage, and
  Quick system makes the game recede without pretending it disappeared.
- Resting controls live directly on the page. Focus is expressed by type scale,
  weight, position, contrast, and artwork emphasis. Do not add a baseline,
  leading bar, rail, glow, or outline merely to make focus visible. Filled
  surfaces are reserved for momentary press acknowledgement.
- Use bone and carbon neutrals. Signal cyan echoes the hardware LEDs and means
  current position, active control, or live state; it is not decoration.
- Inter establishes titles, high-emphasis actions, and UI copy through the
  shared type scale. Noto Sans remains the multilingual fallback. Do not choose
  typefaces in a screen.
- Footers are one quiet action line: navigation/context at the left,
  immediate actions grouped at the right. Keep labels short and action-led.
  The shared footer preserves the primary action and collapses supporting
  labels toward icon-only before controls can collide; screens never assign
  footer slots.

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

### Focus object

For a typography- or artwork-led surface, draw the content at its intended
hierarchy and use `ui_components.focusAnchor()` for stable identity, press,
boundary, and navigation anchoring. The component is intentionally visually
quiet at rest: the content owns focus presentation. A screen must not implement
its own rail, pill, glow, underline, or focus animation.

Focused and active are separate. Focus answers “what will I operate?”; active
answers “what is running or already selected?”. An active game or setting may
remain marked when focus moves elsewhere.

The reusable composition patterns are:

| Pattern | Use | Structure |
| --- | --- | --- |
| Stage | Foyer, empty state, launch | One dominant subject and one obvious next action |
| Receding room | Quick system | Retained game left/back + compact controls right/front |
| Progressive density | Library | Recent editorial → Browse spatial → All games index |
| Index + value stage | Settings, device controls | Navigable labels left + stable value/context right |
| Decision pair | Confirmation | Clear consequence + two balanced actions |

### Game object

Every density uses the same logical game identity and state. `GameObject`
composition consists of artwork when available, an authored typographic
identity when it is not, title, system, stable interaction ID, focus state, and
an independent `active` state. Density changes geometry and information amount;
it must not swap to a different selection metaphor.

Missing artwork is not an empty grey card. Use system name, title typography,
or an authentic physical-media form so a collection remains authored when
metadata is incomplete. Bundled titles use authored covers. Browse preserves
cover proportions and depth; it does not stretch art into a generic card.
`GameObject` treats a loose label or disc face as material for its physical
object, not as a complete cover: editorial cover/card art comes first, the
authentic cartridge or disc comes next, and the loose texture is a last resort.

### Values and visual evidence

A number is not automatically the most important representation of a value.
Use spatial level, shape, position, or state first when that is how the player
judges the result; keep exact text as secondary evidence when precision remains
useful. Brightness is primarily a meter with a subordinate percentage. Device
battery is primarily a compact battery level with a small percentage. Do not
make `100%` larger than the control, device, or consequence it describes.

### Control grammar

Choose a control by behavior, not by the visual convention a screen happens to
resemble:

| Behavior | Representation | Rule |
| --- | --- | --- |
| Continuous value | Continuous meter | Use only when intermediate values are real and useful |
| Discrete numeric value | Stepped meter | Show every reachable stop; exact text is secondary |
| Ordered qualitative value | Magnitude or named choice | Prefer meaning such as Quiet / Balanced / Strong over invented percentages |
| Immediate reversible boolean | State word | Show `On` / `Off` at the row; confirm changes it |
| Asynchronous or fallible boolean | Stateful verb | Use `Turn on`, `Cancel`, and `Try again`; never present an operation as a switch |
| Small safe enumeration | Current value then choice list | Direct cycling is allowed only when every change is reversible and immediately legible |
| Committed selection | `ACTIVE` text | Active and focused remain independent; do not add radio circles or checkmark cards |
| Unknown-duration work | Shared activity cadence | No fake percentage or spinner chosen by the screen |
| Measurable work | Determinate meter | Show progress only when the underlying operation reports it truthfully |

Phone-style switches, segmented pills, and generic slider thumbs are not the
default Brick vocabulary. `ui_components.meter()` owns continuous values;
`ui_components.steppedMeter()` owns discrete values. Both keep a stable ID so
motion retargets rather than restarting.

### Radio initialization

Wi-Fi and Bluetooth checking, starting, stopping, unavailable, and failure
states use `radio_surface.status()`. They are page-scale device states, not
disabled toggle rows. State copy is concrete, one shared activity cadence shows
unfinished work, cancellation appears only when the operation accepts it, and
successful initialization returns to the actual list. Completion is confirmed
in place through the shared feedback lifecycle; it does not open a celebratory
modal.

Copy describes device availability and the user's next choice, never the
service lifecycle. Say “unavailable” and offer “Try again”; do not
expose daemons, initialization, startup failure, or recovery implementation.

### Quick system / receding room

Quick system contains only actions useful while a game is paused: Continue,
Save state, Load state, Performance, Network, and Save and exit. The retained
game representation remains the largest object, but loses contrast and scale;
the control column gains contrast without becoming a floating stack of cards.
Opening and closing are one reversible transform. Reduced motion applies the
same spatial result immediately and preserves the contrast change.

### Progressive density

The library modes are named by intent, never by widget:

| Density | Job | Navigation | Settlement |
| --- | --- | --- | --- |
| Recent | return quickly | vertical editorial sequence | art and detail visible immediately |
| Browse | explore | horizontal spatial sequence | selected object settles after movement |
| All games | locate precisely | vertical compact index | title responds immediately; rich preview may wait |

A held direction enters skim behavior through `input_repeat.Controller`.
Selection and title feedback update on every repeat. Expensive preview/artwork
work must not delay navigation and should settle only after the hold releases or
the shared content dwell expires. Screens do not implement private debounce
timers.

### Dense selectable row or tile

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

### Legacy landing action card

`ui_components.actionCard()` remains for genuinely object-like tiles, not page
navigation. New landing and overview surfaces should normally use Stage or
Deck composition. A group of generic dashboard cards is not Brick's language.

When focus moves between differently sized cards, `focus_motion.Controller`
morphs the shared plate's position and size from its visible geometry. Screen
code declares only the destination bounds and emphasis.

### Focus group

Use `interaction.FocusGroup` for one-dimensional movement. A `boundary` result
is distinct from `moved` and `empty`; route it to semantic boundary feedback.
Grid navigation may calculate its spatial destination, but must preserve the
same result contract and held-input controller.

`focus_motion.Controller` owns focus geometry. Feed each rebuilt
scene to it before presentation; it retargets from its currently visible
position and size. Content hierarchy presents resting focus; press settles into
a brief filled acknowledgement. Do not add selection rails, underlines, pills,
or screen-specific focus ornaments.

When a supported direction cannot move farther, call the controller's
`boundary()` response. It nudges toward the attempted direction and strengthens
the perimeter briefly; reduced motion keeps the perimeter pulse without moving content.
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

Use `ui_components.feedbackBanner()` for transient or terminal status. It uses
one quiet surface with a trailing semantic mark. Do not use coloured edge
stripes, toast shadows, or a new status ornament per screen. Failure copy is
sentence case and says what happened; recovery belongs to the available action.

Game launch is the same contract at page scale: reveal the selected game's
launch destination before synchronous preparation begins, start shared activity
during that connected transition, and leave the honest busy state visible until
the emulator owns the display. Never leave the library frozen after activation.

### Navigation and overlays

Use `navigation_motion.Controller`; screens must not author page-specific
transitions. The complete destination is legible on the first frame and settles
over less than one content margin. Forward and back mirror direction; the old
surface persists only as a narrow edge of spatial context. Do not zoom a page,
expand a control into a page, or use a full-screen presentation wipe. A new
input finishes the current transition at its destination immediately and acts
on that destination; input never waits for decoration. Reduced motion presents
the destination directly.

Whole-surface appearance changes use the same shared settle. Do not add a
theme-specific animation.

In-game overlay sublayers use the same controller and reduced-motion setting as
shell pages, trap focus while open, and restore the originating row. Never add
a screen-specific splash between a source and its destination.

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
