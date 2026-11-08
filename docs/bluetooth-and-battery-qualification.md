# Bluetooth and battery qualification

The device results and implementation decisions from 2026-11-08 are recorded in `bluetooth-spike-results.md`. Where this earlier qualification plan is still phrased as an open question, the measured result takes precedence.

This document turns the Bluetooth and battery research into executable decisions. It does not claim device behaviour from host tests. The device became available on 2026-11-08 and the bounded radio spikes recorded in `bluetooth-spike-results.md` were completed. Future device work must still confirm exclusive ownership first and restore the captured baseline afterward.

## Evidence already established

- The base image builds the Linux Bluetooth and HID support, BlueZ, and BlueALSA. Declared support is not proof that pairing, audio, or controllers work on this board.
- The inspected runtime had a Bluetooth controller, `bluetoothd`, and BlueALSA, but the controller was off, there was no pairing agent, and no paired devices were present.
- The inspected runtime did not expose a Bluetooth ALSA route through the default PCM. A Bluetooth link must therefore not be presented as “audio ready.”
- A host HID-over-GATT fixture completed pairing, service resolution, kernel binding and live evdev input. `UHID` is already built as a module but must be loaded by the production image. This proves the Low Energy input path, not shell hotplug or physical-controller compatibility.
- Sustained codec trials measured BlueALSA at about 1% of one CPU for SBC and 7% for aptX and aptX HD. Reported transport delay varied from 111–152 ms and was not end-to-end. These are CPU and transport observations, not battery-life or acceptable-latency evidence.
- The inspected runtime was externally powered at 100%, did not expose battery current, used the balanced CPU profile, had Wi-Fi power saving off, turned the screen off after five minutes, and never suspended automatically. Those observations do not establish battery life or drain.
- The stock hardware configuration remains the target unless a measured result supports a divergence.

## Product decisions that can proceed without hardware

Bluetooth belongs on one combined settings page with an explicit radio switch, saved devices before nearby devices, and one explicit bounded **Find devices** action. BR/EDR and BLE phases are backend details and must not be presented as user choices. Selecting a nearby device pairs it; selecting a saved device connects it; selecting a connected device disconnects it. Forget is separate and destructive. Pairing, connection, discovery, and radio transitions must be cancellable.

This follows the strongest common handheld patterns without copying their hardware assumptions. Android separates saved devices from available devices and makes pairing or refresh explicit. Steam Deck pairs directly from one Bluetooth list and offers **Show all devices** only as a fallback when useful devices are filtered out. Nintendo surfaces actual accessory-count conflicts at the action that cannot proceed instead of exposing coexistence mechanics. For Brick, show connected and saved devices first, then likely controllers and audio devices found by the current search. Offer **Show all devices** only after a completed search when the expected accessory is missing. Never show Classic, Low Energy, scan duty, Wi-Fi power save, or an internal discovery pause. If later peripheral tests establish a real simultaneous-device limit, explain that concrete limit only when the user reaches it.

The UI distinguishes these user-observable outcomes:

- Bluetooth unavailable, off, turning on, on, turning off, or unable to start.
- Looking for devices or device search failed.
- Nearby, saved, pairing, connecting, connected, preparing audio, audio ready, disconnecting, or connection failed.
- Controller connected is not the same outcome as controller usable by the shell and emulator.

The host-tested form of this contract is in `src/bluetooth.zig`. It intentionally sits above BlueZ properties. A later adapter should consume BlueZ D-Bus events rather than poll command output. The relevant BlueZ device contract is `org.bluez.Device1`; pairing requires an agent and cancellation maps to `CancelPairing` or cancellation of the owning operation.

The same contract has host-only UI snapshots for Bluetooth on, off, pairing, and failure. They are renderable with the shell's `--snapshot` command and are not connected to product navigation. This keeps the interaction available for review without presenting unqualified hardware support to users.

Battery changes are admitted only after paired, repeated measurements. `src/battery_trials.zig` normalizes energy by duration and rejects missing, short, inconsistent, or immaterial results. Three pairs is a minimum screen, not statistical proof; marginal results require longer runs and more repetitions.

## Device work, in safe order

Each activity begins with a read-only capture of the stock or current runtime state and records the firmware commit, kernel commit, configuration, ambient conditions, battery state, and peripherals. Stop if another session owns the device.

### Bluetooth radio and pairing

