#!/usr/bin/env bash
# Status line segment: HBAR/USD price, 1h/24h change, last update time.
# Never blocks on the network — renders from the local price history and, if
# it's stale, kicks off a background refetch for next time.
# See ../../statusline/docs/statusline-segments.md for the segment contract.
set -uo pipefail

# bin/ isn't placeholder-rendered at install time, so derive our own
# location instead of hardcoding @@CACHE_DIR@@.
INSTALL_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CACHE_DIR="$INSTALL_DIR/cache/hbar-addicted"
HISTORY_PATH="$CACHE_DIR/price-history.tsv"
FETCHER="$INSTALL_DIR/bin/hbar-price-fetch.sh"

TTL=300  # refetch in the background once the latest sample is older than this

GREEN='\033[2;32m'
RED='\033[2;31m'
YELLOW='\033[2;33m'
GREY='\033[2m'
RESET='\033[0m'

refetch_in_background() {
  [[ -x "$FETCHER" ]] && nohup "$FETCHER" >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# BSD (`date -r`, macOS) vs GNU (`date -d @epoch`, Linux) date-from-epoch.
format_epoch() {
  local epoch="$1" fmt="$2"
  date -r "$epoch" "+$fmt" 2>/dev/null || date -d "@$epoch" "+$fmt" 2>/dev/null
}

if [[ ! -s "$HISTORY_PATH" ]]; then
  refetch_in_background
  printf '%b' "${GREY}HBAR n/a${RESET}"
  exit 0
fi

now=$(date +%s)

# Single pass over the history: latest sample, plus the ones nearest to
# now-3600 and now-86400 (the 1h/24h reference points), and whether the
# history's earliest sample is old enough to actually cover each window.
read -r last_price last_epoch cover_1h ref_price_1h cover_24h ref_price_24h < <(
  awk -F'\t' -v t1="$((now - 3600))" -v t2="$((now - 86400))" '
    NR == 1 { min_epoch = $1 }
    {
      epoch = $1; price = $2
      if (epoch < min_epoch) min_epoch = epoch
      if (NR == 1 || epoch > max_epoch) { max_epoch = epoch; last_price = price }
      d1 = (epoch > t1) ? epoch - t1 : t1 - epoch
      if (NR == 1 || d1 < best1_diff) { best1_diff = d1; best1_price = price }
      d2 = (epoch > t2) ? epoch - t2 : t2 - epoch
      if (NR == 1 || d2 < best2_diff) { best2_diff = d2; best2_price = price }
    }
    END {
      cover1 = (min_epoch <= t1) ? 1 : 0
      cover2 = (min_epoch <= t2) ? 1 : 0
      printf "%s %s %d %s %d %s\n", last_price, max_epoch, cover1, best1_price, cover2, best2_price
    }
  ' "$HISTORY_PATH"
)

((now - last_epoch > TTL)) && refetch_in_background

price_display="$(awk -v p="$last_price" 'BEGIN { printf "$%.5f", p }')"

time_fmt='%H:%M'
[[ "$(format_epoch "$last_epoch" '%Y-%m-%d')" != "$(date '+%Y-%m-%d')" ]] && time_fmt='%d/%m %H:%M'
time_display="@$(format_epoch "$last_epoch" "$time_fmt")"

price_part="${YELLOW}HBAR ${price_display}${RESET}"
time_part="${GREY}${time_display}${RESET}"

# COVERED (0/1), OLD_PRICE, LABEL -> "<colored change or a dash> (<label>)",
# fully green/red for the direction, or grey when the window isn't covered.
format_change() {
  local covered="$1" old_price="$2" label="$3"
  if [[ "$covered" != "1" ]]; then
    printf '%s- (%s)%s' "$GREY" "$label" "$RESET"
    return
  fi
  awk -v old="$old_price" -v new="$last_price" -v label="$label" \
    -v green="$GREEN" -v red="$RED" -v reset="$RESET" 'BEGIN {
    pct = (new - old) / old * 100
    arrow = (pct >= 0) ? "▲" : "▼"
    color = (pct >= 0) ? green : red
    if (pct < 0) pct = -pct
    printf "%s%s%.2f%% (%s)%s", color, arrow, pct, label, reset
  }'
}

change_1h="$(format_change "$cover_1h" "$ref_price_1h" "1h")"
change_24h="$(format_change "$cover_24h" "$ref_price_24h" "24h")"

printf '%b %b %b %b' "$time_part" "$price_part" "$change_24h" "$change_1h"
