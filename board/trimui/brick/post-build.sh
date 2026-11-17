#!/bin/sh
set -eu

# S20brick-shell loads the governor, PowerVR and metadata modules in order,
# before the first GPU frame. Do not also start the historical S40 service.
rm -f "$TARGET_DIR/etc/init.d/S40gpu"

# The former physical-media presentation installed generated assets here.
# Remove them from reused Buildroot outputs as well as fresh configurations so
# dropping the package cannot leave an obsolete product flow in an image.
rm -rf "$TARGET_DIR/usr/share/brick/cartridges"

# Buildroot's mdev coldplug pass calls modprobe directly for every modalias.
# Blacklisting aliases prevents that pass while plain `modprobe pvrsrvkm`
# remains available to the shell's explicit startup sequence.
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
