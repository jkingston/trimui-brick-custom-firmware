# Bluetooth spike results and implementation plan

Date: 2026-11-08

Device evidence was collected on Buildroot `brick-7.3.0-1-13-ga39b8b8`, Linux `7.3.0-brick-dev`, with the product shell running from the `brick-diag` boot directory. The product worktree was first updated to custom-firmware main revision `682c5d7` so the plan includes the current Wi-Fi and captive-flow architecture.

The device was returned to its original diagnostic state after the tests: Bluetooth powered off, `bluetoothd` and BlueALSA stopped, temporary files removed, no persistent Bluetooth identity created, and Wi-Fi passing traffic normally.

## Outcomes

| Outcome | Evidence | Decision |
| --- | --- | --- |
| XR829 transport initializes | The controller enumerated as manufacturer 1597, BR/EDR and LE capable, after applying a temporary runtime-only address. | Hardware transport is usable. This does not remove the identity prerequisite. |
| Production identity can be resolved without user recovery work | `/data/bluetooth/public-address`, stock `addr_bt`, and `xr_bt.conf` are absent from the current root filesystems, but the current kernel exposes this unit's immutable 256-byte A133 SID through read-only NVMEM. Allwinner's documented address manager supports chip-ID derivation. Stock and Android-based firmware consume its sysfs value; NextUI inherits stock; KNULLI's per-boot random fallback is a documented failure mode. | Architecture closed. Resolve JIT before HCI/BlueZ: preserve an existing valid identity on upgrade, otherwise use one fixed, versioned SID derivation. Never generate randomly on boot. Exact stock equivalence is optional compatibility research. |
| Radio transitions are reliable | Five of five off/on cycles succeeded. Off took 0.05–0.07 seconds; on took 4.33–4.40 seconds, and a later bonded-controller cycle took five wall-clock seconds. There is no rfkill class device. Source and runtime agree that BlueZ `Powered=false` invokes the XR829 shutdown callback: reset is asserted, device-wake is lowered, both regulators and both clocks are disabled, and the next enable reloads the stock firmware and reprograms the verified public address. | Use `Adapter1.Powered`, not rfkill, as the product control. Model `starting` and `stopping` as asynchronous states. This is a real hardware-off path, but its energy saving still needs an external meter. |
| One-shot command discovery works | `bluetoothctl scan on` returned after setting a filter, and BlueZ immediately ended the discovery session when that client exited. | Rejected. The product needs a long-lived D-Bus owner; command invocation and output parsing are not a backend. |
| Long-lived discovery works | A live owner produced `Discovering=yes`, ObjectManager device additions, and clean cancellation on owner exit. | Use BlueZ ObjectManager, PropertiesChanged, InterfacesAdded, and InterfacesRemoved signals. |
| Dual-transport discovery coexists with Wi-Fi | Control traffic had 0% loss and 8–13 ms average latency. True scans produced 16–20% loss, 212–324 ms averages, and peaks of 781–1077 ms; another run disrupted traffic enough to abort its comparison. | Rejected for automatic or background scanning. |
| Classic-only discovery improves coexistence | BR/EDR-only discovery had 0% loss but 273 ms average latency and an 852 ms peak, versus a 10.6 ms control average. | Still unsuitable for background scanning, but preferable for the first explicit search for headsets and classic controllers. |
| Low Energy-only discovery improves coexistence | With Wi-Fi power save off, LE-only discovery produced 60–70% packet loss in the first tests and 96–100% after the stock EPTA priority spike. Wi-Fi recovered immediately after discovery stopped. | Rejected as an automatic scan and as a user-visible transport choice. BLE remains necessary for BLE-only accessories, but it must be an internal bounded phase of one search action. |
| Wi-Fi power save fixes coexistence | With power save on, idle Wi-Fi latency rose from 7.6 ms to 71.9–87.7 ms. LE scanning completed four of four runs without loss, but a forced reconnect then remained in `SCANNING` for ten seconds. With power save off, the same 60/30 scan allowed association while discovery remained active. | Rejected globally and temporarily. Keep the product's power-save-off baseline; reduced scan duty supplies the useful mitigation without a stateful Wi-Fi override. |
| Stock transmit priorities fix coexistence | A test driver restored the stock management/data/video/voice/EAPOL priorities. Classic discovery still averaged 241–250 ms and LE discovery lost 98–100% of Wi-Fi packets. | Correctness parity is useful, but this does not fix discovery. Do not raise all Wi-Fi traffic above the stock priorities: that would merely move starvation to Bluetooth. |
| Stock internal-rate MIB fixes coexistence | Firmware accepted MIB `0x100f`; Classic discovery still averaged 226–252 ms and LE discovery still lost 100% of packets. | Keep this separate from product policy. It is stock parity, not evidence of an improved schedule. |
| Firmware receives Bluetooth arbitration requests | Live MIB `0x1060` statistics showed Bluetooth wins and losses, an active real-time link, pending WLAN traffic, and WLAN software/hardware priority 4 during LE discovery. One live run lost 85% of pings. | The coexistence input is present. The problem is an unfair firmware/hardware schedule, so do not invent an unverified GPIO or host-only priority scheme. |
| Reduced LE scan duty mitigates disruption | The stock defaults were 11.25 ms interval and window: 100% receive duty. With power save off, 60/30 produced 0%, 6%, and 0% loss in the first trials and a later 100-packet run had 0% loss, 44 ms average latency, and the same eight observed addresses as a one-third-duty comparison. A 20–25% window began losing observations. | Adopt 60/30 as the discovery-only default, subject to known-device coverage, throughput and energy qualification. Do not add a Wi-Fi power-save override. |
| Passive LE scanning avoids the conflict | At 100% duty, a passive scan still lost 99% of Wi-Fi packets. At 60/30, passive and active scans had comparable Wi-Fi results (6% versus 2% loss), while active scanning returned scan-response metadata that passive scanning missed. | Rejected. Radio receive occupancy, not active scan requests, dominates the conflict. Keep BlueZ active discovery and control duty instead. |
| The mitigated scan permits Wi-Fi association | With power save off, active 60/30 and 60/20 scans remained running, returned eight or nine devices, and allowed forced Wi-Fi reconnects in about two to three seconds. Three further reconnects during one continuous 60/30 scan completed in about 9.25, 0.25, and 2 seconds; post-reconnect traffic had 0% loss and 10 ms average latency. | Discovery is not a hard association blocker after duty reduction, but the first-connect tail is still too variable. Yield during Wi-Fi changes for deterministic UX, then resume the same user-owned search. |
| Coordinated discovery survives Wi-Fi reconnect | Three stop/reconnect/stabilize/resume cycles associated in about 0.25–2 seconds. Each resumed 60/30 scan had 0% packet loss, with 83–109 ms average latency. | Keep the stop-before-connect policy as a latency bound, not because association is impossible. It needs only Wi-Fi state observation; no power-save lease or cross-service setting mutation is required. |
| Pairing-agent lifetime is controllable | A long-lived `KeyboardDisplay` agent made the adapter pairable; pairable returned to false when the owner exited. Rapid replacement and competing pair operations produced `AuthenticationCanceled`. With one operation in flight, the host authorization request was accepted and the Brick completed bonding, service resolution and trust. Requesting a different capability while the first owner remained registered did not replace it. | One helper must own one agent for its lifetime. Serialize pairing per device, make cancellation idempotent, and never switch capabilities at runtime. Implement confirmation and service authorization as real product states. |
| Audio software is present | BlueALSA 4.3.1 ran as A2DP source with SBC, aptX, and aptX-HD enabled. A Fedora 44 host with a dual-mode controller and PipeWire A2DP sink was paired as a temporary receiver. SBC streamed at 48 kHz/16-bit. With the host's aptX plugin loaded temporarily, aptX-HD streamed at 48 kHz/24-bit and aptX at 48 kHz/16-bit. Both vendor-codec transports were active and decoded into the host PipeWire graph. | The explicit BlueALSA route, optional codec encoders, and actual audio transport work. Keep SBC as the first production baseline; the host fixture does not replace physical-headset latency, stability, volume, RF, or power qualification. |
| Default audio reaches Bluetooth | `aplay -L` exposed only the internal A133 codec as default. RetroArch has no `audio_device` override. Source inspection confirms that RetroArch opens the configured ALSA device only during audio initialization; an open failure continues the game without audio, and ordinary write recovery does not select another PCM. | Not implemented. Do not replace the system default with a Bluetooth-only PCM. Preflight a per-launch route and keep it fixed for the game session. |
| External controllers reach Linux input | A host-side HID-over-GATT fixture paired over LE, bonded, resolved services, created `/dev/input/event5` and `/dev/input/js1`, and delivered repeated `BTN_SOUTH` events through `hid-generic`. Three forced link drops reconnected without discovery or user action. Each reconnect destroyed and recreated the UHID/kernel input instance (`input6` through `input9` in the log), even when the `/dev/input` minor names were reused. | Kernel and BlueZ controller support work. Load `uhid` at boot. The shell input manager must rediscover by capability/identity on every add/remove event and must never retain a path, descriptor, or held-button state across a link drop. |
| External controllers hotplug into the shell | The shell held only `/dev/input/event2`, discovered by exact name `TrimUI Brick Gamepad`; its poll set is fixed for the session. | Not implemented. The proven external controller would not control the shell without an input-manager change. |
| RetroArch controller behavior is known | RetroArch 1.22.2's selected `linuxraw` joypad driver watches `/dev/input` with inotify and hotplugs `js*` nodes. Runtime `--features` confirms UDEV/EVDEV input support is compiled, but the image contains no installed autoconfiguration profiles. The built-in gamepad is `js0`, autoconfiguration is disabled, and only player-one button indices are fixed. | The production candidate is `udev` plus a reviewed profile set and explicit player assignment; compilation alone does not make that route usable. A physical two-controller in-game A/B remains a release qualification, not an architecture unknown. |
| Bluetooth audio CPU cost is bounded | Against a 30-second idle baseline of 1.34% aggregate system busy, 45-second streams measured SBC at 1.00% of one CPU in BlueALSA, aptX at 7.00%, and aptX HD at 7.13%. | Codec CPU cost is modest but aptX variants are about seven times SBC in this encoder. This is not an energy measurement. |
| Bluetooth power saving is measured | The battery driver exposed capacity and voltage but no current; the device was externally powered at 100%. | Not measured. An external meter and interleaved trials are required; voltage at full charge cannot resolve codec energy. |

