#!/usr/bin/env bash
# Status line host: renders the segments contributed by other
# customizations (each declares one via resources/statusline-segment.json).
# Owns only ordering and the separator between segments — no knowledge of
# model, git, prices, etc. See ../docs/statusline-segments.md for the contract.
set -uo pipefail

# bin/ isn't placeholder-rendered at install time, so derive our own
# location instead of hardcoding @@RESOURCES_DIR@@/@@BIN_DIR@@. This also
# keeps segment resolution portable when ~/.claude is later mounted under a
# different $HOME (e.g. a container), since only a relative command name is
# baked into each segment's manifest, not an absolute host path.
INSTALL_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
RESOURCES_DIR="$INSTALL_DIR/resources"
BIN_DIR="$INSTALL_DIR/bin"

GREY='\033[2m'
RED='\033[31m'
RESET='\033[0m'
SEGMENT_SEPARATOR="${GREY} │ ${RESET}"

input="$(cat)"

# "<order>\t<dir>\t<command>" for every installed segment, sorted by
# (order, directory name) so left-to-right placement is deterministic.
segment_manifests() {
  local manifest dir order command
  for manifest in "$RESOURCES_DIR"/*/statusline-segment.json; do
    [[ -f "$manifest" ]] || continue
    dir="$(basename "$(dirname "$manifest")")"
    order="$(jq -r '.order // 0' "$manifest" 2>/dev/null)"
    [[ "$order" =~ ^-?[0-9]+$ ]] || order=0
    command="$(jq -r '.command // empty' "$manifest" 2>/dev/null)"
    [[ -n "$command" ]] || continue
    printf '%s\t%s\t%s\n' "$order" "$dir" "$command"
  done | sort -t $'\t' -k1,1n -k2,2
}

output=""
while IFS=$'\t' read -r order dir command; do
  [[ -n "$dir" ]] || continue

  # Manifests declare a bare filename resolved against the shared bin/ dir;
  # an absolute path (as used by the test suite's throwaway fixtures) is
  # honored as-is.
  [[ "$command" == /* ]] || command="$BIN_DIR/$command"

  segment_ok=false
  segment_output=""
  if [[ -x "$command" ]] && segment_output="$(printf '%s' "$input" | "$command" 2>/dev/null)"; then
    segment_ok=true
  fi

  if ! $segment_ok; then
    piece="${RED}${dir}!${RESET}"
  elif [[ -n "$segment_output" ]]; then
    piece="$segment_output"
  else
    continue
  fi

  if [[ -n "$output" ]]; then
    output="${output}${SEGMENT_SEPARATOR}${piece}"
  else
    output="$piece"
  fi
done < <(segment_manifests)

printf '%b' "$output"
