# Brick product shell

Product layer for the TrimUI Brick base firmware. The current spike combines
an iPod-inspired game library with a small event-driven Zig shell and an
explicit RetroArch launch boundary.

The Zig shell uses PangoFT2 for multilingual text. It builds a fixed-capacity
declarative UI tree, renders directly to the Linux framebuffer, and waits in
`poll()` when nothing changes. Selecting a game releases the framebuffer,
runs `retroarch -L <core> <content>`, then restores the shell when RetroArch
exits. ROMs and saves live on the writable SD partition under `/data`.

Place this repository beside the Brick base repository, then run:

```sh
mise run check
mise run build
```

The build composes two Buildroot external trees: the base first and this product
tree second. Set `BASE=/path/to/base` when they are not siblings.

`mise run release` produces and verifies a clean complete image under
`output/release/images`.

`mise run demo-roms` downloads pinned, publicly distributed NES, Game Boy,
Game Boy Advance and Mega Drive homebrew games for local testing. Their sources and
hashes are recorded in `roms/`; the ROM binaries are ignored by Git.

For desktop work, `mise run simulator` opens the same 1024x768 model, layout and
software renderer used by the device, sized to the Brick's 3.2-inch 4:3 panel.
Press P to switch between physical-size and 1:1 pixel views. Arrow keys navigate,
Z/Enter confirms, X/Escape returns, V changes view, H opens the menu and M previews the in-game
overlay. `mise run screenshots` renders the shell and overlay screens without
opening a window.

Games opens directly: A plays, the upper-left function button changes view,
and the bottom-left Menu button opens navigation. Hints identify those button groups.
B returns to the previous screen. Settings use left/right to adjust values.
Light/dark appearance is saved in Settings. Shared typography, spacing, geometry
and motion are compile-time values in `src/design.zig`; semantic colours live in
`src/theme.zig`. Artwork colours are independent.

View and selection are remembered on the SD card; Recent and Favorites are not
yet exposed.

## SD card content

The content partition is mounted at `/data`. Use `Roms/` and `BIOS/` at its root,
following the [TrimUI/CrossMix convention](https://github.com/cizia64/CrossMix-OS/wiki/Emulators).

| System | Folder under `Roms/` |
| --- | --- |
| NES | `FC` |
| Game Boy / Color / Advance | `GB` / `GBC` / `GBA` |
| Master System / Game Gear / Mega Drive | `MS` / `GG` / `MD` |
| SNES / PlayStation | `SFC` / `PS` |
| Neo Geo / Neo Geo Pocket (Color) | `NEOGEO` / `NGP` |

The device scans ROM folders at shell startup, including subfolders. It accepts
`roms`/`ROMS`, case-insensitive system codes, aliases (`nes`, `snes`, `psx`,
`genesis`, `megadrive`, `mastersystem`, `gamegear`, `ngpc`), and MinUI-style
names such as `Super Nintendo (SFC)`. Existing ROM folders are not moved.
Hidden folders, artwork and `neogeo.zip` are excluded. PS1 tracks launch through
CUE files; M3U playlists hide their referenced discs from the list. Use relative
paths inside playlists for portability.

Put PS1 BIOS files such as `scph5501.bin` in `BIOS/`. FBNeo also searches
`BIOS/fbneo/` and the game's directory for `neogeo.zip`; keep it zipped.
BIOS filenames must match the core's requirements exactly.

Save RAM and states are isolated under `Saves/games/<path-id>/`, then by core.
The ID hashes the ROM path relative to the content partition: moving the card to
another mount preserves it; renaming a ROM or folder changes it. `content-path.txt`
in each save directory identifies the corresponding ROM. Keep paths stable when
copying a library between devices.

On first launch, unambiguous legacy saves and states are copied from `Saves/` or
`saves/`; originals remain intact. Conflicting legacy saves block launch with an
error. New progress is never overwritten by a later import. At startup the older
`system/` BIOS directory is renamed to `BIOS/` if the destination does not exist.

Launch checks distinguish unavailable content, missing cores and unwritable save
storage. The latest emulator output is kept in `/run/brick-shell/last-game.log`
until reboot. BIOS validation and automatic save relocation after renames remain
unfinished.

The image builds FCEUmm, mGBA, Genesis Plus GX, Snes9x, PCSX ReARMed,
FBNeo (Neo Geo subset) and Beetle NeoPop. PS1 can use its HLE BIOS fallback,
but a retail BIOS is recommended for compatibility. Neo Geo requires a matching
BIOS set. Core availability does not guarantee compatibility with every game.

## Cartridge artwork

Neutral cartridge models and game-specific artwork are installed only for ROMs
present on the data card. Clone
the [asset repository](https://github.com/jkingston/trimui-brick-cartridge-assets),
then synchronize through the Brick's USB network interface:

```sh
uv run python tools/sync_ssh_assets.py --dry-run
uv run python tools/sync_ssh_assets.py
```

The first command reports unmatched games without writing. The second downloads
available curated labels, generates clearly neutral labels for unmatched games,
renders the required models, then atomically installs them under `/data/Assets/Brick`.
ROM contents never leave the device; cartridge files are hashed on the Brick.
The workflow does not require wireless networking.

The simulator uses fixtures by default. To browse actual content, run
`output/host/bin/brick-ui-simulator --data-root /path/to/content` after
`mise run simulator-build`. `mise run simulator-check` downloads the homebrew samples,
scans them and checks library navigation with SDL's headless renderer, saving
screenshots under `output/library-check/`. It checks launch requests, not emulation.