## Follow-up risk spikes

### Shared-radio coexistence

The exact stock Linux 4.9 XR829 source was compared with the current driver and then ported in isolated spikes. Stock EPTA classification and the internal-rate MIB were accepted by the running firmware, but neither improved discovery. Read-only firmware statistics proved that Bluetooth arbitration requests reach the coexistence engine: during a live LE scan the firmware reported an active real-time Bluetooth link, pending WLAN traffic and priority-4 WLAN data, while Wi-Fi still lost 85% of pings. The defect is therefore scheduling fairness inside the firmware/hardware policy, not absence of the Bluetooth input.

The best comparable upstream designs reinforce that diagnosis without providing portable register values:

| Driver | Useful design | XR829 implication |
| --- | --- | --- |
| ath9k | Hardware PTA weights and bounded stomp levels arbitrate time-critical traffic. | Preserve the XR829 hardware/firmware arbiter; do not replace it with a user-space timing loop. |
| iwlwifi | Firmware notifications feed a policy using Bluetooth profile, Wi-Fi load/RSSI, aggregation, transmit power and antenna state. | The missing capability is richer live policy and documented firmware controls, not a higher static priority for every packet. |
| rtw88 | A stateful coexistence service reacts to scan, link, media, traffic, RSSI and Bluetooth-profile events and publishes channel information for AFH. | Model coexistence as event-driven state. Investigate whether XR829 exposes documented AFH/channel or profile inputs before proposing new commands. |
| brcmfmac | Critical coexistence operations are bounded state machines with explicit ownership and restoration. | Keep discovery ownership bounded and cancellable. Avoid a Wi-Fi setting transaction now that measurement shows it is unnecessary. |

