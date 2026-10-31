BRICK_SHELL_VERSION = 1
BRICK_SHELL_SITE = $(BR2_EXTERNAL_BRICK_UI_PATH)
BRICK_SHELL_SITE_METHOD = local
BRICK_SHELL_LICENSE = GPL-2.0-only
BRICK_SHELL_LICENSE_FILES = COPYING
BRICK_SHELL_DEPENDENCIES = host-zig-bin

define BRICK_SHELL_BUILD_CMDS
	cd $(@D) && \
		ZIG_LOCAL_CACHE_DIR=$(@D)/.zig-cache \
		ZIG_GLOBAL_CACHE_DIR=$(@D)/.zig-global-cache \
		$(HOST_DIR)/bin/zig build-exe src/main.zig \
		-target aarch64-linux -mcpu=cortex_a53 -OReleaseSmall -fstrip \
		-femit-bin=$(@D)/brick-shell
endef

define BRICK_SHELL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/brick-shell $(TARGET_DIR)/usr/bin/brick-shell
	$(INSTALL) -D -m 0755 $(@D)/package/brick-shell/S02brick-shell \
		$(TARGET_DIR)/etc/init.d/S02brick-shell
endef

$(eval $(generic-package))
