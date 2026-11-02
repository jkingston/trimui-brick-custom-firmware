################################################################################
#
# libretro-genesis-plus-gx
#
################################################################################

LIBRETRO_GENESIS_PLUS_GX_VERSION = f27655b592ef43f317272d79883bcaa10d3ac8ad
LIBRETRO_GENESIS_PLUS_GX_SITE = $(call github,libretro,Genesis-Plus-GX,$(LIBRETRO_GENESIS_PLUS_GX_VERSION))
LIBRETRO_GENESIS_PLUS_GX_LICENSE = Non-commercial
LIBRETRO_GENESIS_PLUS_GX_LICENSE_FILES = LICENSE.txt

define LIBRETRO_GENESIS_PLUS_GX_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) -f Makefile.libretro \
		platform=unix CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" \
		AR="$(TARGET_AR)" LD="$(TARGET_CC)" \
		HAVE_CHD=0 HAVE_CDROM=0 \
		CFLAGS="$(TARGET_CFLAGS) -mcpu=cortex-a53"
endef

define LIBRETRO_GENESIS_PLUS_GX_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/genesis_plus_gx_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/genesis_plus_gx_libretro.so
endef

$(eval $(generic-package))