Do not copy algorithms or raw values across silicon. Continue using stock XR829 behavior as the hardware target unless a measured change is better. Stock source defines EPTA configuration MIB `0x1011` but contains no payload structure or call site, so no guessed payload may be sent. It does expose a richer firmware-debug channel for EPTA timelines, RF ownership transitions, request priorities, grant duration, quota use and Bluetooth request classes. Port that read-only diagnostic channel before attempting further scheduler changes. Separately qualify the stock SDD-derived listen interval and null/PS-poll templates. Keep the existing read-only statistics for diagnosis; decide whether the priority and internal-rate parity changes belong in production only after ordinary Wi-Fi regression testing.

Controller configuration exposed the most useful mitigation. The installed BlueZ defaults used an LE discovery interval and window of 11.25 ms each, a continuous receive scan. A 60 ms interval and 30 ms window greatly reduced loss while retaining more observations than a 100/20 setting. These are also Linux's documented fast-scan constants, but discovery inherits the continuous General Discovery values unless BlueZ overrides them. The firmware worktree now sets `ScanIntervalDiscovery=0x0060` and `ScanWindowDiscovery=0x0030`; a device restart against that candidate configuration loaded exact management values `6000` and `3000`.

Active versus passive scanning isolated the mechanism. Both caused near-total Wi-Fi loss at 100% duty, and both improved similarly at 60/30. Active scanning additionally recovered scan-response metadata, so passive scanning is not the solution. A finer 50%, 40%, 33%, and 25% duty sweep showed substantial RF variance rather than monotonic latency improvement; 25% also observed fewer addresses. Sustained 60/30 and 60/20 runs both had 0% loss and saw the same eight addresses, with 44 ms and 55 ms average latency respectively. This does not prove equal known-device coverage, so retain 60/30 pending peripheral qualification.

The earlier association failure was caused by the temporary Wi-Fi power-save setting, not by 60/30 discovery alone. With power save off, 60/30 discovery stayed active while Wi-Fi associated and continued returning devices. Three repeated reconnects during one continuous scan took about 9.25, 0.25, and 2 seconds; stopping discovery before reconnect reduced the earlier three-cycle range to about 0.25–2 seconds. The service should still yield actual discovery whenever Wi-Fi begins association, roaming, validation or captive sign-in to bound latency, then resume the same user-owned search after a short stable period. It should not change Wi-Fi power save.

The product policy is one explicit, bounded **Find devices** action. The service may phase BR/EDR and BLE internally, but the UI must not expose radio transports, coordination pauses, or a technical network warning. Preserve results, show normal search progress and Cancel, and never search automatically. The 60/30 discovery default belongs in BlueZ configuration, so it does not need per-search mutation. The Bluetooth helper only observes Wi-Fi authority snapshots: it stops BlueZ discovery before a changing network state and resumes after stability. It never owns or changes Wi-Fi power policy. BlueZ UUID, RSSI, pattern and duplicate-data filters affect reported devices or D-Bus traffic; they do not change controller scan duty.

### RetroArch and BlueALSA routing

The exact BlueALSA PCM is `bluealsa:DEV=XX:XX:XX:XX:XX:XX,PROFILE=a2dp`. The predefined plugin is an ALSA software PCM rather than a kernel sound card, so its absence from `/proc/asound` and the default `aplay -L` list is expected unless a name hint is added. Opening the PCM is the useful readiness probe: BlueALSA acquires the A2DP transport when a playback client opens it, and the plugin rejects a missing, unavailable or not-yet-negotiated PCM.

RetroArch passes `audio_device` directly to its ALSA initializer. If the open fails it logs that it will continue without audio; it does not retry the internal codec. During playback it asks ALSA to recover underrun, interrupt and suspend errors on the same handle, not select another PCM. `CMD_EVENT_AUDIO_REINIT` exists, but only an explicit caller invokes it and changing the device during an exclusive game session would need a control path that the product does not have.

The implementation spike is therefore a per-launch contract, not a global ALSA default:

1. Treat a headset as ready only when BlueZ has the A2DP profile, `bluealsa-cli list-pcms` contains the matching playback PCM, and a short non-destructive open/close probe succeeds.
2. Write the validated fixed-format address into the mode-0600 session append config as `audio_device`; never accept a display name or arbitrary config text.
3. If readiness fails before launch, use the internal codec and show the fallback. Once a game starts, lock the route for that session. For the first release, headset loss means the game becomes silent until the user exits and reconnects; do not promise live speaker failover.
4. With a known headset, measure SBC first: 30 minutes of game audio, latency, underruns, volume, disconnect/reconnect, suspend/resume, failed launch readiness and speaker fallback. Qualify aptX variants only afterward.
5. If live switching is later required, spike a supervised RetroArch command interface or an audio session layer. Do not infer it from ALSA recovery calls.

