# Bluetooth production implementation plan

Status: implementation-ready, subject to the physical release gates below  
Baseline: `main` at `682c5d7e1a85cf5cb1b90dff253e6cf8f9cf40d5`  
Evidence: [Bluetooth spike results](bluetooth-spike-results.md) and [Bluetooth and battery qualification](bluetooth-and-battery-qualification.md)

## Product outcome

Bluetooth should feel like a native part of the handheld:

- one Bluetooth switch;
- saved and connected devices shown first;
- one **Find devices** action, with no Classic/Low Energy terminology;
- select a device, complete any code prompt, and see a truthful connecting, connected, or failed state;
- controllers can navigate the shell and games after reconnecting without restarting anything;
- a selected headset is checked before a game starts, with the speaker used if it is not ready;
- turning Bluetooth off shuts the XR829 Bluetooth hardware down;
- the screen follows the existing compact settings layout and both existing light and dark themes.

The first release supports Classic and Low Energy controllers and A2DP output. It does not promise headset microphones, live in-game audio failover, user-selectable codecs, background discovery, wake by controller, or controller remapping in the shell.

## Decision record validated against comparable systems

| Area | Reference behaviour | Production decision | Why this is the right divergence, if any |
| --- | --- | --- | --- |
| Device state | Android SettingsLib maintains cached devices and updates UI from asynchronous framework events rather than command output. BlueZ exposes the same event-driven model through ObjectManager and properties. | A long-lived `brick-bluetooth` service owns a BlueZ ObjectManager cache. The shell consumes versioned snapshots and results. | This follows the mature state model and avoids parsing `bluetoothctl`, polling, or putting D-Bus policy in the UI process. |
| Device list | Android separates paired and available devices. Steam Deck presents saved device details and a normal Bluetooth settings list. | Show **Connected**, **Saved**, and **Nearby** groups; keep existing rows stable while refreshing. | This is the familiar model, adapted to the handheld's directional navigation and small screen. |
| Discovery | BlueZ supports explicit `bredr`, `le`, and interleaved discovery; desktop systems commonly scan while their page is open. | Expose one **Find devices** action, internally run bounded Classic then Low Energy phases, and pause RF discovery during Wi-Fi association or validation. Never scan in the background. | Combined and full-duty Low Energy scans caused severe packet loss on this XR829. Transport selection is a hardware workaround, not a user choice. |
| Pairing | BlueZ intends a pairing wizard to register one agent and defines `KeyboardDisplay` for confirmation, display, passkey, and PIN cases. | The helper owns one lifetime `KeyboardDisplay` agent and serializes one user-owned pairing transaction. Pairable mode is bounded to that transaction. | Directly follows BlueZ's agent contract and avoids races caused by changing capability or spawning command-line agents. |
| Controller lifecycle | SDL emits add, remove, and remap events; RetroArch's `udev` path supports evdev hotplug, force feedback, autoconfiguration, and physical IDs. | Replace the shell's fixed built-in-only poll set with a dynamic evdev manager. Use RetroArch `udev` with a reviewed autoconfiguration set. | The Low Energy fixture proved reconnect creates a new UHID and input object. Retaining an old file descriptor cannot work. |
| Mapping | SDL normalizes physical controls and treats face buttons positionally; RetroArch matches driver, VID/PID, name, and optionally physical ID. | Normalize shell actions by position; package reviewed upstream `udev` profiles; preserve the built-in controls as a recovery input. | Avoids name-only matching and device-specific button assumptions while keeping the handheld operable after an external-controller failure. |
| Audio policy | WirePlumber monitors BlueZ, creates nodes, and applies profile/default-route policy dynamically. | Keep the internal ALSA codec as the global default. For a selected headset, preflight the BlueALSA A2DP PCM and pass a per-launch RetroArch override. | Recreating a desktop session manager is inappropriate for this image. BlueALSA and RetroArch do not provide trustworthy live default-device failover. |
| Codec | Desktop stacks expose many codecs and may choose by policy. Steam support treats changing codec as troubleshooting, not the primary pairing flow. | Ship SBC first. Keep aptX and aptX HD hidden until physical latency, stability, interoperability, and battery gates pass. | The host fixture proved negotiation only. Its 111–152 ms transport delay was not low latency, and aptX encoding used about seven times the BlueALSA CPU of SBC. |
| Power | BlueZ's `Adapter1.Powered` is the public authority. WirePlumber's embedded profile also favours deterministic state over restoring every runtime choice. | Persist the user's desired radio state; drive `Adapter1.Powered`; stop discovery before suspend; restore deliberately after resume. | On this board, `Powered=false` reaches reset, device-wake, regulators, and clocks. There is no Bluetooth rfkill device to manage. |
| Identity | Stock Allwinner firmware resolves `bt_mac` from secure/private storage or can derive it from the SoC chip ID through `sunxi-addr_mgt`; Android derivatives point Bluetooth at that sysfs result. NextUI inherits stock. KNULLI's missing-input fallback instead generated a new address on every boot, an open bug that destroys bond continuity. | Preserve an existing valid identity on upgrade. Otherwise derive one locally administered unicast address from the immutable SoC SID with one fixed, versioned algorithm before HCI starts. | This is zero-touch, stable across reboot and reinstallation, and avoids both per-boot randomness and a fragile multi-source recovery path. |
| Similar gaming firmware | Batocera enables BlueZ and controllers system-wide, but its public issue history includes UI/daemon state disagreement and reconnection workarounds. | Treat BlueZ properties and kernel input readiness as truth; never infer success from a command exit or link alone. | This retains the useful Linux/BlueZ foundation without copying a shell-script control boundary that has shown lifecycle failures. |