Use a disposable audio device and controller. Capture controller identity, rfkill state, BlueZ adapter properties, daemon arguments, logs, and D-Bus signals. Exercise radio on/off, bounded discovery, pairing, cancellation at each in-progress state, reconnect after reboot, disconnect without forgetting, forgetting, incorrect or rejected authentication, and radio loss.

Accept only if every UI state follows an observed D-Bus state, cancellation returns promptly, saved devices remain saved after disconnect, and no secret or device address is written to logs unnecessarily.

Resolved by device spikes:

- The board uses the XR829 over UART with the extracted stock Bluetooth firmware and initialization profile. The running driver and firmware complete real BR/EDR, Low Energy, A2DP and HOG paths.
- No rfkill class device is registered. BlueZ `Adapter1.Powered=false` is nevertheless a hardware-off operation: the XR829 driver asserts reset, lowers device-wake, disables both radio supplies and clocks, and reloads firmware on the next enable.
- One long-lived `KeyboardDisplay` agent is the correct product owner. It covers confirmation, passkey entry/display and service authorization; changing capability at runtime introduces cancellation races.
- Discovery severely disturbs the shared XR829 Wi-Fi radio. One bounded foreground search with internal Classic and 60/30 Low Energy phases is the accepted mitigation; discovery pauses during Wi-Fi state changes and is never exposed as a transport choice.

Remaining questions require production identity or physical accessories: cancellation against each real I/O capability, persistence across daemon restart and reboot, and the energy difference between powered-off and powered-idle states.

Risks include an apparent software success with a nonfunctional radio, an uncancellable BlueZ request, stale saved-device state, address leakage, and radio coexistence regressions.

### Bluetooth audio routing

The host-controller fixture has already proved real SBC, aptX, and aptX HD negotiation and decoded streaming through the device's BlueALSA build. That removes basic codec availability as an unknown, but does not qualify an accessory. Pair one physical SBC headset first. Capture BlueZ services, BlueALSA PCM enumeration, selected codec, sample format, underruns, reconnect behaviour, volume behaviour, end-to-end latency, RF range, and routing before and after emulator launch. Then repeat with physical aptX and aptX HD receivers; do not make a codec the default merely because the host fixture negotiated it.

Use the selected device's explicit BlueALSA PCM in a per-launch RetroArch append config and leave the internal codec as the system default. Verify that the preflight falls back to the speaker before launch, that the speaker is not silently active during private listening, and that headset loss during a game follows the documented silent-until-exit behavior.

Accept only when the shell says “audio ready” after the PCM is usable, RetroArch produces sustained audio, pre-launch failure selects the speaker predictably, and repeated reconnects do not require restarting the shell.

Resolved by software and device spikes:

- Keep the internal codec as the system default. Preflight the selected BlueALSA PCM and pass an explicit `audio_device` in the per-launch RetroArch append config. Lock that route for the game session; a lost headset becomes silent until exit in the first release rather than silently switching speakers.
- SBC, aptX and aptX HD all negotiate and carry decoded audio through the board's current BlueALSA build. SBC is the baseline because the host fixture gives no latency reason to prefer aptX and the aptX encoders used about seven times SBC's measured BlueALSA CPU.

Physical headsets must still establish end-to-end latency, underrun rate, volume semantics, codec fallback, RF range and energy. The host's 111–152 ms transport reports are not end-to-end and are already too large to market as low-latency gaming.

Risks include claiming success at link establishment, silent playback, excessive latency, codec-specific instability, simultaneous speaker output, and a route that disappears while a game is running.

### External controller behaviour

The host fixture has proved the Low Energy HID-over-GATT path through `/dev/uhid`, `hid-generic`, `/dev/input/event5`, `/dev/input/js1`, and live `BTN_SOUTH` events. Load `uhid` automatically in the production image. Next pair representative physical Bluetooth Classic and Bluetooth Low Energy controllers and record identity, capabilities, reconnect identity, and mappings. Exercise connection before shell launch, connection while browsing, connection while playing, two controllers, disconnect, sleep, and wake.

Accept only when controller discovery is dynamic, the built-in controls remain available, mappings are deterministic, and reconnect does not duplicate or reorder players unexpectedly.

Resolved by the host-controller spike:

- Low Energy HOG is an appropriate controller route and works through BlueZ, UHID, `hid-generic`, evdev and joydev. It complements rather than replaces Classic HID because real controllers use both transports.
- Reconnect creates a new UHID and input object even if `/dev/input/event*` or `js*` numbers are reused. The shell must watch add/remove events, match capabilities plus the service's stable opaque identity, reopen the device, and clear held/repeat state.
- RetroArch has UDEV/EVDEV support compiled, but the image has no controller profile set. Production needs reviewed profiles and explicit player assignment; merely selecting `udev` is insufficient.

