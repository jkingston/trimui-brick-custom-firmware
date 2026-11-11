# Bluetooth implementation record

Date: 2026-11-08

This records the prior art used for production decisions, what is implemented,
and where Brick deliberately differs. Device measurements remain in
`bluetooth-spike-results.md`; this document does not turn declared capability
or a host fixture result into physical-accessory qualification.

## Decisions and prior art

| Area | Reference behavior | Brick implementation |
| --- | --- | --- |
| Device authority | BlueZ `Adapter1`, `Device1`, `Agent1`, `Battery1`, and ObjectManager are the supported state and pairing APIs. | One root service owns BlueZ, one lifetime `KeyboardDisplay` agent, bounded operations, opaque HMAC device IDs, optional reported battery, and a versioned `SOCK_SEQPACKET` shell protocol. The shell never receives an address or D-Bus path. |
| Discovery | BlueZ supports per-client discovery filters, including `bredr` and `le`; Android and SteamOS present one accessory list rather than transport choices. | One explicit **Find devices** action runs 12 seconds of Classic and 15 seconds of Low Energy discovery. Wi-Fi association/validation pauses and resumes the internal phase without exposing radio mechanics to the user. There is no background discovery. |
| Input hotplug | RetroArch 1.22.2's udev driver supports evdev hotplug, physical identity and autoconfiguration. Its reservation code reallocates devices to requested players. | The shell accepts event devices with gamepad capabilities, watches `/dev/input` changes, reconciles paths, handles hats and D-pads, and clears state after removal or `SYN_DROPPED`. RetroArch uses udev and a private per-launch reservation: one external pad is Player 1 and the built-in pad is Player 2; without an external pad the built-in pad remains Player 1. |
| Controller mappings | The official `retroarch-joypad-autoconfig` repository supplies VID/PID/name mappings under the MIT license. | A reviewed subset at commit `2e3b8a2728d5efd00fa0207d07ba2488b89e87b2` covers current Xbox, DualShock 3/4, DualSense and representative 8BitDo Bluetooth modes. Brick-owned profiles cover the built-in pad and the deterministic host fixture. The full unreviewed database is not shipped. |
| Recovery input | RetroArch normally evaluates joypad meta hotkeys only on the hotkey port, which follows Player 1. | A narrow downstream RetroArch 1.22.2 patch promotes only the exact `TrimUI Brick Gamepad` autoconfig Menu event to Quit after collection. This preserves a hardware recovery exit when an external pad is Player 1. It changes frontend policy, not controller hardware configuration. |
| Audio | BlueALSA exposes an explicit ALSA PCM. RetroArch opens `audio_device` during audio initialization and does not safely reroute an active game. | The internal codec remains the global default. The service publishes a mode-0600 A2DP route only after BlueZ service resolution and a successful PCM open; its snapshot separately marks the selected live game-audio route so the shell never mistakes readiness for active output. The launcher validates and copies that route into the private game config. Missing readiness falls back to the speaker. A loss during play is explained on return and requires relaunch. SBC is the only product path; aptX remains unexposed. |
| Power | BlueZ `Powered` is the public adapter authority. Device evidence shows it reaches the XR829 reset/regulator/clock shutdown path. | Desired radio state is persisted. Suspend preserves that intent while the existing bounded suspend transaction powers the adapter down, checks it, and restores it after wake. Discovery is never automatic on resume. |
| Identity | Stock Allwinner systems obtain a stable board address from private storage or `sunxi-addr_mgt`; per-boot random fallback breaks bonds. | The already-landed early boot resolver preserves a valid address or deterministically derives a versioned local-unicast address from the immutable SID. There is no optional override. |

## Hardware-reference disposition

The XR829 UART node, stock initialization firmware/profile, stock coexistence
priorities, Bluetooth reset/wake sequencing, reference clocks, supplies, and
BlueZ power path remain unchanged. Stock and custom-driver spikes showed that
copying the stock packet priorities did not repair Low Energy discovery and
that the firmware already receives coexistence arbitration requests. No guessed
EPTA payload, priority escalation, listen interval, null/PS-poll template, or
other XR829 hardware setting is included in production.

The only new driver-level divergence is the targeted RetroArch recovery-input
patch described above. The kernel already declares and builds `UHID`, generic
HID, Microsoft, Sony, PlayStation, Nintendo, and xpad support; runtime tests,
not those declarations, determine accessory support.

## Primary source revisions

- RetroArch `v1.22.2`, commit `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576`: udev joypad driver, autoconfiguration, and player reservations.
- RetroArch joypad autoconfig commit `2e3b8a2728d5efd00fa0207d07ba2488b89e87b2`, pinned archive hash `0143f69b5b16ec14a0e09812c1c06501591440890b0220344e0432f08bc19b3a`.
- BlueZ Device API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst>
- BlueZ Agent API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst>
- BlueZ Battery API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Battery.rst>
- RetroArch controller autoconfiguration: <https://github.com/libretro/docs/blob/master/docs/guides/controller-autoconfiguration.md>
- RetroArch input drivers: <https://github.com/libretro/docs/blob/master/docs/guides/input-controller-drivers.md>
- RetroArch player reservation implementation: <https://github.com/libretro/RetroArch/blob/v1.22.2/tasks/task_autodetect.c>
- Android Bluetooth settings cached-device model: <https://android.googlesource.com/platform/frameworks/base/+/master/packages/SettingsLib/src/com/android/settingslib/bluetooth/CachedBluetoothDevice.java>

## Qualification boundary

The implementation and deterministic host fixtures can be completed in-tree.
Release claims still require the physical matrix and external measurements:
Xbox, PlayStation and 8BitDo controllers; SBC headsets; two-controller play;
cold reconnect; 50 suspend cycles; long soaks; end-to-end audio latency;
underruns; RF range; and external-current confidence intervals. A missing
physical result is recorded as unqualified, never converted into a software
fallback or a hidden user setting.
