# Brick product shell

Minimal product layer for the TrimUI Brick base firmware. It currently proves
the product boundary, early framebuffer ownership, physical controls and an
event-driven Zig UI without committing the final product structure.

The shell is a dependency-free Zig program. It builds a fixed-capacity
declarative UI tree, renders directly to the Linux framebuffer, and waits in
`poll()` when nothing changes. Startup draws the product splash before loading
the home screen; input redraws only after a model change.

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

For desktop work, `make simulator` opens the same 1024x768 model, layout and
software renderer used by the device, sized to the Brick's 3.2-inch 4:3 panel.
Press P to switch between physical-size and 1:1 pixel views. Arrow keys navigate,
Z/Enter confirms, X/Escape returns and H returns home. `make screenshots`
renders the splash and home screens without opening a window.
