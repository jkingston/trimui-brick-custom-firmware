# Official prebuilt host compiler, pinned for reproducible product builds.
HOST_ZIG_BIN_VERSION = 0.17.1
HOST_ZIG_BIN_SOURCE = zig-x86_64-linux-$(HOST_ZIG_BIN_VERSION).tar.xz
HOST_ZIG_BIN_SITE = https://ziglang.org/download/$(HOST_ZIG_BIN_VERSION)
HOST_ZIG_BIN_LICENSE = MIT
HOST_ZIG_BIN_LICENSE_FILES = LICENSE

define HOST_ZIG_BIN_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/zig $(HOST_DIR)/bin/zig
	mkdir -p $(HOST_DIR)/lib/zig
	cp -a $(@D)/lib/. $(HOST_DIR)/lib/zig/
endef

$(eval $(host-generic-package))
