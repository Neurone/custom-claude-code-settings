#!/usr/bin/env bash
# Check the shell scripts in the repository for issues using shellcheck.
set -uo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# `shellcheck` has issues with using relative paths, so we always cd to the repository root first.
cd -- "$REPO_DIR" || exit 1
find . -name "*.sh" -print0 | xargs -0 shellcheck -x --color=auto
