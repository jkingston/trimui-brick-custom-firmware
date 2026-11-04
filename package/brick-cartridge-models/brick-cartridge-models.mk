BRICK_CARTRIDGE_MODELS_VERSION = 0.1.0
BRICK_CARTRIDGE_MODELS_SOURCE = trimui-brick-cartridge-models-$(BRICK_CARTRIDGE_MODELS_VERSION).tar.gz
BRICK_CARTRIDGE_MODELS_SITE = https://github.com/jkingston/trimui-brick-cartridge-assets/releases/download/v$(BRICK_CARTRIDGE_MODELS_VERSION)
BRICK_CARTRIDGE_MODELS_LICENSE = Proprietary

define BRICK_CARTRIDGE_MODELS_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/share/brick/cartridge-models/models
	cp -a $(@D)/models/. $(TARGET_DIR)/usr/share/brick/cartridge-models/models/
	$(INSTALL) -m 0644 $(@D)/models-index.json \
		$(TARGET_DIR)/usr/share/brick/cartridge-models/models-index.json
	$(INSTALL) -m 0644 $(@D)/SHA256SUMS \
		$(TARGET_DIR)/usr/share/brick/cartridge-models/SHA256SUMS
endef

$(eval $(generic-package))
