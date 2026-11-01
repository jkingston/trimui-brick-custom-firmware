################################################################################
#
# retroarch
#
################################################################################

RETROARCH_VERSION = 1.22.2
RETROARCH_SITE = $(call github,libretro,RetroArch,v$(RETROARCH_VERSION))
RETROARCH_LICENSE = GPL-3.0
RETROARCH_LICENSE_FILES = COPYING
RETROARCH_DEPENDENCIES = host-pkgconf alsa-lib libdrm libudev
RETROARCH_TARGET_CFLAGS = $(TARGET_CFLAGS) -mcpu=cortex-a53

RETROARCH_CONF_OPTS = \
	--prefix=/usr \
	--host=$(GNU_TARGET_NAME) \
	--enable-alsa \
	--enable-builtinzlib \
	--enable-dynamic \
	--enable-menu \
	--enable-plain_drm \
	--enable-rgui \
	--enable-threads \
	--enable-udev \
	--disable-caca \
	--disable-cheevos \
	--disable-egl \
	--disable-ffmpeg \
	--disable-gfx_widgets \
	--disable-kms \
	--disable-materialui \
	--disable-mpv \
	--disable-networking \
	--disable-neon \
	--disable-opengl \
	--disable-opengl1 \
	--disable-opengl_core \
	--disable-ozone \
	--disable-pipewire \
	--disable-pulse \
	--disable-sdl \
	--disable-sdl2 \
	--disable-vulkan \
	--disable-wayland \
	--disable-x11 \
	--disable-xmb \
	--enable-zlib

define RETROARCH_CONFIGURE_CMDS
	(cd $(@D); \
		$(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(RETROARCH_TARGET_CFLAGS)" \
		CXXFLAGS="$(TARGET_CXXFLAGS) -mcpu=cortex-a53" \
		PKG_CONF_PATH="$(HOST_DIR)/bin/pkg-config" \
		PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)" \
		PKG_CONFIG_LIBDIR="$(STAGING_DIR)/usr/lib/pkgconfig:$(STAGING_DIR)/usr/share/pkgconfig" \
		./configure $(RETROARCH_CONF_OPTS))
endef

define RETROARCH_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" CXX="$(TARGET_CXX)" AR="$(TARGET_AR)" \
		DRM_CFLAGS="`$(HOST_DIR)/bin/pkg-config --cflags libdrm`"
endef

define RETROARCH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/retroarch $(TARGET_DIR)/usr/bin/retroarch
endef

$(eval $(generic-package))
