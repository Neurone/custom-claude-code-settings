#!/usr/bin/env bash
# Show logs. Pass -f to follow them, and/or a customization name to show its
# logs instead of the watchdog's.
#
#   scripts/logs.sh                last 40 lines of the watchdog log
#   scripts/logs.sh -f              follow the watchdog log
#   scripts/logs.sh hbar-addicted   last 40 lines of logs/hbar-addicted/*.log
#   scripts/logs.sh -f hbar-addicted   follow logs/hbar-addicted/*.log
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

follow=false
name=""
lines=40
for arg in "$@"; do
  if [[ "$arg" = "-f" ]]; then
    follow=true
  elif [[ "$arg" =~ ^[0-9]+$ ]]; then
    lines="$arg"
  else
    name="$arg"
  fi
done

if [[ -n "$name" ]]; then
  customization_exists "$name" || die "unknown customization: $name; available: $(available_customizations_line)"
  log_dir="$LOG_DIR/$name"
  logs=()
  if [[ -d "$log_dir" ]]; then
    for f in "$log_dir"/*.log; do [[ -f "$f" ]] && logs+=("$f"); done
  fi
else
  log_dir="$LOG_DIR"
  logs=("$LOG_DIR/enforce.log" "$LOG_DIR/enforce.out.log" "$LOG_DIR/enforce.err.log")
fi
existing=()
for f in "${logs[@]+"${logs[@]}"}"; do [[ -f "$f" ]] && existing+=("$f"); done
[[ ${#existing[@]} -gt 0 ]] || die "no logs in $log_dir yet"

if $follow; then
  ok "Following logs in $log_dir"
  exec tail -f "${existing[@]}"
fi
ok "Last $lines lines from $log_dir"
tail -n "$lines" "${existing[@]}"
