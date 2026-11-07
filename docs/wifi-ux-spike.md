# Wi-Fi UX spike results

Status: production integration. The spike model became the single shippable
implementation: the shell uses it in Settings and the in-game pause menu, and
the firmware authority described in the production plan is the only mutable
Wi-Fi control path.

## What the spike proves

The product model in `src/wifi.zig` parses whole immutable snapshots with an
authority generation and revision. It represents radio, connectivity and
stage-specific network outcomes independently; keys focus by a stable logical
network identity; freezes row order while the user navigates; accepts value
updates without moving the focused row; and rejects old snapshots. Raw SSID
bytes are either valid UTF-8 or rendered as a lossless `\xNN` sequence, so two
malformed names cannot collapse into the same replacement-character label.

The flow model in `src/wifi_flow.zig` exercises controller-only toggle, refresh,
saved/open/WPA2 joins, hidden SSID and security entry, password recovery,
disconnect, retry, captive launch, auto-connect, private-address, information
and confirmed Forget actions. Credentials and hidden names live in bounded
buffers, are never formatted by the UI, and are securely zeroed after send,
cancel or successful recovery. A recoverable authentication failure retains
the transient password only until edit, cancel, success or authority restart.

`src/wifi_ipc.zig` proves the shell/authority seam with Unix
`SOCK_SEQPACKET`: one command, result or snapshot is one packet. Commands carry
the authority generation and a stable request ID. Stale commands have an
explicit non-mutating result. The descriptor can join the existing poll loop,
so scans and joins do not run on the input/render path. The contract deliberately
contains product states rather than supplicant events.

The native renderer now covers the picker, off and radio-error states, network
actions, password OSK, hidden-name and security entry, open-network warning,
connection information and Forget confirmation. The keyboard is one compound
element, keeping the fixed 48-element tree bound. Deterministic renders live in
`output/wifi-spike` during development and all states are part of the screenshot
task.

## Acceptance coverage and MVP boundary

| Scenario from the UX design | Shell evidence | Production status |
| --- | --- | --- |
| Off/on/scan/WPA2/validation/Internet | Model, command and render paths | Authority/device path passed; classifier runs automatically after association |
| Wrong password/edit/success | Transient retry-secret test | Supplicant temporary-disable maps to authentication failure |
| Open join/captive/success | Confirmation and `open_captive` command | Wired to the single qualified WPE chain |
| Captive auto-join during game | Deferred notice design only | Excluded from MVP; in-game Network remains explicit |
| Captive cancel/choose another | Qualified browser cancel plus network flow | Implemented by WPE supervisor and picker |
| Local, limited and captive separation | Distinct connectivity and row states | Bounded CAPPORT/HTTP/HTTPS classifier installed with curl/CA dependencies |
| Disconnect suppresses immediate auto-join | Explicit command | Supplicant `DISCONNECT` holds until an explicit reconnect/select |
| Atomic Forget | Confirmed generation-bound command | Delegates to the durable Forget transaction |
| Scan update without focus jump | Frozen-order and stable-identity tests | Runtime poll integration applies immutable revisions |
| One ESS row and silent roam | Model consumes logical rows | Authority groups scan BSSIDs by SSID/security; radio policy remains in supplicant |
| Failed roam/recovery copy | `reconnecting` state | Qualified driver/service recovery path retained |
| Off/on has no stale list | Off/error render and item-count tests | Fresh authority snapshot; old scan results rejected in supplicant |
| Independent restarts | Generation/revision/stale contract | Shell reconnect and authority generation boundary implemented |
| Unicode, duplicate and malformed SSIDs | Parser tests and escaped fallback | Byte identities retained; firmware all-zero hidden rows suppressed |
| D-pad/A/B/Y and OSK only | Flow state-machine tests and compound OSK | Same production flow is reachable in Settings and in-game |

## Closed decisions

There is one production architecture: the shell owns presentation and focus;
one out-of-process authority owns policy, credentials after submission,
supplicant/DHCP/connectivity state and captive-session eligibility; the existing
WPE captive implementation owns only contained web interaction. The shell does
not invoke synchronous Wi-Fi helpers and the page cannot declare Internet
success.

`SOCK_SEQPACKET` is selected over a byte stream because snapshot atomicity is a
contract requirement and the bounded packet size is small. The protocol stays
textual and hex-encodes untrusted strings for auditable spike fixtures; a later
binary encoding is not required for correctness and would add another decision.

## Production cut-over evidence

The runtime descriptor is part of the shell poll set and reconnects across
authority restarts. Settings and the in-game Network entry open the same flow.
The C authority implements generation/revision rejection, per-client request
replay, ESS grouping, credential/profile transactions, structured connection
information and delegation to the durable private-address, Forget,
connectivity and captive services.

Host verification on 2026-11-07: all 63 shell tests pass; formatting and static
analysis report no warnings; the ReleaseSafe AArch64 shell and authority build
through the composed Buildroot graph. On the attached Brick the production
shell connected to the authority, off persisted and stopped supplicant with
WLAN rfkill blocked, on restored the radio, enabled stale-scan rejection and
reconnected the saved WPA2 network in two seconds. Live XR829 encodings for
`WPA-PSK WPA-EAP`, `[SAE-H2E]` capability and all-zero hidden SSIDs are covered
by authority regression tests.