The remaining product choices are the supported controller matrix and multiplayer assignment policy. The recommended default is built-in controls plus the selected external controller as player one for single-player use, with an explicit assignment screen for multiplayer. Physical two-controller, Classic HID, cold reconnect and suspend tests remain mandatory.

Risks include hard-coded input identity, incorrect player order, hotplug loss, stuck input after disconnect, and different behaviour between the shell and RetroArch.

### Deep sleep qualification

First capture wakeup sources, regulator states, clocks, CPU idle states, suspend logs, and current on external power and battery. Run repeated suspend/resume cycles with no radios, Wi-Fi connected, Bluetooth audio connected, a controller connected, SD activity quiesced, and low battery. Measure current after the system has settled, not just immediately after writing a suspend state.

Accept automatic suspend only if wake is reliable, storage remains intact, input works, display and audio recover, and settled power is materially below screen-off idle. Until then, keep “Sleep” classified as unfinished support rather than a battery improvement.

Open questions:

- Which power state is implemented by the stock firmware and PMIC?
- Which key is a reliable wake source?
- Do the display, audio codec, SD interface, Wi-Fi, and Bluetooth resume without reinitialization?
- What is the settled current and time to settle?

Risks include data corruption, a device that cannot wake, a nominal suspend state that saves little power, and radio or display failure after resume.

### Wi-Fi power saving and scan cadence

Measure identical idle, browsing, download, and streaming workloads with the inherited setting and each candidate. Record RSSI, throughput, latency distribution, reconnects, external energy, and logs. Test Bluetooth coexistence separately. Compare continuous scanning with bounded foreground scans and event-driven background status updates.

Accept a change only when repeated energy measurements clear the material-savings threshold without unacceptable latency, throughput, reconnect, captive-portal, or Bluetooth regression.

Open questions:

- Does the xradio driver implement the requested power-save mode correctly on this board?
- Which setting persists across reconnect and reboot?
- How much energy is scan cadence actually costing?
- Does power saving create controller or audio interference?

Risks include configuration that reports enabled but changes no hardware state, poor latency, unstable association, shared-radio regressions, and measurements dominated by screen or charging behaviour.

### Display, CPU, LEDs, and idle services

Measure each option independently before composing them: lower default brightness, shorter screen-off choices, power-saver CPU policy in menus, automatic profile changes around game launch, LED policy, and removal or deferral of periodic background work. For CPU changes, record actual clocks, parent/divider behaviour, governor transitions, frame pacing, input latency, temperature, and energy for light and demanding games.

Accept only changes that preserve the selected user setting, restore state after failures, and show repeatable material savings for the intended workload. Avoid an estimated “time remaining” display until discharge current and a calibrated capacity model are available; percentage and charging state are the honest outputs.

Open questions:

- Which workloads can use the power-saver profile without visible latency?
- Are current frequency limits inherited stock behaviour or temporary bring-up values?
- Which backlight curve gives useful low-end steps?
- Are any periodic services waking the system after the display is off?

Risks include frame pacing regressions, misleading frequency settings, unreadable defaults, profile state stranded after a crash, and additive changes whose combined result differs from isolated trials.

## Measurement record

For each trial, record:

- Descriptive outcome name, hypothesis, exact changed setting, and why it differs from stock.
- Firmware, kernel, product-shell, and configuration revisions.
- Power source, battery percentage and voltage, temperature, display brightness, radios, peripherals, and workload.
- Meter model, sampling method, warm-up, duration, raw trace location, average power, and observed failures.
- At least three interleaved baseline/candidate pairs of at least ten minutes. Longer runs are required when the expected difference is small or the system is thermally drifting.
- Decision: missing measurement, measurement too short, improvement not repeatable, no material improvement, or measured improvement.

Do not combine several changes into one claimed saving until each has been isolated. Re-run the chosen combination because savings are not necessarily additive.

## References

- BlueZ device API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst>
- BlueZ adapter API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst>
- BlueZ agent API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst>
- BlueALSA PCM plugins: <https://github.com/Arkq/bluez-alsa/blob/master/doc/bluealsa-plugins.7.rst>
- Linux power-management testing: <https://docs.kernel.org/power/basic-pm-debugging.html>
- Linux CPU frequency policy: <https://docs.kernel.org/admin-guide/pm/cpufreq.html>