### Host-controller audio fixture

The development host can be a useful deterministic A2DP receiver. Its controller is dual-mode BR/EDR + LE and supports discoverable, pairable, advertising and secure-connection modes. PipeWire exposes the Audio Sink service, so the Brick can treat it as headphones even though BlueZ reports the host's class and icon as a computer. Device classification must therefore use service capabilities, not the class, icon or display name alone.

The host appeared reliably in explicit BR/EDR discovery. Repeated combined discovery runs spent their bounded interval on Low Energy results and did not rediscover it, while a BR/EDR-only run found it immediately. This is direct evidence for the planned internal phased search: one user action must include a bounded Classic phase and a bounded Low Energy phase while presenting one stable result list.

The host's installed PipeWire 1.6.8 build did not include aptX. For the spike, the RPM Fusion `pipewire-codec-aptx` 1.6.7 and Fedora `libfreeaptx` 0.2.2 packages were downloaded and unpacked under `/tmp`, without installing them. A temporary WirePlumber process loaded the codec module while the normal PipeWire daemon retained its system plugin path. The module's ABI was accepted and real audio decoded. The host was then restored to its ordinary WirePlumber service and all temporary packages, configuration, pairing state and aliases were removed.

Measured fixture results:

| Codec | Negotiated PCM | Active transport evidence | Short-run reported delay |
| --- | --- | --- | --- |
| SBC | 48 kHz, signed 16-bit, stereo | BlueALSA PCM ran and PipeWire routed `bluez_input` to the host output | Not captured while active |
| aptX HD | 48 kHz, signed 24-bit, stereo | BlueALSA selected `aptX-HD`; vendor codec `0xff` used Qualcomm vendor `0x000000d7`, codec `0x0024`; PipeWire decoded and routed audio | 111.4 ms |
| aptX | 48 kHz, signed 16-bit, stereo | BlueALSA selected `aptX`; vendor codec `0xff` used Qualcomm vendor `0x0000004f`, codec `0x0001`; PipeWire decoded and routed audio | 131.8 ms |

The delay values are BlueZ/BlueALSA transport reports from one short tone, not measured end-to-end latency and not a codec ranking. Repeat sustained, underrun and end-to-end latency measurements with physical headphones before setting codec policy. Automatic negotiation preferred aptX HD when both aptX variants were available. Plain aptX was forced by temporarily running the existing device BlueALSA binary with aptX HD disabled; the shipped init configuration was not changed.

A second sustained run used the same 48 kHz stereo signal for 45 seconds per codec, explicitly selecting each BlueALSA encoder. The idle baseline was 1.34% aggregate system busy. SBC used 1.00% of one CPU in BlueALSA and produced 2.04% aggregate system busy; aptX used 7.00% of one CPU and 4.36% aggregate busy; aptX HD used 7.13% of one CPU and 4.68% aggregate busy. `bluetoothd` stayed at 0.00–0.02% of one CPU. Temperature rose by 0.1 C for SBC, 0.7 C for aptX, and 0.5 C for aptX HD. Reported transport delay was about 151 ms for all three during these runs, demonstrating that the earlier 111.4 ms sample was neither stable nor an end-to-end result.

At 60 frames per second, 111 ms spans about 6.7 frames and 151 ms spans about 9.1 frames before adding application, ALSA and receiver latency. That is not a credible low-latency gaming result. SBC remains the production baseline; aptX and aptX HD may improve fidelity or interoperability but these measurements provide no latency reason to prefer them. The roughly 7% single-core encoder load is small on the four-core A133, but aptX variants are around seven times the measured BlueALSA CPU cost of SBC. Because the PMIC interface exposes no discharge current and the unit was USB-powered at full charge, no battery-life claim follows from CPU or temperature.

This fixture is credible for discovery, confirmation, authorization, bonding, service resolution, A2DP negotiation, PCM readiness, codec selection, streaming, disconnect and bond removal.

### Host-controller HID fixture

`tools/bluetooth/mock_ble_gamepad.py` now turns the development host into a real Low Energy HID-over-GATT gamepad. It is derived from the BlueZ 5.86 GATT server and advertisement contracts and exports Device Information, Battery, and HID services; HID information, report map, protocol mode, control point and input report characteristics; a report-reference descriptor; gamepad appearance; and live input notifications. The host adapter's peripheral and advertising capabilities are therefore exercised rather than inferred from UUID advertising.

The Brick found the host in an explicit LE phase, completed bonding and service authorization, resolved UUID `0x1812`, and subscribed to the input report. `CONFIG_UHID=m` and `CONFIG_HID_GENERIC=y` are already present in the running kernel. Loading `uhid` created `/dev/uhid`; BlueZ then created `/dev/input/event5` and `/dev/input/js1` for `Brick Test Controller`. `evtest` captured alternating `BTN_SOUTH` values 1 and 0 at one-second intervals. The kernel logged a Bluetooth HID gamepad bound through `hid-generic` at the host's address.

The fixture also exposed four product details. The host's generic GATT Device Name (`minipc`) replaced its advertisement name after service resolution, so the UI must keep its user-facing identity stable and classify the device from HID service/capabilities rather than the late name. Pairing required an explicit service-authorization decision on the host; one long-lived product agent must represent that state instead of auto-accepting it. Three forced link drops automatically reconnected, but each recreated the UHID instance and kernel input object (`input6` through `input9`). Finally, the host is dual-mode: after a radio restart, a generic `Device1.Connect` selected its Classic services instead of proving HOG reconnect. Product reconnect logic must be profile-aware, and cold reconnect remains a physical-controller test.

