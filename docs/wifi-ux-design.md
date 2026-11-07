# Wi-Fi UX design

Status: proposed interaction contract for the Brick shell. This document designs
the user-facing layer over the connectivity authority in
`brick/firmware/board/trimui/brick/WIFI-PRODUCTION-PLAN.md`; it does not change
the radio, roaming, security or captive-browser qualification gates.

## Decision

Brick should behave like a small, controller-first mobile device rather than a
router administration screen:

* Settings exposes one **Wi-Fi** row with a short outcome: `Off`, `On`,
  `Sign-in required` or `No internet`.
* Opening it shows the Wi-Fi switch, one live status sentence, then one stable
  list of logical networks. The current network is first, followed by saved
  networks in range, then new networks by signal quality.
* A network row contains only its name, a plain-language state, signal and a
  lock/open indication. BSSID, channel, IP, DNS, MAC and protocol names do not
  belong in the picker.
* Selecting a new secured network opens password entry. Selecting a saved
  network connects. Selecting the current network opens its actions and
  details.
* Association is not presented as success. Brick briefly checks the usable
  path and then reports `Connected`, `Sign-in required`, or `No internet`.
* Captive login opens automatically after a user-initiated join when the shell
  is in the foreground. An automatic join never takes over a running game;
  instead it exposes `Sign-in required` in Settings and a non-modal notice at
  the next safe shell surface.
* Normal roaming stays invisible. Only a prolonged or failed handoff becomes
  `Reconnecting…`; the UI never promises seamless roaming.

This uses the shell's general page state machine, list geometry and controller
conventions. Wi-Fi gets its own product model because its connectivity,
credential, validation and captive-login states are not scalar settings.

## Research synthesis

The useful consensus across mobile devices and consoles is consistent:

* Android presents a fast network switcher and a fuller list; it marks secured
  networks with a lock, shows signal strength, remembers successful joins and
  keeps metered/randomized-MAC controls in network details. It also treats
  captive login as separate remediation from association.
* iOS keeps the join list sparse, auto-joins known networks, puts Auto-Join,
  Forget, private address, DNS and proxy behind per-network details, and keeps
  `Without Internet` distinct from leaving a captive network.
* Steam Deck's documented Game Mode path is intentionally short: Internet,
  choose network, use the on-screen keyboard. Valve's public documentation is
  not strong enough to use its captive behavior as a reference.
* Nintendo Switch is the strongest controller-first precedent: opening Internet
  Settings scans, `Y` scans again, choosing an SSID leads to password entry,
  then the console tests the connection. Manual setup is below the normal list.
* PlayStation shows new and saved networks together, uses a lock for protected
  networks and places manual/advanced configuration after the ordinary path.

Brick diverges where its hardware and product are smaller. It does not expose
manual network priority, Wi-Fi bands/BSSIDs, WPS, enterprise authentication,
WPA3, metered policy or editable IP/DNS/proxy in v1. Features that are not
implemented must not appear as inert controls.

## Information architecture

```text
Settings
└── Wi-Fi                         Off / On / Sign-in required / No internet
    ├── Wi-Fi switch
    ├── current, saved-in-range and available networks
    ├── Add hidden network
    └── Saved networks            only when an out-of-range profile exists
        └── Network
            ├── primary action    Sign in / Disconnect / Connect / Retry
            ├── Auto-connect
            ├── Private address
            ├── Connection info   read-only
            └── Forget network
```

There is no separate top-level `Internet` screen: Brick has no cellular path
and wired USB recovery is not a consumer network choice.

### Settings summary

The value is deliberately coarser than the Wi-Fi screen:

| Authority state | Settings value |
| --- | --- |
| `OFF`, `STOPPING` | `Off` |
| `STARTING`, `ASSOCIATING`, `LOCAL`, `ROAMING` | `On` |
| `CAPTIVE` | `Sign-in required` |
| `BACKOFF` with a saved/associated path but failed validation | `No internet` |
| `INTERNET` | `On` |

