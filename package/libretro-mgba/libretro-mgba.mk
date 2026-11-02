################################################################################
#
# libretro-mgba
#
################################################################################

LIBRETRO_MGBA_VERSION = 7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6
LIBRETRO_MGBA_SITE = $(call github,libretro,mgba,$(LIBRETRO_MGBA_VERSION))
LIBRETRO_MGBA_LICENSE = MPL-2.0
LIBRETRO_MGBA_LICENSE_FILES = LICENSE
LIBRETRO_MGBA_CONF_OPTS = \
	-DBUILD_LIBRETRO=ON \
	-DBUILD_QT=OFF \
	-DBUILD_SDL=OFF \
	-DBUILD_SHARED=OFF \
	-DBUILD_STATIC=OFF \
	-DSKIP_LIBRARY=ON \
	-DDISABLE_DEPS=ON \
	-DENABLE_DEBUGGERS=OFF \
	-DENABLE_GDB_STUB=OFF \
	-DLIBRETRO_LIBDIR=/usr/lib/libretro

define LIBRETRO_MGBA_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/mgba_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/mgba_libretro.so
endef

$(eval $(cmake-package))
