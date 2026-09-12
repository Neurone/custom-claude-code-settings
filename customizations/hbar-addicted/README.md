# HBAR Addicted

A `statusline` segment (see
[`docs/statusline-segments.md`](../statusline/docs/statusline-segments.md)) showing
the HBAR/USD price, its 1h/24h change, and when it was last updated:

```text
@14:32 HBAR $0.07470 ▼1.83% (24h) ▲0.42% (1h)
```

- Green `▲` for a positive change, red `▼` for a negative one, gray `-` when
  the local history doesn't cover that window yet (first run, or a gap after
  the machine was off/offline for a while) — never a misleading percentage
  computed from a handful of minutes of data.
- `@HH:MM` if the last sample is from today, `@DD/MM HH:MM` otherwise.
- No samples at all yet ⇒ `HBAR n/a` in gray.

## How it stays fresh without blocking

CoinMarketCap's chart API
(`api.coinmarketcap.com/data-api/v3.3/cryptocurrency/detail/chart`, id=4642
for HBAR, convertId=2781 for USD) returns far more than 24h of 5-minute
samples in one JSON call (there's no request param that limits it to 24h),
so every fetch trims the response to the last 24h plus a 30-minute margin
and replaces the local history outright instead of building it up sample by
sample. The margin matters: the 24h cutoff is computed at fetch time, but
`hbar-segment.sh` checks coverage against its own (later) render time, so
without it the retained history was trimmed right at the 24h line and the
24h change dashed out until enough time had passed since the last fetch.

- `bin/hbar-price-fetch.sh` — fetches the chart JSON and rewrites
  `cache/hbar-addicted/price-history.tsv` as `<epoch>\t<price>` lines, one
  per point (sorted, deduped by epoch, anything older than 24h plus the
  margin dropped), atomically (temp file + `mv`). A malformed/non-JSON
  response, a non-zero `status.error_code`, or a failed `curl` is logged to
  `logs/hbar-addicted/price.log` and leaves the history untouched. Locked
  via an atomic `mkdir`, with a stale lock (older than 60s — a previous run
  that died) cleared automatically. Safe to run by hand for diagnosis.
- `bin/hbar-segment.sh` — the segment. If the latest sample is older than 5
  minutes (`TTL`), it launches the fetcher in the background and renders
  whatever it already has: **rendering never waits on the network.** The
  1h/24h changes come from a single `awk` pass over the history, picking the
  sample nearest to `now-3600` and `now-86400`.
- `customization.json` — `{"statusLine": {"refreshInterval": 60}}`, deep-merged
  on top of `statusline`'s own fragment so the price and the `@HH:MM` stay
  current even when the session is idle. This is the reason a segment
  customization is allowed to add settings of its own on top of what it
  requires.
- `resources/statusline-segment.json` — declares `order: 20` to the host
- `customization.meta.json` — `requires: ["statusline"]`

## Requirements

`curl`, `awk`, `jq` (used by `hbar-price-fetch.sh` to parse the chart JSON).

## Diagnosing

```bash
scripts/logs.sh hbar-addicted                 # fetch errors, if any
customizations/hbar-addicted/bin/hbar-price-fetch.sh   # fetch once, by hand
echo '{}' | customizations/hbar-addicted/bin/hbar-segment.sh   # render once, by hand
```
