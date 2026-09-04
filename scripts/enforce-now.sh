#!/usr/bin/env bash
# Run the installed enforcement utility once, right now, and show the result.
# Handy after editing ~/.claude/settings.json by hand.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

[[ -x "$ENFORCER" ]] || die "not installed — run scripts/install-or-update.sh"

"$ENFORCER"
step "Enforced keys in $SETTINGS_PATH"
if command -v jq >/dev/null 2>&1; then
  jq -n --slurpfile s "$SETTINGS_PATH" --slurpfile e "$ENFORCED_PATH" \
    '$e[0] | keys[] as $k | {($k): $s[0][$k]}' | sed 's/^/  /'
fi
step "Last log lines"
tail -n 5 "$LOG_DIR/enforce.log" 2>/dev/null | sed 's/^/  /' || info "no log yet"