The Low Energy controller path is now credible through Linux input, including ordinary link-loss recovery. Remaining controller work is shell input hotplug, normalized mappings, player assignment, cold reconnect, suspend/resume, multiple controllers and physical-accessory coverage. Classic HID still requires a physical controller or a separate fixture with HID SDP plus control and interrupt L2CAP channels.

### Controller hotplug and assignment

The device kernel supplies `joydev`, HIDP, UHID and generic HID. The built-in gamepad is both `event2` and `js0`. `UHID` is a module and was not loaded at baseline; load it from the production image before starting BlueZ so HID-over-GATT devices work without a manual step. There is no `/dev/uinput` and the running kernel does not enable `CONFIG_INPUT_UINPUT`, but the completed host fixture does not need it: BlueZ uses `/dev/uhid` to deliver the remote HID report descriptor and reports to the kernel.

There are two independent gaps:

- The shell opens only the built-in `event2` and never rebuilds its poll set. Add a capability-based evdev manager that watches additions/removals, keeps built-in controls as recovery input, normalizes buttons/hats, and clears held/repeat state on removal and `SYN_DROPPED`. Reopen from the add event; a reconnected controller is a new kernel object even if the node name is reused.
- RetroArch hotplugs legacy `js*` nodes, but the built-in pad remains port zero, external pads receive later indices, autoconfiguration is off, and arbitrary controllers cannot be assumed to share the Brick's numeric button order. UDEV/EVDEV support is compiled, but no autoconfiguration profile directory is installed in the image.

Run a diagnostic A/B spike between the current `linuxraw` path and the already-compiled `udev` joypad driver. For the `udev` candidate, enable autoconfiguration, add an explicit Brick built-in profile, install only reviewed upstream profiles for in-scope controllers, and set player assignment explicitly in the per-session append config. Acceptance requires connect before launch, shell hotplug, in-game hotplug, disconnect without stuck input, reconnect to the same assignment, two controllers, suspend/resume and guaranteed built-in recovery. The likely handheld default is built-in controls plus the first selected external controller both controlling player one for single-player games; multiplayer assignment needs a separate explicit screen.

### Other unresolved release risks

| Risk | Current evidence | Resolution spike |
| --- | --- | --- |
| Production controller identity | The current userspace does not contain a factory file or legacy address-manager sysfs node, but the mainline kernel exposes a readable 256-byte A133 SID NVMEM device. Stock's DTS enables Allwinner address management and its attach binary consumes that result. | Implement and test one documented SID/address rule in the zero-touch early-boot resolver, with versioned provenance and atomic persistence. Exact stock derivation remains non-blocking compatibility research. |
| Pairing cancellation and daemon loss | A fixed long-lived agent works and the rapid replacement failure is now explained, but the product helper does not yet exist to own restart and cancellation state. | Keep one `KeyboardDisplay` owner, allow only one pairing transaction per device, and exercise every Agent1 callback, cancellation ordering, daemon restart and radio loss with known peripherals. |
| Suspend and cold reconnect | A bonded Low Energy fixture reconnected after three ordinary link drops. Radio off/on preserved the controller identity and bond, but the host fixture was not a clean cold-reconnect oracle: its dual-mode services merged under one address and its GATT application retained subscription state. No paired physical device has crossed suspend/resume or reboot. | Test controller and SBC audio across radio restart, service restart, reboot and repeated suspend cycles. Reconnect must not start discovery, and tests must assert the expected bearer/profile rather than a generic dual-mode `Device1.Connect`. |
| Bluetooth energy | The battery interface has no current measurement and USB power invalidates discharge inference. | Use an external meter and the paired-trial evaluator for radio off, idle on, connected controller, connected headset, playback, Classic discovery and 60/30 LE discovery. |
| Kernel coexistence diagnostics | Stock priority, internal-rate and read-only-statistics spikes ran on the device. The first two did not improve discovery; statistics exposed severe arbitration losses. | Retain the diagnostic branch, locate documentation for MIB `0x1011`, and qualify each prospective driver change independently against Wi-Fi and real Bluetooth links. |

## Baseline hardware and software evidence

- Device tree path `/soc/serial@5000400/bluetooth` declares `xradio,xr829-bt`, reset, host-wake, device-wake, reference clocks, and supplies.
- `hci_xradio`, `hci_uart`, `bluetooth`, and `rfkill` were loaded; firmware was `/lib/firmware/xr829/fw_xr829_bt.bin`.
- The driver reported the stock XR829 initialization profile, manufacturer 1597 and revision 3609. Its observed firmware address must not be used as the product identity: `hci_xradio.c` deliberately applies `HCI_QUIRK_INVALID_BDADDR` because stock replaces that address.
- BlueZ 5.86, BlueALSA 4.3.1, `dbus-send`, `dbus-monitor`, `gdbus`, libdbus, and GLib are installed.
- BlueZ exposes `org.bluez.Adapter1`, `AgentManager1`, `Device1`, ObjectManager, Media, GATT, and advertising interfaces on the system bus.
- Wi-Fi used the same XR829 on 2.4 GHz channel 6 with power saving off. The kernel log already contained recurring XR829 WLAN `missed interrupt` messages before Bluetooth testing, so coexistence work must inspect both the Bluetooth scan scheduling and the shared WLAN driver behavior.

## Recommended architecture

### Long-lived Bluetooth service

