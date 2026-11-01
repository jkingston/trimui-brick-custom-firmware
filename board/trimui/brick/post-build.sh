#!/bin/sh
set -eu

# The shell and emulator present through display DRM. Keep PowerVR modules
# available for future use without powering the unused GPU at boot.
rm -f "$TARGET_DIR/etc/init.d/S40gpu"
