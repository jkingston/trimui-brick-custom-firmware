################################################################################
#
# libretro-fbneo
#
################################################################################

LIBRETRO_FBNEO_VERSION = 87627162f72154e76172f2d1c319515b8c596459
LIBRETRO_FBNEO_SITE = $(call github,libretro,FBNeo,$(LIBRETRO_FBNEO_VERSION))
LIBRETRO_FBNEO_LICENSE = Non-commercial
LIBRETRO_FBNEO_LICENSE_FILES = LICENSE.md
LIBRETRO_FBNEO_DEPENDENCIES = zlib

# The archive's generated driver list covers all systems, not the Neo Geo subset.
define LIBRETRO_FBNEO_GENERATE_DRIVER_LIST
	perl $(@D)/src/dep/scripts/gamelist.pl \
		-o $(@D)/src/dep/generated/driverlist.h \
		$(@D)/src/burn/drv/neogeo/d_neogeo.cpp
endef
LIBRETRO_FBNEO_PRE_BUILD_HOOKS += LIBRETRO_FBNEO_GENERATE_DRIVER_LIST

# Compiler flags precede upstream's own flags, preserving its required defines.
define LIBRETRO_FBNEO_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src/burner/libretro -f Makefile \
		platform=unix CC="$(TARGET_CC) $(TARGET_CFLAGS) -mcpu=cortex-a53" \
		CXX="$(TARGET_CXX) $(TARGET_CXXFLAGS) -mcpu=cortex-a53" \
		AR="$(TARGET_AR)" SUBSET=neogeo EXTERNAL_ZLIB=1
endef

define LIBRETRO_FBNEO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/src/burner/libretro/fbneo_neogeo_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/fbneo_neogeo_libretro.so
endef

$(eval $(generic-package))