Do not put the SSID in the Settings list. Long or hostile names would make the
root settings layout unstable, while the outcome is what matters there.

Adding Wi-Fi makes six root settings rows. The current static settings geometry
fits five and would place the sixth under the footer, so this feature also
requires the root Settings list to use the existing choice-style visible-window
pattern. Do not squeeze typography or row height to make six rows appear at
once.

## Primary Wi-Fi screen

Use the shell's 1024×768 rhythm: a 92 px switch row, a status caption and at
most four 96 px network/action rows. Lists longer than the viewport scroll one
row at a time and keep the focused row anchored.

```text
Wi-Fi

  Wi-Fi                                                   On
  Connected to Alder House

  Alder House                             Connected     ▂▄▆█  lock
  Studio                                  Saved         ▂▄▆   lock
  Train WiFi                              Sign in       ▂▄     open
  Add hidden network                                      >

  B Settings                                      A Open
```

Network results update in place. While focus is moving, a scan may update
signal and state but must not reorder rows under the user. Reconcile ordering
after a short idle period or when the screen is reopened. Preserve focus by a
stable network identity, never by transient scan index.

Treat an ESS as one logical row: compatible BSSIDs with the same SSID/security
and credentials are backend candidates, not separate networks. The strongest
candidate supplies the displayed signal; roaming remains an implementation
detail.

`Y Refresh` is shown only when the authority can accept a foreground scan. The
screen performs one scan on entry, so Refresh is recovery, not a required step.
When associated-scan support is disabled or busy, retain the existing list and
omit the affordance rather than showing a control that cannot work.

### Row ordering

1. Current network, including connecting, captive, limited and reconnecting.
2. Saved networks currently in range, ordered by the authority's connection
   preference rather than raw RSSI alone.
3. New supported secured networks, then new open networks, by signal bucket and
   name. Avoid visibly resorting for one-bar fluctuations.
4. Unsupported networks remain selectable only when selection can explain the
   limitation. Otherwise omit them; unexplained disabled rows are a dead end.
5. `Add hidden network`, then `Saved networks` when applicable.

Duplicate display names with incompatible security remain separate logical
rows and receive a secondary label such as `Open network` or `Secured`.

### State copy

The shell consumes product states from the authority, not raw supplicant
events:

| Product state | Primary copy | Network-row copy |
| --- | --- | --- |
| Off | `Wi-Fi off` | no rows |
| Starting | `Turning Wi-Fi on…` | no rows yet |
| Scanning, no current network | `Looking for networks…` | previous results remain |
| Associating | `Connecting to {name}…` | `Connecting…` |
| Local / validating | `Checking the connection…` | `Checking…` |
| Internet | `Connected to {name}` | `Connected` |
| Captive | `{name} needs you to sign in` | `Sign-in required` |
| Limited | `Connected to {name}, no internet` | `No internet` |
| Roaming under the normal bound | retain `Connected to {name}` | `Connected` |
| Roaming beyond the normal bound | `Reconnecting to {name}…` | `Reconnecting…` |
| Authentication failure | `Check the password for {name}` | `Password incorrect` |
| Address failure | `{name} could not assign an address` | `Couldn't get address` |
| Unsupported security | `This network's security is not supported` | `Not supported` |
| Network disappeared | `{name} is no longer in range` | `Out of range` |
| Authority/radio failure | `Wi-Fi could not start` | no misleading results |

An operation that is still inside its measured normal time does not need a
spinner animation. The changing words are sufficient and cheaper to render.

## Join flow

### Saved network

`A Connect` starts immediately. Keep the row focused and replace its detail
with `Connecting…`, then `Checking…`. On success, move it to the first row only
after focus can be preserved. On failure, leave it focused with the specific
error and make `A Retry` or `A Edit password` the next action.

### New secured network