The XR829-specific discovery and power choices are measured divergences, not attempts to mimic another radio. No coexistence register, MIB payload, clock value, or scan parameter may be copied from another chipset.

### What comparable Brick firmware actually does for identity

| Firmware/platform | Observed implementation | Lesson |
| --- | --- | --- |
| TrimUI stock | Its DTS enables `allwinner,sunxi-addr_mgt`. The XR829 attach binary reads `/sys/class/addr_mgt/addr_bt`, then `xr_bt.conf`, then falls back to random. The universal root filesystem contains no per-unit address, so the primary value originates below the root filesystem. | Preserve the board identity path, not a file from the downloadable image. |
| Allwinner Tina reference | The address manager can consume a burned `bt_mac` from secure/private storage, derive from chip ID (`type_addr_bt = 2`), or accept a controlled sysfs value. | A JIT board resolver derived from immutable silicon identity is the vendor's scalable model. Exact stock equivalence is useful compatibility research, not an implementation prerequisite. |
| NextUI | It boots on the installed stock kernel and userspace services rather than replacing the board stack. Reports explicitly contrast it with KNULLI's changing address. | Its apparent identity success is inherited stock behaviour, not portable NextUI provisioning code. |
| KNULLI on Brick | It packages the stock BSP kernel/DTS, but the XR829 attach path receives no address and generates a different value after reboot; the resulting BlueZ directory changes and saved accessories require pairing again. This remains an open public issue in the archived distribution repository. | Copying the stock kernel is insufficient if the early userspace/boot identity input is omitted. Never use its random fallback as a design reference. |
| muOS on Brick | The inspected public package uses the same vendor 4.9 kernel lineage and retains the stock `sunxi-addr_mgt` DTS node, but Bluetooth identity provisioning is not exposed as an independently documented implementation. | It corroborates retention of the vendor board facility, but not a complete production Bluetooth path. |
| Android Allwinner derivatives | The vendor property `ro.bt.bdaddr_path` points at `/sys/class/addr_mgt/addr_bt`. | The address-manager boundary is reused across very different userspaces. |
| Generic Batocera/BlueZ systems | BlueZ normally consumes a stable address already supplied by the adapter/board integration; Batocera manages pairing and bonds above it. | A generic Bluetooth UI cannot repair a missing board identity. This belongs below `brick-bluetooth`. |

The product should therefore behave like stock/Allwinner at the board boundary and like BlueZ/Android at the device-state boundary. It should not ask each installer to recover a file and should not treat a per-boot random address as acceptable merely because pairing succeeds once.

## Production architecture

```text
settings UI ── versioned SOCK_SEQPACKET ── brick-bluetooth
     │                                      ├── BlueZ ObjectManager + Agent1
     │                                      ├── BlueALSA readiness probe
     │                                      └── persistent product policy
     │
dynamic evdev input manager ◀── kernel HID / UHID ◀── BlueZ
     │
game launcher ── private append config ── RetroArch udev + BlueALSA PCM
```

