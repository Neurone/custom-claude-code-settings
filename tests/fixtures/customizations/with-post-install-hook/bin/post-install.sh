#!/usr/bin/env bash
# Test fixture: records that the hook ran and what INSTALL_DIR it received.
set -uo pipefail
printf '%s' "$1" > "$1/post-install-hook-received-install-dir.txt"