Open a dedicated password screen with the SSID, a masked field, `Show
password`, and the on-screen keyboard. The action is `Connect`, not `Save`:
credentials become a saved profile only through the successful/atomic join
transaction. Preserve the entered password across a recoverable authentication
failure in protected memory, but never logs, screenshots or persistent preedit
state. Clear it on cancel, network change, authority restart or timeout.

The OSK is part of the qualified P0.4 input path. It must expose case state,
symbols, deletion and a visible Connect action without requiring pointer input.
The UI tree currently holds 48 elements; a keyboard made from several primitives
per key will exceed that capacity. Add one compound keyboard element or make a
measured, tested capacity change rather than relying on silent truncation.

### Open network

Do not interrupt every open-network join with a generic modal. The row says
`Open network`; after selection, a concise confirmation explains that traffic
may be visible to others. Remembering the choice does not suppress future
security changes or privacy warnings.

### Hidden network

`Add hidden network` asks for the exact name, then offers only the security
types qualified by the production plan: `Open` and `WPA2 Personal`. It does not
expose BSSID, channel, WPS, WPA3 or enterprise fields. A hidden profile defaults
to auto-connect off until its first successful join, limiting repeated directed
probes for a mistyped name.

### Explicit disconnect

Disconnect retains credentials but temporarily suppresses auto-rejoin. It must
not reconnect immediately while the user is still choosing another network.
Re-enable eligibility after an explicit Connect, after the network leaves and
returns, or after a documented bounded timeout. Forget is a separate action.

## Current/saved network details

The first row is always the outcome-specific primary action:

* `Sign in` for captive;
* `Retry connection check` for limited;
* `Disconnect` for connected;
* `Connect` for saved and disconnected; or
* `Cancel` for a user-started pending connection when cancellation is safe.

Then expose:

1. **Auto-connect** — on by default after a successful join. Off keeps the
   credentials but prevents unsolicited association.
2. **Private address** — on by default, backed by the stable per-network mode
   already selected in the production plan. Turning it off warns that the
   network may identify the device and reconnects only after confirmation;
   never mutate the active MAC in place.
3. **Connection info** — read-only security, signal quality and IP address for
   diagnosis. Channel, BSSID and raw RSSI may appear here only in a development
   build or an explicitly expanded diagnostics view.
4. **Forget network** — confirm because it atomically removes credentials,
   private-address state and captive-browser data. For the active network say
   that it will disconnect.

Do not expose `Metered` until it changes updater/download policy. Do not expose
editable IP, DNS, proxy, roaming aggressiveness, band choice or network priority
in v1. A visible switch with no complete policy is worse than omission.

## Captive login

Captive is a usable local link that still needs action, not a failed password.

### When to open

* User explicitly chose the network from the Wi-Fi screen: after the authority
  confirms captive, open the contained login automatically.
* Auto-join while on Home/Settings: show a non-modal `Sign in to {name}` notice
  and make the current network's primary action `Sign in`. Do not unexpectedly
  replace the whole shell.
* Auto-join while a game is running: never launch or overlay the browser. Defer
  the notice until pause/exit; online-only work sees the authority's captive
  state and fails cleanly.
* Resume to a still-captive network: recheck first, then surface one notice. Do
  not reopen a portal merely because stale browser data exists.

### Browser chrome

Show the network name, `Cancel`, page Back when meaningful, an activity state
and one `Done`/`Check connection` action. Do not display a security padlock that
could be confused with the Wi-Fi network's lock. TLS errors fail closed and use
product UI outside the page.

After navigation, form submission or Done, the authority rechecks independently.
Only it can close the browser as successful. Cancel returns to network details
with `Sign-in required`; secondary actions may offer `Stay connected without
internet` for local-LAN use or `Choose another network`. Manual URL/QR is a
fallback for incompatible portals, not the default flow.

## Interruptions and notices

Wi-Fi should be quiet when it works:

