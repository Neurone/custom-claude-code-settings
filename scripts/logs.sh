#!/usr/bin/env bash
# Show the enforcement logs. Pass -f to follow them.
#
#   scripts/logs.sh        last 40 lines of each log
#   scripts/logs.sh -f     follow
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

logs=("$LOG_DIR/enforce.log" "$LOG_DIR/enforce.out.log" "$LOG_DIR/enforce.err.log")
existing=()
for f in "${logs[@]}"; do [[ -f "$f" ]] && existing+=("$f"); done
[[ ${#existing[@]} -gt 0 ]] || die "no logs in $LOG_DIR yet"

if [[ "${1:-}" = "-f" ]]; then
  ok "Following logs in $LOG_DIR"
  exec tail -f "${existing[@]}"
fi
ok "Last ${1:-40} lines from $LOG_DIR"
tail -n "${1:-40}" "${existing[@]}"