`brick-bluetooth` is a small root-owned C service using GDBus and GLib, both already present in the image. The framebuffer shell remains independent of D-Bus. BlueZ remains responsible for bonds and profiles; the helper owns product policy, serialization, and safe presentation.

### Process and boot ownership

Boot order must be explicit:

1. mount persistent `/data`;
2. resolve, validate, and atomically provision the Bluetooth identity;
3. load `uhid` and bring up the XR829 HCI transport;
4. start D-Bus and BlueZ with persistent bond storage;
5. start BlueALSA;
6. start `brick-bluetooth` and register its agent;
7. start the shell.

Identity resolution is JIT on the device's first boot, not part of writing the SD image and not a user workflow. It runs before the XR829 HCI transport and BlueZ:

1. Reuse a valid identity already stored in `/data/bluetooth`; this preserves existing installations, legitimately allocated addresses, and bonds.
2. Otherwise hash a fixed domain string plus the full immutable A133 SID with SHA-256, take six bytes in a documented canonical order, and set the locally administered and unicast bits. Reject invalid and Bluetooth-reserved results by rehashing with a documented counter. The domain, byte order, and algorithm are versioned and may never change silently.
3. Write the address atomically, start the transport, and verify that `hci0` reports the selected value before BlueZ creates bond storage. The derivation version is the fixed domain string in the implementation and its published test vector; there is no user-selectable algorithm or identity override.

The current mainline kernel already exposes the Brick's immutable 256-byte SID as read-only NVMEM at `/sys/bus/nvmem/devices/sunxi-sid0/nvmem`; no new low-level SID driver is required. The resolver should use the kernel NVMEM consumer API or a narrowly privileged early-boot reader, never map SID registers directly.

On every later boot, validate and apply the persisted identity without replacing it. A missing `/data` record is not an error: the same identity is regenerated from the immutable SID. The helper must never accept the XR829 firmware placeholder or generate a fresh address per boot.

This is a pragmatic community-firmware identity, not a claim that the derived address is an IEEE-allocated public BD_ADDR. Supporting formal Bluetooth address allocation is outside this implementation.

If all identity sources fail, the helper reports **Bluetooth unavailable** and leaves the controller off. The shell still boots and the built-in controls and speaker remain usable.

### Control protocol

Use `AF_UNIX` `SOCK_SEQPACKET` at `/run/brick-bluetooth/control.sock`, owned by root and accessible only to the shell's service identity. Reuse the Wi-Fi protocol conventions:

- protocol version and bounded packet size;
- service generation changed on restart;
- monotonically increasing snapshot revision;
- client request ID echoed in exactly one terminal result;
- stale-generation rejection;
- a full initial snapshot followed by complete replacement snapshots;
- fixed maximum counts and lengths, validated UTF-8, and zeroed unused fields.

Commands:

- `set_radio(enabled)`;
- `start_search`, `cancel_search`;
- `pair(device_id)`, `confirm_pairing`, `submit_passkey`, `cancel_pairing`;
- `connect(device_id)`, `disconnect(device_id)`, `forget(device_id)`;
- `select_audio(device_id | speaker)`;
- `set_controller_player(device_id, player | automatic)`.

The shell receives an opaque device ID, display name, device class, saved/connected/readiness state, supported product roles, optional battery percentage, player assignment, current operation, and a bounded product error. Raw addresses, BlueZ paths, UUID lists, and codec internals stay in the helper.

Opaque IDs must remain stable across helper restarts without exposing the address: derive them with a keyed digest over the controller identity, remote address and address type. Store the key mode 0600 in `/data/bluetooth`; never log the input or output at normal level.

### State authority and recovery

Desired state and observed state are separate:

- the persisted radio preference is intent;
- `Adapter1.Powered` is observed radio state;
- `Device1.Paired`, `Trusted`, and `Connected` are link/security state;
- `ServicesResolved` and profile-specific objects are capability state;
- an openable BlueALSA PCM is audio readiness;
- an eligible, opened evdev node is controller readiness.

The service never reports success early. It observes BlueZ property transitions and kernel/profile readiness, with bounded deadlines. On BlueZ owner loss it cancels operations, increments generation, closes readiness probes, reports service recovery, and reconstructs state when BlueZ returns. Cancellation and late callbacks are idempotent.

### Discovery scheduler

One user action owns a search. The initial implementation uses configurable phase deadlines with a 30-second total hard limit:

1. stop any orphaned discovery session and apply a Classic-only filter;
2. run a bounded Classic inquiry and accumulate results;
3. stop and observe `Discovering=false`;
4. apply the Low Energy filter and run with BlueZ's measured 60 ms interval / 30 ms window;
5. stop, retain results, and expire unsaved nearby rows only after the search completes.

The exact split is a qualification constant, not a UI contract. Start with 12 seconds Classic and 15 seconds Low Energy plus transition allowance, then tune only from the known-device discovery matrix. Use `DuplicateData=false`; do not make the adapter discoverable.

The helper subscribes to Wi-Fi authority state. It stops the active RF phase before association, roaming, connectivity validation, or captive sign-in, preserves the user's search and results, then resumes after the link has been stable for two seconds. It also stops immediately on page exit, game launch, suspend, explicit cancellation, radio-off, or client loss.

Acceptance requires the physical test set to be found reliably while concurrent Wi-Fi loss, latency, and throughput remain within the release budget. The promising 60/30 result is not sufficient by itself.

### Pairing and saved devices

Register one `KeyboardDisplay` agent for the helper lifetime and make it the default. Implement all BlueZ Agent1 methods, including release and cancellation. Pair only the selected opaque ID and reject unsolicited authorization.

For a user-owned pairing operation:

1. make the adapter pairable for the bounded operation only;
2. stop discovery before authentication;
3. present confirmation, displayed passkey, passkey entry, or legacy PIN as requested;
4. call `Device1.Pair` once;
5. wait for paired state and required service resolution;
6. mark trusted only after success;
7. return the device to a role-specific connected/readiness state;
8. clear pairable state on every terminal path.

Back invokes `CancelPairing`, dismisses the local prompt, and tolerates a late BlueZ cancellation. **Disconnect** preserves the bond. **Forget** requires confirmation, disconnects, calls `Adapter1.RemoveDevice`, removes product preferences, and verifies disappearance.

Automatic reconnect is limited to saved devices for which the relevant profile supports it. It never starts discovery. Use a bounded retry with backoff after boot/resume and stop retrying when the user disconnects, turns Bluetooth off, or selects another audio route.

### Controller input and player assignment

Implement a shell input manager independent of the Bluetooth helper:

- enumerate existing `/dev/input/event*` devices on startup;
- monitor udev additions, removals, and changes;
- inspect `EV_KEY`, `EV_ABS`, hats, VID/PID, bus, and device identity;
- accept eligible gamepads by capabilities, not display name;
- open nonblocking descriptors and add them to the poll set;
- assign a new instance whenever a device reappears, even if the path is reused;
- clear buttons, axes, repeat timers, and held navigation on removal, read failure, or `SYN_DROPPED`;
- ignore keyboard-only, touch, power, volume, sensor, and duplicate HID interface nodes.

The built-in gamepad is always active in the shell and is never displaced. Face actions are positional, with the current product accept/back convention applied after normalization.

Initial game assignment policy:

- without an external controller, built-in controls are player one;
- with one explicitly connected external controller, it becomes player one for games and built-in controls remain a recovery input for the shell and overlay;
- additional external controllers receive the next free player number;
- the settings page permits explicit reassignment before launch;
- reconnect restores a saved assignment only when the same opaque device identity returns; otherwise it uses the next free slot.

RetroArch switches `input_joypad_driver` from `linuxraw` to `udev`. Package a reviewed subset of the upstream `retroarch-joypad-autoconfig` `udev` profiles for the supported matrix, preserving license and source revision. Do not enable an enormous unreviewed database in the release image. Use VID/PID and the names/physical IDs supported by upstream matching, then pass explicit player assignments in the private per-launch append config.

### Audio routing

First release audio is A2DP output with SBC. A saved audio device is not **Ready** until:

1. BlueZ reports the device and A2DP profile connected;
2. BlueALSA exposes the playback PCM;
3. the helper opens and closes the exact PCM successfully.

The launcher writes a mode-0600 append file under `/run/brick-shell/` containing only the selected `bluealsa:DEV=…,PROFILE=a2dp` route and other per-session settings. The raw address never enters the long-lived shell model or persistent general configuration. Remove the file after RetroArch exits.

If preflight fails, show a short notice and launch on the speaker. If the headset disconnects in game, do not pretend it failed over: explain on return to the shell that the game must be relaunched after reconnecting or selecting the speaker.