Add a small root-owned `brick-bluetooth` service rather than linking D-Bus policy into the framebuffer shell or invoking `bluetoothctl`.

The service should:

- keep one system-bus connection and one BlueZ ObjectManager cache;
- register one `org.bluez.Agent1` with `KeyboardDisplay` capability for its lifetime;
- own discovery sessions and always stop them on cancellation, client loss, page exit, game launch, suspend, or daemon shutdown;
- translate BlueZ properties and BlueALSA PCM availability into product states;
- expose a root-owned `SOCK_SEQPACKET` control socket under `/run/brick-bluetooth/`, following the generation, revision, request-id, snapshot, result, and stale-request conventions already used by Wi-Fi;
- keep Bluetooth addresses internal to the service and logs. Give the shell opaque bounded device identifiers and validated UTF-8 display names;
- persist BlueZ bonds through the existing `/var/lib/bluetooth` mapping to `/data`, and keep the separately versioned controller-identity record under `/data/bluetooth`. Identity is selected only by the early-boot resolver, never by the UI service.

Use GDBus or libdbus in the helper. Both are already present on the image. GDBus offers ObjectManager, properties, exported agent objects, and a main loop without requiring a new IPC design in Zig. The shell should remain independent of D-Bus and consume fixed-size, bounded snapshots through a Zig client matching `wifi_ipc.zig`.

### Discovery policy for the shared radio

The observed coexistence failure rules out background discovery.

- Search only while the Bluetooth page is visible or after an explicit Refresh action.
- Present one **Find devices** action. Internally start with a bounded BR/EDR phase and then run a bounded BLE phase when needed; transport names and radio workarounds are implementation details.
- Configure BlueZ's discovery-only LE defaults to the measured 60 ms/30 ms policy. Keep Wi-Fi power save at the product baseline; the Bluetooth service must not invoke `iw` or request a temporary override.
- Yield actual BR/EDR or BLE discovery while Wi-Fi associates, roams, validates connectivity, or opens captive sign-in. Keep the user-owned search and accumulated results alive, then resume after a bounded stable-link delay.
- Stop immediately when leaving the page, launching a game, opening captive sign-in, or receiving an explicit cancel.
- Preserve the current list while a refresh runs so rows do not move under the user's thumb.
- Do not make the adapter discoverable merely to discover accessories.
- Treat Wi-Fi latency, loss and throughput plus discovery completeness as acceptance metrics. A lower-duty scan is only a mitigation, not evidence that coexistence is fixed.

Open a base-firmware investigation for the XR829 coexistence behavior. Compare stock firmware and relevant custom firmware, then test firmware scheduling, WLAN power-save interaction, scan transport, scan window/interval controls if the controller exposes them, and current xradio missed-interrupt behavior. Preserve stock radio settings unless measurements justify divergence.

### Pairing and authentication

Keep the adapter non-pairable except during an explicit user-owned pairing operation. The helper's fixed `KeyboardDisplay` agent must implement:

- confirmation of a six-digit code;
- entry of a passkey or legacy PIN using the existing on-screen keyboard components;
- display of a passkey that must be entered on the accessory;
- authorization, cancellation, and agent release;
- `Device1.CancelPairing` when the user backs out.

Pair only the selected opaque device ID. Mark it trusted only after successful pairing and required service discovery. Disconnect must preserve pairing; Forget must disconnect and call `RemoveDevice`, with confirmation. Agent callbacks and BlueZ property changes can arrive in either order, so the helper must make all completion and cancellation paths idempotent.

### Audio routing

Keep the internal codec as the system default. When a selected paired audio sink has a BlueALSA A2DP PCM:

1. Prefer SBC for the first supported path; qualify optional codecs separately.
2. Generate a mode-0600 runtime RetroArch append configuration containing an explicit `audio_device = "bluealsa:DEV=…,PROFILE=a2dp"`.
3. Call the device “audio ready” only after BlueZ reports the relevant profile connected, BlueALSA lists the PCM, and opening the PCM succeeds.
4. Before game launch, fall back to the internal codec if the selected PCM cannot open and tell the user what happened.
5. During a game, do not claim live failover. RetroArch does not select another ALSA PCM automatically; the first implementation should explain before launch that headset loss requires exiting the game to reconnect or switch to the speaker.

Do not install a global `pcm.!default` pointing at BlueALSA: it makes internal audio dependent on a connected accessory and does not provide a trustworthy failover mechanism.

### Controller input

The shell needs a dynamic input manager before controller support is exposed:

- keep the built-in gamepad open and authoritative for recovery;
- watch input-device additions and removals, inspect capabilities rather than names alone, and add eligible gamepads to the poll set without restarting the shell; treat every add as a new object even when a node path is reused;
- clear held/repeat state on removal or `SYN_DROPPED` so disconnect cannot leave stuck navigation;
- map common evdev buttons and hats through a normalized action layer;
- ignore keyboards, power, volume, vibration, and sensor devices;
- show “controller connected” only after an eligible evdev device is open and producing a usable mapping.

RetroArch must be qualified independently. Decide player order before enabling autoconfiguration. The recommended default is that the built-in controls remain available, while the first external controller can control player one for single-player games; multiplayer assignment should be explicit and stable across reconnects. Validate the chosen rule with at least one classic and one Low Energy controller.

### Power and suspend

`Adapter1.Powered=false` is confirmed to reach the driver's full hardware-off callback; it is not a cosmetic software state. Radio-on current, connected-idle current and the actual saving from that callback remain unmeasured. Use the existing paired-trial evaluator with an external meter for radio off, radio on idle, connected controller idle, connected headset idle, audio playback, and explicit discovery. Do not infer savings from voltage at 100% charge.

