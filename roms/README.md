# Demo ROMs

`make demo-roms` downloads two redistributable NES homebrew games from pinned
author releases and verifies their hashes. ROM files are local test data and
are ignored by Git.

- **Falling** by Jesse Williams: MIT, source revision
  `52dcb8a951200562e696dfc2aba5d4d14edd0078` at
  <https://github.com/xram64/falling-nes>.
- **Minekart Madness** by Matt Hughson: MIT, release `v1.0` at
  <https://github.com/mhughson/mbh-cart/releases/tag/v1.0>.

On the device, user-owned content lives under `/data/roms`; save RAM and states
live under `/data/saves`. The firmware repository does not bundle commercial
ROMs.