Keep the global ALSA default on the internal codec. Do not add a global `pcm.!default`, and do not add PipeWire/WirePlumber solely for Bluetooth. Reconsider a session manager only if a later product requirement demands live routing and its memory, startup, and power costs are measured.

aptX and aptX HD remain compile-time available but product-disabled. Promote a codec only after physical receivers pass end-to-end latency, underrun, range, volume, reconnect, CPU, and external-current tests, and only if it produces a material user benefit over SBC. aptX Low Latency was not demonstrated and must not be implied by ordinary aptX support.

### Power, suspend, and coexistence

Persist only the user's desired Bluetooth state and product preferences. When off, set `Adapter1.Powered=false` and verify the observed transition. Do not add an rfkill abstraction that this driver does not expose.

Suspend sequence:

1. cancel search and pairing;
2. stop discovery and observe it stopped;
3. close audio probes and allow active profiles to disconnect;
4. record desired radio and selected-device intent;
5. suspend only after a bounded quiesce deadline.

Resume sequence:

1. wait for D-Bus, BlueZ, and the XR829 transport;
2. restore desired powered state, allowing the measured 4.3–5 second firmware startup;
3. reconstruct the device cache;
4. attempt bounded saved-profile reconnects without discovery;
5. re-enumerate input devices and clear all pre-suspend input state.

Do not change XR829 coexistence MIB `0x1011`, listen intervals, null/PS-poll templates, priorities, or rates without an exact stock layout and an A/B result. First port only the stock read-only coexistence diagnostics. Every driver change must compare stock declaration, runtime state, and measured behaviour, and rerun both Wi-Fi and Bluetooth matrices.

## Implementation milestones

### 0. Zero-touch identity and reproducible baseline

Deliver:

- specify and implement the version-one SID derivation, including its domain string, canonical byte order, local/unicast bit handling, reserved-value retry rule, and fixed test vectors;
- preserve any existing valid identity on upgrade;
- keep recovery of the exact Allwinner derivation as non-blocking compatibility research and record any future evidence without silently changing the version-one result;
- implement the early-boot resolver, versioned record, atomic persistence, and recomputation check;
- migrate an existing valid `/data/bluetooth/public-address` without changing it, then verify fresh install, reimage, missing `/data`, and restored-backup behaviour;
- verify the same `hci0` address and bond-storage path across two custom-firmware cold boots and an SD reimage;
- record kernel, BlueZ, BlueALSA, XR829 firmware hashes, and stock evidence in the qualification log;
- add release checks that reject absent, invalid, per-boot-random, firmware-placeholder, unversioned, source-mismatched, or unexpectedly changed identities.

Exit gate: a user can write a clean image and boot without supplying an address; the resolver selects the same identity on first boot, every reboot, and a clean reimage. Radio enable/disable and bond persistence are repeatable.

### 1. Service foundation and radio control

Deliver:

- Buildroot package, init script, D-Bus policy, persistent storage setup, and `uhid` load;
- GDBus ObjectManager cache, lifetime Agent1, protocol parser, peer-credential check, snapshots, and restart recovery;
- radio preference and truthful four-state UI: off, starting, on, unavailable;
- fake-BlueZ host harness and malformed-protocol tests.

Exit gate: shell and helper survive restart in either order; radio-off reaches XR829 hardware-off; no raw address reaches the UI/log; malformed or stale clients cannot mutate state.

### 2. Search, list, and pairing UX

Deliver:

- integrate the existing themed Bluetooth screen into settings;
- stable Connected/Saved/Nearby groups, one Find action, cancel, empty states, and bounded errors;
- phased discovery scheduler and Wi-Fi pause/resume contract;
- every Agent1 prompt using existing dialog and on-screen keyboard structures;
- disconnect and confirmed forget.

Exit gate: successful, rejected, timed-out, cancelled, daemon-lost, radio-lost, and duplicate-action cases all converge on correct state in light and dark themes. Search never survives its UI owner.

### 3. Dynamic controllers

Deliver:

- udev-backed shell input manager and normalized action layer;
- clean add/remove/reconnect handling and built-in recovery input;
- `uhid` boot integration;
- RetroArch `udev`, reviewed profiles, and explicit assignment config;
- controller detail/test screen showing live recognized actions and battery when available.

Exit gate: supported Classic and Low Energy controllers navigate the shell, launch games, work in-game, reconnect three times without stuck input, and preserve assignment. Two-controller play passes. Unsupported mappings fail visibly without compromising the built-in controls.

