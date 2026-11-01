#!/bin/sh
set -eu

# The shell and emulator present through display DRM. Keep PowerVR modules
# available for future explicit use without powering the unused GPU at boot.
rm -f "$TARGET_DIR/etc/init.d/S40gpu"

# Buildroot's mdev coldplug pass calls modprobe directly for every modalias.
# Blacklisting aliases prevents that pass while plain `modprobe pvrsrvkm`
# remains available when a future UI explicitly enables the GPU.
install -d "$TARGET_DIR/etc/modprobe.d"
printf '%s\n' 'blacklist pvrsrvkm' \
	> "$TARGET_DIR/etc/modprobe.d/brick-ui.conf"

# mdev otherwise loads pvrsrvkm from the GPU's device-tree modalias. A matching
# rule without a command stops at this entry and leaves explicit modprobe usable.
gpu_rule='$MODALIAS=.*sun50i-a133-gpu.* root:root 660'
if ! grep -Fqx "$gpu_rule" "$TARGET_DIR/etc/mdev.conf"; then
	{ printf '%s\n' "$gpu_rule"; cat "$TARGET_DIR/etc/mdev.conf"; } \
		> "$TARGET_DIR/etc/mdev.conf.tmp"
	mv "$TARGET_DIR/etc/mdev.conf.tmp" "$TARGET_DIR/etc/mdev.conf"
fi