Before suspend, stop discovery and disconnect active profiles cleanly. On resume, restore the user's desired radio state and saved-device reconnect policy, allowing for the measured four-second controller startup. Automatic reconnect should be bounded and must not trigger a discovery scan.

## Implementation sequence

### Resolve identity automatically and establish the service boundary

- Specify fixed version-one test vectors for hashing the full SID, byte order, local/unicast bits, and reserved-value retries.
- Add the JIT early-boot identity resolver before HCI/BlueZ: preserve an already valid identity on upgrade, otherwise derive the version-one value from SID.
- Persist the address atomically and verify the applied address. Keep the version in the fixed derivation domain and its test vector; do not add an override or a second provenance file.
- Add the helper package, init ordering, D-Bus ObjectManager cache, agent object, control socket, bounded protocol parser, and service restart behavior.
- Add host tests with a fake BlueZ bus and device tests for daemon loss and restart.

Completion means a clean SD image resolves the same identity on first boot, reboot, and reimage without user action; the radio can be turned on and off from the helper; a four-second startup is represented accurately; and the shell survives helper or BlueZ restart.

#### First-boot identity resolution

The official 1.1.1 update is universal and cannot contain a per-unit identity. Read-only extraction confirms that its root filesystem does not ship `/etc/bluetooth/xr_bt.conf`; the stock XR829 attach binary instead references `/sys/class/addr_mgt/addr_bt`, then the configuration file, and finally a random-address fallback. Stock's DTS enables `allwinner,sunxi-addr_mgt`. Allwinner documents burned secure/private storage and chip-ID derivation as normal sources below that sysfs boundary.

The mainline product kernel does not recreate the legacy `addr_mgt` class, but it already exposes the immutable A133 SID through the standard NVMEM framework. Live inspection found `/sys/bus/nvmem/devices/sunxi-sid0/nvmem`, read-only, 256 bytes, backed by `allwinner,sun50i-a100-sid` / `allwinner,sun50i-a64-sid`. Current boot arguments contain no `bt_mac`. This is sufficient for a zero-touch resolver without direct register access.

Use this order immediately before the first HCI startup:

1. Reuse a valid address already in `/data/bluetooth`, including an identity retained by an upgrade.
2. Otherwise hash a fixed domain string plus the full SID with SHA-256, take six bytes in a documented canonical order, and set the locally administered and unicast bits. Reject invalid and Bluetooth-reserved results by rehashing with a documented counter.
3. Store the address atomically before starting HCI. The fixed domain string and test vector define the algorithm version. Verify `hci0` reports it before BlueZ can create `/var/lib/bluetooth/<address>`.
4. Validate and apply that address on later boots. Missing `/data` is recoverable from SID; an existing valid address is never silently replaced.

Do not use the XR829 firmware placeholder, an address from another Brick, a neighbouring device's address, or a newly generated value on each boot. A Low Energy static-random address is not interchangeable with the public BD_ADDR programmed into this dual-mode controller.

### Add explicit discovery and the handheld list

- Integrate the existing snapshot-only Bluetooth screen with settings navigation.
- Implement saved, active, and nearby groups with stable focus and duplicate-name handling.
- Add one **Find devices** action with visible cancellation and bounded internal BR/EDR and BLE phases. Do not expose transport selection.
- Subscribe read-only to Wi-Fi authority state so discovery pauses before Wi-Fi association/validation and resumes only after stability.
- Record Wi-Fi ping and throughput during every device test.

Completion means discovery never outlives its UI owner, never starts in the background, and Wi-Fi degradation is documented and bounded by the accepted product rule.

### Complete pairing, reconnect, disconnect, and forget

- Implement every agent callback and authentication screen.
- Exercise successful, rejected, timed-out, cancelled, daemon-lost, and radio-lost pairing.
- Verify persistence across Bluetooth service restart and full device reboot using the preserved production identity.

Completion means saved state, link state, authentication state, and user-visible results remain consistent across all failure paths.

### Qualify Bluetooth audio

- Pair a physical SBC headset, then qualify PCM enumeration, open, playback, latency, underruns, volume, disconnect, reconnect, game launch, and speaker fallback.
- Repeat aptX and aptX HD with physical receivers. The host fixture proves codec negotiation and decode, not accessory interoperability or acceptable handheld latency.
- Add the per-session RetroArch audio override and explicit readiness probe.

Completion means sustained game audio works, audio readiness is never claimed from the link alone, and disconnect behavior is predictable.

### Qualify external controllers

- Load the existing `uhid` module before BlueZ starts and verify `/dev/uhid` exists.
- Implement shell input hotplug and normalized mappings.
- Decide and implement player assignment.
- Exercise connect before launch, connect in the shell, connect during a game, reconnect, two controllers, suspend, and wake.

Completion means the built-in controls always recover the UI, external devices do not leave stuck input, and shell and RetroArch mappings agree.

### Measure power and harden coexistence

- Run interleaved external-meter trials for all radio states.
- Retain the completed transmit-priority, internal-rate and read-only-statistics results; next qualify the association listen interval and templates independently, and investigate MIB `0x1011` only from an exact documented layout.
- Qualify the configured 60/30 LE discovery duty, with Wi-Fi power save off, against known-device coverage, throughput, cancellation and energy. Keep discovery mutually exclusive with Wi-Fi state changes to bound association latency.
- Re-run the complete Bluetooth and Wi-Fi matrices after any driver, firmware, scan-policy, or power-save change.

Completion means claimed savings are measured and the accepted discovery policy has explicit Wi-Fi latency and throughput limits.

