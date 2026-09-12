#!/usr/bin/env bash
# Single entry point for the whole test suite.
#
# Runs the native suite directly on this host, but only when the host is
# macOS (the platform this repo is developed on day to day) — then always
# runs the Linux suite via scripts/test-linux.sh. On a non-macOS host, the
# native run is skipped: scripts/test-linux.sh's own Pass 1 already covers a
# full Linux-native run of the same suite, either in a disposable Docker
# container, or directly on this host if it's already Linux and Docker isn't
# available (see scripts/test-linux.sh).
#
# Requires Docker for the Linux suite, unless this host is already Linux (see
# above), and jq/python3/shellcheck on macOS.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_DIR"

if [[ "$(uname -s)" = "Darwin" ]]; then
  echo "=== macOS: full test suite (tests/, shellcheck) ==="
  python3 -m unittest discover tests
  scripts/shellcheck.sh
  echo
else
  echo "Skipping native macOS suite (this host is $(uname -s), not Darwin)."
  echo
fi

echo "=== Linux: full test suite (plus install/uninstall verification via Docker, when available) ==="
scripts/test-linux.sh

echo
echo "scripts/test-all.sh: all suites green"
