#!/usr/bin/env bash
# Fetch HBAR/USD 5-minute price samples from CoinMarketCap's chart API and
# use them to replace the local price history, which is what makes the
# 1h/24h change in hbar-segment.sh possible.
#
# Safe to run by hand for diagnosis; logs errors instead of failing loudly.
set -uo pipefail

# bin/ isn't placeholder-rendered at install time, so derive our own
# location instead of hardcoding @@CACHE_DIR@@/@@LOG_DIR@@.
INSTALL_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CACHE_DIR="$INSTALL_DIR/cache/hbar-addicted"
LOG_DIR="$INSTALL_DIR/logs/hbar-addicted"
HISTORY_PATH="$CACHE_DIR/price-history.tsv"
LOCK_DIR="$CACHE_DIR/.fetch.lock"

STALE_LOCK_SECONDS=60
# Kept a bit past 24h: this cutoff is computed relative to fetch time, but
# hbar-segment.sh later checks coverage against its own (later) render time,
# so the oldest sample must still reach 24h back by then too. Without this
# margin the retained history was trimmed right at the 24h line, so the 24h
# change dashed out until enough time had passed since the last fetch.
RETENTION_MARGIN_SECONDS=$((30 * 60))
RETENTION_SECONDS=$((24 * 3600 + RETENTION_MARGIN_SECONDS))
# id=4642 is HBAR, convertId=2781 is USD. The API returns far more than 24h
# of samples no matter what range is requested, so the last-24h-plus-margin
# window is enforced locally below via RETENTION_SECONDS.
CHART_URL="https://api.coinmarketcap.com/data-api/v3.3/cryptocurrency/detail/chart?id=4642&interval=5m&convertId=2781"

mkdir -p "$CACHE_DIR" "$LOG_DIR"

log_error() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_DIR/price.log"
}

# GNU form first: GNU stat's `-f` means "filesystem status", a real flag that
# still runs (dumping filesystem info to stdout) before failing on `%m` as a
# bogus second file operand, so trying it second would leak that garbage into
# our stdout instead of just failing cleanly like BSD stat's `-c` does.
lock_mtime() {
  stat -c %Y "$LOCK_DIR" 2>/dev/null || stat -f %m "$LOCK_DIR" 2>/dev/null
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  age=$(($(date +%s) - $(lock_mtime || echo 0)))
  if ((age > STALE_LOCK_SECONDS)); then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { log_error "could not acquire lock even after clearing a stale one"; exit 1; }
  else
    # Another fetch is already in flight; nothing to do.
    exit 0
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

response="$(curl -fsS --max-time 5 "$CHART_URL" 2>&1)"
curl_rc=$?
if [[ $curl_rc -ne 0 ]]; then
  log_error "curl failed (exit $curl_rc): $response"
  exit 1
fi

if ! error_code="$(jq -e -r '.status.error_code' <<<"$response" 2>&1)"; then
  log_error "malformed response (not JSON), history left untouched: $response"
  exit 1
fi
if [[ "$error_code" != "0" ]]; then
  log_error "API error (code $error_code), history left untouched: $response"
  exit 1
fi

if ! points="$(jq -e -r '.data.points[] | select(.v[0] != null) | "\(.s)\t\(.v[0])"' <<<"$response" 2>&1)"; then
  log_error "could not extract points, history left untouched: $points"
  exit 1
fi

now=$(date +%s)
cutoff=$((now - RETENTION_SECONDS))
tmp_history="$(mktemp "$CACHE_DIR/.price-history.XXXXXX")"
# The API returns far more than 24h of samples, so the fetched (and
# cutoff-filtered) points replace the local history outright instead of
# being appended to it. Sorted and deduped by epoch in case the API ever
# repeats a bucket.
awk -F'\t' -v cutoff="$cutoff" '$1 >= cutoff' <<<"$points" \
  | sort -t $'\t' -k1,1n \
  | awk -F'\t' '!seen[$1]++' \
  >"$tmp_history"
mv "$tmp_history" "$HISTORY_PATH"