### 4. Bluetooth audio

Deliver:

- role classification, selected audio device, BlueALSA readiness probe, private launch override, and speaker fallback;
- SBC qualification and user-visible disconnect behaviour;
- optional codec test switch available only in engineering builds.

Exit gate: a physical headset passes two hours of gameplay without an underrun outside the agreed budget; cold boot/reconnect, volume, range, launch failure, and mid-game loss are predictable. End-to-end latency and external current are recorded, not inferred.

### 5. Suspend, battery, and coexistence hardening

Deliver:

- suspend/resume state machine and bounded reconnect;
- external-meter trials for off, on-idle, controller-idle, headset-idle, playback, and discovery;
- known-device discovery coverage alongside Wi-Fi loss/latency/throughput;
- read-only XR829 coexistence diagnostics and a documented decision on every proposed driver divergence.

Exit gate: 50 suspend/resume cycles have no lost adapter, stuck input, orphan scan, or wrong audio route; radio-off saving and feature costs have confidence intervals; concurrent-network thresholds below all pass.

### 6. Release hardening

Deliver:

- supported accessory matrix with firmware versions and transports;
- 24-hour paired-idle and 8-hour active-controller/audio soaks;
- storage-corruption, full-disk, BlueZ crash, helper crash, and missing-firmware fault injection;
- upgrade and rollback test preserving valid bonds and preferences;
- diagnostic bundle that redacts public and remote addresses by default;
- user documentation for pairing mode, reconnect, forget, Wi-Fi interference, and audio limitations.

Exit gate: every definition-of-done item is evidenced on the physical Brick; disabling the feature returns the existing speaker and built-in-control experience without reflashing.

## Release budgets and test matrix

Values marked **set during qualification** must be agreed from baseline distributions before the release candidate; they must not be silently chosen after seeing a failure.

| Property | Release gate |
| --- | --- |
| Identity | Same preserved or version-one SID-derived address across first boot, every cold boot, and reimage; algorithm/provenance recorded; zero per-boot-random paths |
| Search lifetime | At most 30 seconds of RF discovery per action; zero background or orphan discovery |
| Known-device discovery | At least 19/20 finds for every supported accessory at 0.5 m and 3 m, repeated with idle and loaded Wi-Fi |
| Wi-Fi during discovery | Packet loss, p95 latency, and throughput budgets set from the no-scan and phased-scan distributions; association/validation always takes priority |
| Pairing | 20/20 successful clean pairings per supported accessory; every cancel returns within two seconds after BlueZ acknowledges it |
| Reconnect | 20/20 ordinary reconnects and 20/20 post-reboot reconnects per supported controller/headset |
| Input | No stuck action in 100 remove/reconnect or `SYN_DROPPED` injections; built-in controls always retain shell recovery |
| Audio | End-to-end latency, underrun count, range, and volume recorded per codec/device; SBC is the only initial release requirement |
| Suspend | 50/50 cycles per supported role and 20/20 with two controllers |
| Power | External-current paired trials with confidence intervals for every advertised saving/cost; no voltage-only inference |
| Memory/CPU | Helper steady-state and peak RSS plus scan/pair CPU recorded; no unbounded cache or per-event allocation growth |

Physical coverage:

- one current Xbox controller, one PlayStation controller, one 8BitDo controller, and the working host Low Energy fixture;
- at least one Classic HID controller if distinct from the above;
- one SBC-only headset and two dual-codec receivers from different vendors;
- one passkey-confirmation device and one legacy PIN path if supported scope retains it;
- one and two external controllers, with Wi-Fi idle, association, download, and captive validation;
- cold boot, warm restart, helper restart, BlueZ restart, suspend/resume, low-battery, and radio-off/on.

## Security, privacy, and failure rules

- The shell cannot talk to BlueZ directly and cannot supply arbitrary D-Bus paths or addresses.
- Validate peer credentials on the control socket and install a restrictive BlueZ D-Bus policy.
- Pairable and discoverable are off by default; discovery does not require local discoverability.
- Trust follows successful user-owned pairing and service resolution, never mere proximity or name match.
- Bound every string, array, device count, deadline, and retry count.
- Sanitize device names before display and never interpret them as markup.
- Redact controller and accessory addresses, passkeys, PINs, link keys, and identity hashes from normal logs.
- Store the controller identity, opaque-ID key, bonds, and runtime launch file mode 0600; update persistent product state atomically.
- Reject unsolicited authorization and concurrent pairing. Clear prompts and secrets on every cancellation and process restart.
- Failure always preserves the built-in gamepad and internal speaker.