| Context | Surface |
| --- | --- |
| Normal auto-join or roam succeeds | no notice |
| User-started join succeeds | return to Wi-Fi list with `Connected` |
| Captive after user-started join | open login |
| Captive after background auto-join | one non-modal shell notice |
| Link drops briefly and recovers within roam bound | no notice |
| Reconnect exceeds bound | status changes in shell; no modal over a game |
| Online operation fails because network is captive/limited | explain the network outcome and link to Wi-Fi |
| Wi-Fi turned off | immediate status update; no success toast |

Avoid polling-driven toasts. Notices are edge-triggered and deduplicated by
network identity plus authority generation so shell restarts do not replay old
events.

## Error design

Errors stay attached to the network and name the failed stage. They preserve
focus and provide one relevant recovery:

| Failure | Primary recovery | Secondary recovery |
| --- | --- | --- |
| Wrong password / rejected authentication | `Edit password` | `Cancel` |
| Network disappeared | `Refresh` | `Choose another` |
| Address/DHCP failed | `Retry` | `Connection info` |
| Captive | `Sign in` | `Choose another` |
| Internet validation failed | `Retry check` | `Stay connected` / `Choose another` |
| Unsupported security | none | show supported modes |
| Radio/firmware recovery in progress | `Cancel` when safe | wait with bounded timeout |
| Recovery exhausted | `Try again` | `Turn Wi-Fi off` |

Never use a generic `Connection failed` when the authority knows the stage.
Never blame the router until device-side recovery has completed. Never discard
the list position or typed SSID after a recoverable failure.

## Controller and accessibility contract

* D-pad Up/Down moves by one logical row; no horizontal focus graph.
* `A` performs the footer's named action; `B` always returns/cancels safely.
* `Y Refresh` appears only on the Wi-Fi list and only when supported.
* No core action requires long-press, pointer, touch, colour perception or an
  unlabeled icon.
* Signal has four stable buckets plus a textual description in details. Do not
  expose rapidly fluctuating percentages.
* Lock/open state has both an icon and words where it changes the decision.
* Long SSIDs are ellipsized visually but their full, sanitized Unicode name is
  available in details. Invalid scan bytes get a stable escaped fallback, never
  replacement characters that merge distinct identities.
* Live scan changes do not steal focus or cause repeated screen-reader speech.
* Password visibility always has a textual state, not an eye icon alone.

## Scan, power and roaming presentation

The UI must not accidentally turn foreground browsing into continuous scanning.
Opening the Wi-Fi screen requests one immediate scan; explicit Refresh requests
one more. The background controller remains adaptive and independently bounded.

Show signal quality, not scan age or `Searching…`, while usable cached results
exist. When the radio is off, show no stale networks. When a foreground scan
cannot run during a driver recovery, keep the previous results and report the
recovery state.

The product copy is `Wi-Fi off`, not `radio powered off`: device evidence proves
RF soft block and interface/service teardown, not independent rail power-off.
Roaming copy is `Reconnecting…`, never `Seamless roaming` or `Always connected`.

## V1 scope and later work

Ship in v1 only when the corresponding backend path is qualified:

* Wi-Fi on/off and stable global summary;
* current/saved/available logical network list;
* signal buckets, lock/open state and explicit Refresh;
* WPA2 password and open-network join; hidden network entry;
* auto-connect, disconnect, forget and stable private-address override;
* authoritative Connected / Sign-in required / No internet outcomes;
* captive login plus URL/QR fallback; and
* stage-specific errors with retry/recovery.

Later or explicitly out of scope: WPA3, enterprise/certificates, WPS, credential
sharing, manual priority, metered mode, editable IP/DNS/proxy, user-visible
BSSID/band selection and claims of seamless independent-AP roaming.

## Implementation seams

Add an independent `wifi.zig` product model. Keep authority data conversion
outside rendering and model network identity separately from display name. The
minimum shell-facing snapshot is:

```zig
pub const RadioState = enum { unavailable, off, starting, ready, stopping, failed };
pub const Connectivity = enum { none, local, captive, internet, limited };
pub const NetworkState = enum {
    available, saved, connecting, validating, connected,
    sign_in, limited, reconnecting, auth_failed, address_failed,
    out_of_range, unsupported,
};

pub const Network = struct {
    id: StableNetworkId,
    display_name: []const u8,
    security: enum { open, wpa2_personal, unsupported },
    signal: enum { weak, fair, good, strong },
    state: NetworkState,
    auto_connect: bool,
    private_address: bool,
};
```

The exact IPC is a Phase 2 authority decision. It should publish immutable
snapshots with a generation and accept idempotent commands (`set_enabled`,
`scan`, `connect`, `cancel`, `disconnect`, `forget`, `set_auto_connect`,
`set_private_address`, `open_captive`, `recheck`). The shell must be able to
restart, request one snapshot and reconstruct the screen without replaying
commands.

The authority fd belongs in the shell's existing event-driven poll loop. Scan,
join, validation, roaming and captive progress must never block rendering or
input on a synchronous helper. Keep the C/GLib authority out of process and the
client protocol narrow: the build currently caps the stripped AArch64 shell at
524,288 bytes, and simulator tests should not need the daemon or a networking
client stack.

Keep rendering pure. The shell model owns focus by stable identity, freezes row
order during interaction and converts pending commands into product states. The
backend owns credentials, redaction, timing, retries and authority.

## Acceptance scenarios

At minimum, simulator and device tests should cover:

1. Off → on → scan → WPA2 password → association → validation → Internet.
2. Wrong password → Edit password without losing focus → success.
3. User-started open join → captive browser → authority-approved success.
4. Captive auto-join during a game does not launch browser or steal input.
5. Captive cancel → still connected/sign-in required → choose another network.
6. Connected/no-DNS and connected/no-Internet remain distinct from captive.
7. Explicit Disconnect does not immediately auto-rejoin.
8. Forget active network removes credentials, private MAC and portal data and
   returns to available state.
9. Scan results update while navigating without focus jumping.
10. Same SSID across BSSIDs renders once and ordinary roam is silent.
11. Failed roam crosses its time bound → Reconnecting → rollback/recovery.
12. Wi-Fi off/on restores the list from a fresh authority snapshot and never
    implies that the whole shared radio rail was powered down.
13. Authority and shell restart independently in every visible state.
14. Long Unicode, duplicate and malformed SSIDs remain distinguishable.
15. Every flow works with D-pad, A/B/Y and OSK only.

## Primary references

* [Android: connect to Wi-Fi networks](https://support.google.com/android/answer/9075847?hl=en)
* [Android: metered and advanced network settings](https://support.google.com/android/answer/9654714?hl=en)
* [Android captive-portal detection and CAPPORT](https://source.android.com/docs/core/connect/android-custom-tabs-captive-portal)
* [Apple: manage Wi-Fi settings](https://support.apple.com/en-ie/guide/iphone/iphw5gjwl8k2/27/ios/27)
* [Apple: private Wi-Fi addresses](https://support.apple.com/en-gb/102509)
* [Apple: captive Wi-Fi networks](https://support.apple.com/en-au/102554)
* [Steam Deck basic use: Wi-Fi and OSK](https://help.steampowered.com/en/faqs/view/69E3-14AF-9764-4C28)
* [Nintendo Switch wireless connection flow](https://www.nintendo.com/en-gb/Support/Troubleshooting/How-to-Connect-to-the-Internet-Using-a-Wireless-Network-on-Nintendo-Switch-1228927.html)
* [PlayStation wireless setup](https://www.playstation.com/en-us/support/connectivity/internet-connect-playstation/)
* [Brick Wi-Fi device evidence and selected policy](../../firmware/board/trimui/brick/WIFI-SPIKE.md)
* [Brick Wi-Fi production plan](../../firmware/board/trimui/brick/WIFI-PRODUCTION-PLAN.md)
