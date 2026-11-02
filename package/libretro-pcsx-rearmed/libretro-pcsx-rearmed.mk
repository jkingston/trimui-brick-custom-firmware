################################################################################
#
# libretro-pcsx-rearmed
#
################################################################################

LIBRETRO_PCSX_REARMED_VERSION = 7b0e8f8fadfbce3d170d195b9d9eecaabfa08c8e
LIBRETRO_PCSX_REARMED_SITE = $(call github,libretro,pcsx_rearmed,$(LIBRETRO_PCSX_REARMED_VERSION))
LIBRETRO_PCSX_REARMED_LICENSE = GPL-2.0+
LIBRETRO_PCSX_REARMED_LICENSE_FILES = COPYING

# Compiler flags precede upstream's own flags, preserving its required defines.
define LIBRETRO_PCSX_REARMED_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) -f Makefile.libretro \
		platform=unix CC="$(TARGET_CC) $(TARGET_CFLAGS) -mcpu=cortex-a53" \
		CXX="$(TARGET_CXX) $(TARGET_CXXFLAGS) -mcpu=cortex-a53" \
		AR="$(TARGET_AR)" HAVE_PHYSICAL_CDROM=0
endef

define LIBRETRO_PCSX_REARMED_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/pcsx_rearmed_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/pcsx_rearmed_libretro.so
endef

$(eval $(generic-package))
