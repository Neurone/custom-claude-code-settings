#!/usr/bin/env bash
# Install-time hook (see scripts/install-or-update.sh): populates the price
# history synchronously, once, so the very first statusline render after
# install already has a real price instead of "n/a" until the first
# TTL-triggered background refetch (hbar-segment.sh) gets a chance to run.
# Best-effort: a failed fetch here just leaves hbar-segment.sh to fall back
# to its normal "n/a" + background refetch behavior, same as offline usage.
set -uo pipefail

install_dir="$1"
"$install_dir/bin/hbar-price-fetch.sh" || true
