BASE ?= ../firmware
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BASE := $(abspath $(BASE))
BUILDROOT_VERSION := $(shell sed -n 's/^BUILDROOT_VERSION := //p' $(BASE)/Makefile)
BUILDROOT := $(BASE)/output/buildroot-$(BUILDROOT_VERSION)
O ?= $(ROOT)/output/build
override O := $(abspath $(O))
EXTERNALS := $(BASE) $(ROOT)
ZIG ?= zig

.PHONY: all configure check clean
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
