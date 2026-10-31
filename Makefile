BASE ?= ../firmware
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BASE := $(abspath $(BASE))
BUILDROOT_VERSION := $(shell sed -n 's/^BUILDROOT_VERSION := //p' $(BASE)/Makefile)
BUILDROOT := $(BASE)/output/buildroot-$(BUILDROOT_VERSION)
O ?= $(ROOT)/output/build
override O := $(abspath $(O))
EXTERNALS := $(BASE) $(ROOT)
ZIG ?= zig

.PHONY: all configure check clean simulator simulator-pixels simulator-build screenshots
all: configure
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads

configure:
	test -f $(BASE)/Makefile
	$(MAKE) -C $(BASE) O=$(O) configure
	$(BUILDROOT)/utils/config --file $(O)/.config --enable BR2_PACKAGE_BRICK_SHELL
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads olddefconfig
	grep -qx 'BR2_PACKAGE_BRICK_SHELL=y' $(O)/.config

check:
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) test $(ROOT)/src/main.zig
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) build-exe $(ROOT)/src/main.zig -target aarch64-linux \
		-mcpu=cortex_a53 -OReleaseSmall -fstrip -fno-emit-bin

clean:
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" clean

simulator: simulator-build
	$(ROOT)/output/host/brick-ui-simulator --physical

simulator-pixels: simulator-build
	$(ROOT)/output/host/brick-ui-simulator --pixels

simulator-build:
	mkdir -p $(ROOT)/output/host
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) build-exe $(ROOT)/src/simulator.zig -OReleaseSafe -lc \
		-femit-bin=$(ROOT)/output/host/brick-ui-simulator

screenshots:
	mkdir -p $(ROOT)/output/host $(ROOT)/output/screenshots
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) build-exe $(ROOT)/src/main.zig -OReleaseSafe \
		-femit-bin=$(ROOT)/output/host/brick-shell-host
	for screen in systems games detail game-menu checkpoints game-settings storage empty-library save-data save-conflict; do \
		$(ROOT)/output/host/brick-shell-host --snapshot $(ROOT)/output/screenshots/$$screen.ppm $$screen; \
		magick $(ROOT)/output/screenshots/$$screen.ppm $(ROOT)/output/screenshots/$$screen.png; \
	done
