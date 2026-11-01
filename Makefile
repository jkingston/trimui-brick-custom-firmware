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
ROM_DIR := $(ROOT)/roms/nes

.PHONY: all configure check clean release simulator simulator-pixels simulator-build screenshots demo-roms
all: configure
	$(MAKE) -C $(BUILDROOT) O=$(O) BR2_EXTERNAL="$(EXTERNALS)" \
		BR2_DL_DIR=$(BASE)/output/downloads

configure:
	test -f $(BASE)/Makefile
	$(MAKE) -C $(BASE) O=$(O) EXTERNALS="$(EXTERNALS)" configure
	$(BUILDROOT)/utils/config --file $(O)/.config --enable BR2_PACKAGE_BRICK_SHELL
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
	for screen in splash home games game; do \
		$(ROOT)/output/host/brick-shell-host --snapshot $(ROOT)/output/screenshots/$$screen.ppm $$screen; \
		magick $(ROOT)/output/screenshots/$$screen.ppm $(ROOT)/output/screenshots/$$screen.png; \
	done

demo-roms: $(ROM_DIR)/falling.nes $(ROM_DIR)/minekart-madness.nes
	cd $(ROOT)/roms && sha256sum -c SHA256SUMS

$(ROM_DIR)/falling.nes:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://raw.githubusercontent.com/xram64/falling-nes/52dcb8a951200562e696dfc2aba5d4d14edd0078/falling.nes \
		-o $@.tmp
	echo 'e22b947542c2d7e595bf84725b333be7af8189c5965b9c53e356a249c7d79943  $@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(ROM_DIR)/minekart-madness.nes:
	mkdir -p $(@D)
	curl -fL --retry 3 \
		https://github.com/mhughson/mbh-cart/releases/download/v1.0/minekart_madness_mmc1.nes \
		-o $@.tmp
	echo '45d18d8b3662e6c08043759e550e658bcd23e48394a00f24de5e5fbe57e4900a  $@.tmp' | sha256sum -c -
	mv $@.tmp $@