## Closed product decisions and qualification inputs

The implementation decisions are closed: the supported target matrix begins
with Xbox, PlayStation, 8BitDo and the deterministic host fixture; one external
controller becomes player one while built-in controls remain recovery input;
legacy PIN callbacks are handled safely without promising an untested legacy
accessory; and battery appears only when BlueZ exposes `Battery1.Percentage`.

Numerical Wi-Fi, end-to-end audio latency, underrun, discovery-coverage and
battery budgets are qualification inputs, not architecture choices. They must
be set from the first physical distributions and external-current trials before
a release claim. Missing measurements may not be replaced with inferred limits.

No architecture choice remains open between Classic and Low Energy: production supports both behind one device experience. No driver tuning is required to begin milestones 0–4; driver changes remain permitted when exact stock evidence and controlled measurements justify them.

## Definition of done

Bluetooth is production-ready only when:

- a clean image resolves identity without user action; it remains stable across reboot, upgrade, and reimage, preserves bonds when `/data` is retained, and reports its provenance accurately;
- all UI states are driven by observed service/profile/input readiness and match both themes;
- discovery is explicit, bounded, cancellable, and coexistence-qualified;
- pairing, reconnect, disconnect, and forget survive every tested failure path;
- controller hotplug works in the shell and RetroArch with stable player assignment;
- SBC audio launches reliably with truthful fallback and documented mid-game loss behaviour;
- power and performance claims come from external-current and runtime measurements;
- stock hardware behaviour and every divergence are recorded with exact source/runtime evidence;
- the feature can be disabled without regressing built-in input, speaker audio, Wi-Fi, boot, or suspend.

## Primary references

- Bluetooth Core, BR/EDR device addressing: <https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-61/out/en/br-edr-controller/baseband-specification.html>
- Bluetooth Core, Low Energy public and random addresses: <https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-62/out/en/low-energy-controller/link-layer-specification.html>
- BlueZ Adapter API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst>
- BlueZ Device API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst>
- BlueZ Agent and AgentManager APIs: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst>, <https://github.com/bluez/bluez/blob/master/doc/org.bluez.AgentManager.rst>
- BlueZ management protocol: <https://github.com/bluez/bluez/blob/master/doc/mgmt-protocol.rst>
- BlueZ discovery configuration: <https://github.com/bluez/bluez/blob/master/src/main.conf>
- Android cached Bluetooth device model: <https://android.googlesource.com/platform/frameworks/base/+/master/packages/SettingsLib/src/com/android/settingslib/bluetooth/CachedBluetoothDevice.java>
- Android paired/available device settings structure: <https://android.googlesource.com/platform/packages/apps/Settings/+/master/src/com/android/settings/bluetooth/BluetoothSettings.java>
- SDL gamepad hotplug and mapping API: <https://github.com/libsdl-org/SDL/blob/main/include/SDL3/SDL_events.h>, <https://github.com/libsdl-org/SDL/blob/main/include/SDL3/SDL_gamepad.h>
- RetroArch Linux input drivers and autoconfiguration: <https://docs.libretro.com/guides/input-controller-drivers/>, <https://docs.libretro.com/guides/controller-autoconfiguration/>
- RetroArch upstream controller profiles: <https://github.com/libretro/retroarch-joypad-autoconfig>
- WirePlumber Bluetooth policy: <https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/bluetooth.html>
- BlueALSA PCM plugin: <https://github.com/Arkq/bluez-alsa/blob/master/doc/bluealsa-plugins.7.rst>
- Batocera Bluetooth configuration: <https://github.com/batocera-linux/batocera.linux/blob/master/package/batocera/core/batocera-system/batocera.conf>
- Steam Deck Bluetooth coexistence guidance: <https://help.steampowered.com/en/faqs/view/4c18-08b5-dec9-3af4>
- Allwinner Wi-Fi/Bluetooth address-manager source hierarchy and chip-ID mode: <https://bbs.aw-ol.com/topic/768/faq-wi-fi-bt-mac%E5%9C%B0%E5%9D%80%E5%AE%9A%E5%88%B6>
- KNULLI Brick per-boot random-address integration bug: <https://github.com/knulli-cfw/distribution/issues/453>
