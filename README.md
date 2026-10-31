# Brick UI firmware

Product firmware for the TrimUI Brick. It layers on the Brick base image and
owns the user interface, applications, product policy and branding.

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

For desktop UI work, `make simulator` opens the same 1024x768 model, layout and
software renderer used by the device, sized to the Brick's 3.2-inch 4:3 panel.
Press P to switch between physical-size and 1:1 pixel views. Arrow keys navigate,
Z/Enter confirms, X/Escape returns, and 1-9 plus 0 open reference screens.
`make screenshots` renders those screens without opening a window.
