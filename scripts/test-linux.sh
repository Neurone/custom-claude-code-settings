#!/usr/bin/env bash
# Linux smoke test for the maintenance scripts, run inside disposable
# debian:bookworm containers via Docker. Dev only: needs Docker and network
# access (for apt-get). Not part of scripts/shellcheck.sh's runtime checks.
#
# Two passes, both mounting the repo read-only and pointing CLAUDE_DIR at a
# throwaway path inside the container:
#
#   A - no systemd installed at all (the base image's default state). Asserts
#       install/status/enforce-now/uninstall all still work end to end, with
#       a warning instead of a running watchdog.
#   B - systemd package installed, but no user manager running — the
#       container case scripts/lib/platform-linux.sh detects and degrades
#       from (the systemctl binary exists, nothing is listening on the
#       user bus). Asserts the availability check still says "no", and that
#       the three unit files were rendered anyway with real paths substituted.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="debian:bookworm"

command -v docker >/dev/null 2>&1 || { echo "'docker' is required but not installed" >&2; exit 1; }

run_pass() {
  local name="$1" extra_pkgs="$2" body="$3"
  echo
  echo "=== $name ==="
  docker run --rm -v "$REPO_DIR:/repo:ro" "$IMAGE" bash -euo pipefail -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq jq python3 $extra_pkgs >/dev/null
    export CLAUDE_DIR=/root/.claude-test
    export LABEL_FILE_BASE=com.user.custom-claude-code-settings.enforce
    $body
  "
}

# The body strings below run inside the container's shell via `bash -c`, not
# this one, so their $-expressions are intentionally left unexpanded here.
# shellcheck disable=SC2016
run_pass "Pass A: no systemd installed" "" '
  set -x
  out="$(/repo/scripts/install-or-update.sh 2>&1)"
  echo "$out" | grep -q "no user service manager available" \
    || { echo "FAIL: expected no-watchdog warning"; exit 1; }
  jq -e ".showClearContextOnPlanAccept == true" "$CLAUDE_DIR/settings.json" >/dev/null \
    || { echo "FAIL: enforced keys missing from settings.json after install"; exit 1; }

  /repo/scripts/status.sh
  /repo/scripts/enforce-now.sh
  /repo/scripts/uninstall.sh

  if jq -e ".showClearContextOnPlanAccept" "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
    echo "FAIL: enforced keys still present after uninstall"; exit 1
  fi
  [[ ! -d "$CLAUDE_DIR/customizations/custom-claude-code-settings" ]] \
    || { echo "FAIL: install dir still present after uninstall"; exit 1; }
  echo "PASS A"
'

# shellcheck disable=SC2016
run_pass "Pass B: systemd package installed, no user manager running" "systemd" '
  set -x
  out="$(/repo/scripts/install-or-update.sh 2>&1)"
  echo "$out" | grep -q "no user service manager available" \
    || { echo "FAIL: expected no-watchdog warning (systemctl binary present but no user manager)"; exit 1; }

  unit_dir="$HOME/.config/systemd/user"
  for unit in service path timer; do
    f="$unit_dir/$LABEL_FILE_BASE.$unit"
    [[ -f "$f" ]] || { echo "FAIL: missing rendered unit file $f"; exit 1; }
    grep -q "@@" "$f" && { echo "FAIL: leftover @@ placeholder in $f"; exit 1; }
    grep -q "$LABEL_FILE_BASE" "$f" \
      || { echo "FAIL: $f missing the substituted label"; exit 1; }
  done
  grep -q "$CLAUDE_DIR/settings.json" "$unit_dir/$LABEL_FILE_BASE.path" \
    || { echo "FAIL: enforce.path unit missing the substituted settings path"; exit 1; }
  grep -q "$CLAUDE_DIR/settings.json" "$unit_dir/$LABEL_FILE_BASE.service" \
    || { echo "FAIL: enforce.service unit missing the substituted settings path"; exit 1; }
  echo "PASS B"
'

echo
echo "scripts/test-linux.sh: all passes green"
