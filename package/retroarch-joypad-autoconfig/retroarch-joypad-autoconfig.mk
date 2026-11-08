################################################################################
# Official RetroArch controller profiles, pinned for reproducible mappings.
################################################################################

RETROARCH_JOYPAD_AUTOCONFIG_VERSION = 2e3b8a2728d5efd00fa0207d07ba2488b89e87b2
RETROARCH_JOYPAD_AUTOCONFIG_SITE = $(call github,libretro,retroarch-joypad-autoconfig,$(RETROARCH_JOYPAD_AUTOCONFIG_VERSION))
RETROARCH_JOYPAD_AUTOCONFIG_LICENSE = MIT
RETROARCH_JOYPAD_AUTOCONFIG_LICENSE_FILES = COPYING

define RETROARCH_JOYPAD_AUTOCONFIG_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/libretro/autoconfig/udev
	$(INSTALL) -m 0644 "$(@D)/udev/Xbox_Wireless_Controller.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/Xbox One S Wireless Controller.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/Sony DualShock 4 Controller.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/Sony Interactive Entertainment DualSense Wireless Controller.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/Sony-PlayStation3-DualShock3-Controller-Bluez.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/8BitDo_Pro2_BT_X.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/8BitDo_Pro2_BT_D.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/8BitDo_SN30_Pro+_BT_X.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/8BitDo_SN30_Pro+_BT_B.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
	$(INSTALL) -m 0644 "$(@D)/udev/8BitDo_Ultimate_2C_Wireless_Controller_BT.cfg" $(TARGET_DIR)/usr/share/libretro/autoconfig/udev/
endef

$(eval $(generic-package))