## Unknowns closed by this spike

The remaining work is no longer blocked on a choice between Bluetooth transports, audio architectures, pairing-agent capabilities, or radio power APIs:

| Question | Closed outcome |
| --- | --- |
| Is Low Energy the controller route? | Support both HOG over Low Energy and Classic HID. The full HOG path and ordinary link-loss reconnect are proven; transport is not a user-facing choice. |
| Can Bluetooth really power down without rfkill? | Yes. `Adapter1.Powered=false` reaches the XR829 reset, regulator and clock shutdown path. Use BlueZ as the authority. |
| Can the shell retain an input node across reconnect? | No. Reconnect creates a new UHID and kernel input object. Re-enumerate dynamically and clear input state. |
| Which RetroArch driver is the production candidate? | UDEV/EVDEV with reviewed profiles and explicit assignment. The binary supports it, but the required profiles are not installed yet. |
| Should Bluetooth replace the default ALSA device? | No. Keep the speaker default and use a preflighted, per-launch BlueALSA PCM. |
| Should aptX be the first audio target? | No. Start with SBC. aptX variants negotiate, but cost about seven times SBC's encoder CPU and have no proven latency or energy advantage here. |
| How should discovery coexist with Wi-Fi? | One explicit bounded search, internal Classic then 60/30 Low Energy phases, paused during Wi-Fi state changes. Never run discovery in the background or expose the phases. |

Production implementation begins with the zero-touch identity resolver, not a manual recovery prerequisite. It has one normal rule: preserve a valid existing identity, otherwise deterministically derive the documented version-one identity from SID. Exact stock derivation is optional compatibility research and cannot silently change that result. The remaining product choices are the supported physical-controller matrix and multiplayer assignment policy; neither changes the service or input architecture above.

## Remaining physical tests

The host fixtures completed software-path checks for pairing and A2DP, including SBC, aptX and aptX HD, plus Low Energy HID through live evdev events. No physical headset or controller was qualified, so these outcomes remain open:

- authentication prompts and cancellation against real accessories with their actual I/O capabilities;
- saved-device reconnect after reboot;
- sustained BlueALSA playback, end-to-end latency, underruns, volume, RF range, codec fallback and route fallback on physical headsets;
- physical-controller evdev capabilities, HID mapping, player order, shell hotplug, and reconnect;
- Bluetooth behavior across suspend and resume;
- power consumption with an external meter.

Use known test peripherals and record their model and Bluetooth transport. Do not pair anonymous nearby devices.

## References

- BlueZ Device API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Device.rst>
- BlueZ Adapter API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Adapter.rst>
- BlueZ Agent API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.Agent.rst>
- BlueZ management API, including default system configuration: <https://github.com/bluez/bluez/blob/master/doc/mgmt-protocol.rst>
- BlueZ discovery scan interval/window configuration: <https://github.com/bluez/bluez/blob/master/src/main.conf>
- BlueALSA PCM plugins: <https://github.com/Arkq/bluez-alsa/blob/master/doc/bluealsa-plugins.7.rst>
- BlueALSA PCM D-Bus delay semantics: <https://github.com/arkq/bluez-alsa/blob/master/doc/org.bluealsa.PCM1.7.rst>
- Bluetooth SIG HID over GATT Profile 1.2: <https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/hogp_v1-2_1777405843/HOGP_v1.2/out/en/index-en.html>
- BlueZ GATT application API: <https://github.com/bluez/bluez/blob/master/doc/org.bluez.GattManager.rst>
- RetroArch Linux input drivers: <https://github.com/libretro/docs/blob/master/docs/guides/input-controller-drivers.md>
- Linux wireless Bluetooth coexistence overview: <https://wireless.docs.kernel.org/en/latest/en/users/documentation/bluetooth-coexistence.html>
- ath9k hardware coexistence: <https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath9k/btcoex.html>
- Intel iwlwifi coexistence implementation: <https://github.com/torvalds/linux/blob/master/drivers/net/wireless/intel/iwlwifi/mvm/coex.c>
- Realtek rtw88 coexistence implementation: <https://github.com/torvalds/linux/blob/master/drivers/net/wireless/realtek/rtw88/coex.c>
- Broadcom brcmfmac bounded coexistence state machine: <https://github.com/torvalds/linux/blob/master/drivers/net/wireless/broadcom/brcm80211/brcmfmac/btcoex.c>
- Steam Deck Bluetooth pairing and **Show all devices** fallback: <https://help.steampowered.com/en/faqs/view/69E3-14AF-9764-4C28>
- Android saved/available device and explicit pairing flow: <https://support.google.com/android/answer/9417604>
- Nintendo Switch controller and Bluetooth-audio limits: <https://en-americas-support.nintendo.com/app/answers/detail/a_id/22424/>
- Stock Tina XR829 source used for the EPTA comparison: `/home/jack/workspace/trimui-brick/firmware-research/linux-4.9.191-a133.tar.xz`
- Stock XR829 firmware provenance: <https://github.com/REG-Linux/xr829-firmware>
- Local XR829 implementation: `brick/linux/drivers/bluetooth/hci_xradio.c`
- Local identity gate: `brick/firmware/package/brick-bluetooth-identity/`
- Allwinner address-manager source hierarchy and chip-ID mode: <https://bbs.aw-ol.com/topic/768/faq-wi-fi-bt-mac%E5%9C%B0%E5%9D%80%E5%AE%9A%E5%88%B6>
- KNULLI Brick per-boot random-address bug and bond impact: <https://github.com/knulli-cfw/distribution/issues/453>
