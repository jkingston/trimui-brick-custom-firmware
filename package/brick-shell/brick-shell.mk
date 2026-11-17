BRICK_SHELL_VERSION = 1
BRICK_SHELL_SITE = $(BR2_EXTERNAL_BRICK_UI_PATH)
BRICK_SHELL_SITE_METHOD = local
BRICK_SHELL_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude output \
	--exclude .zig-cache \
	--exclude .zig-global-cache \
	--exclude roms/nes \
	--exclude design
BRICK_SHELL_LICENSE = GPL-2.0-only
BRICK_SHELL_LICENSE_FILES = COPYING
BRICK_SHELL_DEPENDENCIES = \
	host-zig-bin pango googlefontdirectory host-fontconfig brick-gpu libdrm

define BRICK_SHELL_BUILD_CMDS
	cd $(@D) && \
		ZIG_LOCAL_CACHE_DIR=$(@D)/.zig-cache \
		ZIG_GLOBAL_CACHE_DIR=$(@D)/.zig-global-cache \
		$(HOST_DIR)/bin/zig build-exe src/main.zig \
		-target aarch64-linux-gnu -mcpu=cortex_a53 -OReleaseSmall -fstrip -dynamic -lc \
		-femit-bin=$(@D)/brick-shell
	$(TARGET_CC) $(TARGET_CFLAGS) -std=c11 -Wall -Wextra -Werror \
		-I$(STAGING_DIR)/usr/include/libdrm \
		$(BR2_EXTERNAL_BRICK_PATH)/board/trimui/brick/wpe-platform-brick/integration/brick-kms-watchdog.c \
		$(TARGET_LDFLAGS) -ldrm -o $(@D)/brick-shell-watchdog
endef

define BRICK_SHELL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/brick-shell $(TARGET_DIR)/usr/bin/brick-shell
	$(INSTALL) -D -m 0755 $(@D)/brick-shell-watchdog $(TARGET_DIR)/usr/libexec/brick-shell-watchdog
	$(INSTALL) -D -m 0755 $(@D)/package/brick-shell/S20brick-shell \
		$(TARGET_DIR)/etc/init.d/S20brick-shell
	$(INSTALL) -D -m 0755 $(@D)/package/brick-shell/S41brick-efficiency \
		$(TARGET_DIR)/etc/init.d/S41brick-efficiency
	$(INSTALL) -D -m 0755 $(@D)/package/brick-shell/brick-performance \
		$(TARGET_DIR)/usr/sbin/brick-performance
	$(INSTALL) -D -m 0755 $(@D)/package/brick-shell/brick-settings \
		$(TARGET_DIR)/usr/sbin/brick-settings
	$(INSTALL) -D -m 0644 $(@D)/package/brick-shell/retroarch.cfg \
		$(TARGET_DIR)/etc/retroarch/retroarch.cfg
	$(INSTALL) -D -m 0644 $(@D)/package/brick-shell/brick.rguip \
		$(TARGET_DIR)/etc/retroarch/brick.rguip
	$(INSTALL) -D -m 0644 $(@D)/package/brick-shell/TrimUI_Brick_Gamepad.cfg \
		$(TARGET_DIR)/usr/share/libretro/autoconfig/udev/TrimUI_Brick_Gamepad.cfg
	$(INSTALL) -D -m 0644 $(@D)/package/brick-shell/Brick_Test_Controller.cfg \
		$(TARGET_DIR)/usr/share/libretro/autoconfig/udev/Brick_Test_Controller.cfg
	rm -f $(TARGET_DIR)/usr/share/fonts/notosans/*Italic*.ttf
	rm -f $(TARGET_DIR)/usr/share/fonts/inter/*Italic*.ttf
	mkdir -p $(TARGET_DIR)/var/cache/fontconfig
	env FONTCONFIG_FILE=/etc/fonts/fonts.conf \
		$(HOST_DIR)/bin/fc-cache --really-force --system-only \
		--sysroot=$(TARGET_DIR)
endef

$(eval $(generic-package))
