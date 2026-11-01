# Brick product shell

Product layer for the TrimUI Brick base firmware. The current spike combines
an iPod-inspired game library with a small event-driven Zig shell and an
explicit RetroArch launch boundary.

The shell is a dependency-free Zig program. It builds a fixed-capacity
declarative UI tree, renders directly to the Linux framebuffer, and waits in
`poll()` when nothing changes. Selecting a game releases the framebuffer,
runs `retroarch -L <core> <content>`, then restores the shell when RetroArch
exits. ROMs and saves live on the writable SD partition under `/data`.

Place this repository beside the Brick base repository, then run:

```sh
make check
make configure
make
```

The build composes two Buildroot external trees: the base first and this product
tree second. Set `BASE=/path/to/base` when they are not siblings.

`make release` produces and verifies a clean complete image under
`output/release/images`.

`make demo-roms` downloads two pinned, MIT-licensed NES homebrew games for
local testing. Their sources and hashes are recorded in `roms/`; the ROM
binaries are ignored by Git.

For desktop work, `make simulator` opens the same 1024x768 model, layout and
software renderer used by the device, sized to the Brick's 3.2-inch 4:3 panel.
Press P to switch between physical-size and 1:1 pixel views. Arrow keys navigate,
Z/Enter confirms, X/Escape returns, H returns home and M previews the in-game
overlay. `make screenshots` renders the shell and overlay screens without
opening a window.
