# Brick product interface contract

This is the minimum product contract for new shell UI. It is deliberately
short: values live in code, behavior lives in reusable components, and this
document explains the decisions they enforce.

## Product model

Brick is a game-centred, controller-first personal-device OS. It takes the
predictability and ambient awareness of a modern mobile OS, but makes play—not
apps, documents, or multitasking—the foreground model. There is no dashboard,
dock, or app grid.

The experience has six layers with distinct jobs:

| Layer | Job |
| --- | --- |
| Play | The full-screen foreground activity; ordinary system chrome is absent. |
| Library | Home: resume, choose, or explore a game. |
| Quick system | A reversible control layer over retained play context. |
| Device | Deliberate configuration reached from Library or Quick system. |
| Focused task | A bounded job such as joining Wi-Fi or pairing a controller. |
| Interruption | A rare cross-context event that cannot be represented where it originated. |

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
| Product page hierarchy and return direction | `src/product_navigation.zig` |
| Interruptible scalar motion and frame deadlines | `src/motion.zig` |
| Connected source/destination settlement | `src/navigation_motion.zig` |
| Shared focus, meter, activity, layout, and navigation orchestration | `src/scene_motion.zig` |
| Stable-ID viewport scrolling | `src/layout_motion.zig` |
| Animated meters and value retargeting | `src/meter_motion.zig` |
| Indeterminate activity cadence | `src/activity_motion.zig` |
| Identity, control lifecycle, focus boundaries | `src/interaction.zig` |
| Sound/haptic event policy | `src/feedback.zig` |
| Selectable controls and notice lifecycle | `src/ui_components.zig` |
| Exceptional entry composition | `src/foyer_view.zig` |
| Settings, choices, confirmations, and value stages | `src/device_views.zig` |
| Game identity across every library density | `src/game_object.zig` |
| Wi-Fi/Bluetooth initialization and recovery | `src/radio_surface.zig` |
| Renderer-neutral state and post-build interaction | `src/ui_scene.zig` |
| Input collection and device integration | `src/linux_backend.zig` |

Raw durations and easing curves outside `design.zig` are defects. Components
select a `MotionRole`; they do not construct private motion styles.
`tools/check-ui-architecture` also rejects view code that emits raw interactive
scene primitives; new controls must enter through `ui_components.zig`.

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

## System chrome and interruption policy

Brick borrows the settled grammar of a modern mobile OS but reorders it around
play. The Library is home, a running game is the foreground activity, and Quick
system is the contextual control surface. Do not import phone or desktop chrome
without the job that justified it there.

| Element | Brick policy |
| --- | --- |
| Taskbar, dock, app switcher | None. Library is home and play is foreground; Brick does not expose routine multitasking or an app grid. |
| Status bar | No full-width bar. `ui_components.systemStatus()` owns a compact top-right cluster on Library, Device, and Quick system surfaces. It is absent over uninterrupted play and on pages where connectivity is already the task. |
| Battery, network, accessories | Ambient icons in the shared status cluster. They describe durable state and never become a row of prose. |
| Routine success | Settle in place. The changed value, connected row, or status icon is the confirmation; do not toast “saved”, “on”, or “connected”. |
| Progress, warning, failure | Keep it at the originating control where possible. Use the shared hairline status band only when the event has no sufficient local surface. |
| Notification | Reserve for a cross-context event that needs attention, such as controller loss or save failure. Background sync completion is silent. There is no notification centre until real product requirements justify one. |
| Modal | Only destructive, security-sensitive, or irreversible commitments. Never use a modal merely to report completion. |
| Menu button | Reveal Device from Library; dismiss the complete system layer back to Library; reveal or close Quick system during play. From a focused task opened during play, Menu closes every system layer and resumes. It is never ignored or used as a page-dependent shortcut carousel. |

The status cluster owns icon order, spacing, and collapse. Screens do not place
battery or network marks themselves. A durable state may remain visible there;
a transient event must expire or become a concrete object in its destination.

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
useful. Brightness is primarily a named perceptual outcome and stepped meter;
its exact stop (`10 of 10`) is subordinate evidence, not a percentage headline.
Device battery is primarily a compact battery level with small exact text only
where the remaining number changes a decision. Do not make `100%` larger than
the control, device, or consequence it describes.

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
states use `radio_surface.status()`. The destination and task remain stable
(`Join a network`, `Connect a device`) while a compact state word and the shared
activity cadence communicate readiness. They are not disabled toggle rows or
page-scale explanations of the radio lifecycle. Cancellation appears only when
the operation accepts it, and successful initialization resolves into the real
list without a completion toast.

Copy describes the task and the user's next choice, never the service lifecycle.
Say `needs attention` and offer `Try again`; do not expose daemons,
initialization, startup failure, or recovery implementation.

### Quick system / receding room

Quick system contains only actions useful while a game is paused: Continue,
Save state, Load state, Brightness, Network, and Save and exit. Performance is
a deliberate Device setting, not a frequent in-game control. Brightness changes
directly with horizontal input and stays bounded rather than wrapping. Healthy
connectivity resolves into the top-right status icon; the Network row carries
text only when it needs attention. The retained
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

Use `ui_components.feedbackBanner()` only for cross-context progress, warning,
or failure that has no sufficient local surface. It uses the stable hairline
status band with a trailing semantic mark, not a floating toast. Routine success
must resolve into the changed object or `systemStatus()`. Do not use coloured
edge stripes, toast shadows, or a new status ornament per screen. Failure copy
is sentence case and says what happened; recovery belongs to the available
action.

Game launch is the same contract at page scale: reveal the selected game's
launch destination before synchronous preparation begins, start shared activity
during that connected transition, and leave the honest busy state visible until
the emulator owns the display. Never leave the library frozen after activation.

### Navigation and overlays

Routine shell navigation is press then cut: the source control acknowledges the
input, and the complete destination appears immediately. Use
`scene_motion.Controller.cutTo()` so focus continuity resets and unrelated pages
do not appear to morph into each other.

Use `navigation_motion.Controller` only when the source and destination share a
meaningful object or room: game launch, Quick system depth, and similarly
connected handoffs. The complete destination is legible on the first frame and
settles over less than one content margin. Forward and back mirror direction;
the old surface persists only as a narrow edge of spatial context. Do not zoom
a page, expand a control into a page, or use a full-screen presentation wipe. A
new input finishes the current transition at its destination immediately and
acts on that destination; input never waits for decoration. Reduced motion
presents the destination directly.

Whole-surface appearance changes use the same immediate cut. Do not add a
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
- routine page changes use shared press-cut handling; connected handoffs use the shared navigation controller and cancel cleanly;
- reduced motion, muted sound, and disabled haptics preserve usability;
- deterministic unit tests cover its state transitions and motion endpoints;
- active animation cannot block beyond its next frame deadline;
- the physical-device pass checks frame cadence and button-to-photon latency.

For release qualification, record at least 100 button-to-photon samples with a
high-speed camera or equivalent sensor and report median, p95, and worst case.
Software dispatch timestamps are diagnostic evidence, not photon latency. Also
test rapid direction reversal, long held scrolling, every boundary, cold and
warm game launch, overlay resume, failure recovery, and low-brightness use.
