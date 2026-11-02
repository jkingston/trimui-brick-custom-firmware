BASE ?= ../firmware
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BASE := $(abspath $(BASE))
BUILDROOT_VERSION := $(shell sed -n 's/^BUILDROOT_VERSION := //p' $(BASE)/Makefile)
BUILDROOT := $(BASE)/output/buildroot-$(BUILDROOT_VERSION)
O ?= $(ROOT)/output/build
override O := $(abspath $(O))
EXTERNALS := $(BASE) $(ROOT)
RELEASE_O ?= $(ROOT)/output/release
ZIG ?= zig
ROM_ROOT := $(ROOT)/roms

.PHONY: all configure check clean release simulator simulator-pixels simulator-build screenshots demo-roms
all: configure
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads

configure:
	test -f $(BASE)/Makefile
	$(MAKE) -C $(BASE) O=$(O) EXTERNALS="$(EXTERNALS)" configure
	$(BUILDROOT)/utils/config --file $(O)/.config --enable BR2_PACKAGE_BRICK_SHELL
	$(BUILDROOT)/utils/config --file $(O)/.config --set-str BR2_ROOTFS_POST_BUILD_SCRIPT \
		'$$(BR2_EXTERNAL_BRICK_PATH)/board/trimui/brick/post-build.sh $$(BR2_EXTERNAL_BRICK_UI_PATH)/board/trimui/brick/post-build.sh'
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads olddefconfig
	grep -qx 'BR2_PACKAGE_BRICK_SHELL=y' $(O)/.config

check:
	mkdir -p $(ROOT)/output/check
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) test $(ROOT)/src/main.zig
	ZIG_LOCAL_CACHE_DIR=$(ROOT)/.zig-cache \
	ZIG_GLOBAL_CACHE_DIR=$(ROOT)/.zig-global-cache \
		$(ZIG) build-exe $(ROOT)/src/main.zig -target aarch64-linux \
		-mcpu=cortex_a53 -OReleaseSmall -fstrip \
		-femit-bin=$(ROOT)/output/check/brick-shell
	test "$$(stat -c %s $(ROOT)/output/check/brick-shell)" -le 524288

clean:
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" clean

release:
	test ! -e "$(RELEASE_O)/.config"
	test ! -e "$(RELEASE_O)/local.mk"
	$(MAKE) O=$(RELEASE_O) configure
	$(MAKE) -C $(BUILDROOT) O=$(RELEASE_O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads
	$(MAKE) -C $(BASE) O=$(RELEASE_O) EXTERNALS="$(EXTERNALS)" release-check

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
	for screen in splash home games game overlay overlay-states overlay-options; do \
		$(ROOT)/output/host/brick-shell-host --snapshot $(ROOT)/output/screenshots/$$screen.ppm $$screen; \
		magick $(ROOT)/output/screenshots/$$screen.ppm $(ROOT)/output/screenshots/$$screen.png; \
	done

demo-roms: \
	$(ROM_ROOT)/FC/falling.nes \
	$(ROM_ROOT)/FC/minekart-madness.nes \
	$(ROM_ROOT)/GB/adjustris.gb \
	$(ROM_ROOT)/GBA/rkanoid.gba \
	$(ROM_ROOT)/MD/willows-dream.md
	cd $(ROOT)/roms && sha256sum -c SHA256SUMS

$(ROM_ROOT)/FC/falling.nes:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://raw.githubusercontent.com/xram64/falling-nes/52dcb8a951200562e696dfc2aba5d4d14edd0078/falling.nes \
		-o $@.tmp
	echo 'e22b947542c2d7e595bf84725b333be7af8189c5965b9c53e356a249c7d79943  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(ROM_ROOT)/FC/minekart-madness.nes:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://github.com/mhughson/mbh-cart/releases/download/v1.0/minekart_madness_mmc1.nes \
		-o $@.tmp
	echo '45d18d8b3662e6c08043759e550e658bcd23e48394a00f24de5e5fbe57e4900a  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(ROM_ROOT)/GB/adjustris.gb:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://github.com/tbsp/Adjustris/releases/download/v1.1/adjustris.gb \
		-o $@.tmp
	echo 'b6c8affe6d906419cfc99ff459718f33a1868af03254a2f65cea2a9430394712  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(ROM_ROOT)/GBA/rkanoid.gba:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://raw.githubusercontent.com/benoror/gbadev/b61cb1e8d6646789c833522a7d3d64adda27581a/public/roms/%40rkanoid%20MODERN%20-%20RECOMPILED.gba \
		-o $@.tmp
	echo '99ae825ffb1b7e8b48b33cd2715ceb8ca524858f99fee4b22938489460083d94  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(ROM_ROOT)/MD/willows-dream.md:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://raw.githubusercontent.com/marcellodash/willows-dream/9ff80c7ef5f7b31e178b57fd4542f8ceee27eca4/out/rom.bin \
		-o $@.tmp
	echo '4200bfebc7a15d5cac1bdc1f5aa5e61c3d7b02f2b68af913275720436c2645b0  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

.PHONY: simulator-check
simulator-check: simulator-build demo-roms
	mkdir -p $(ROOT)/output/sim-data/Roms $(ROOT)/output/sim-empty
	cp -R $(ROM_ROOT)/FC $(ROM_ROOT)/GB $(ROM_ROOT)/GBA $(ROM_ROOT)/MD $(ROOT)/output/sim-data/Roms/
	SDL_VIDEODRIVER=dummy $(ROOT)/output/host/brick-ui-simulator --data-root $(ROOT)/output/sim-data --library-check $(ROOT)/output/library-check
	SDL_VIDEODRIVER=dummy $(ROOT)/output/host/brick-ui-simulator --data-root $(ROOT)/output/sim-empty --library-check $(ROOT)/output/empty-check
