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
