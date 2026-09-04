#!/usr/bin/env bash
# Shared paths and helpers for the maintenance scripts. Source, don't run.

set -euo pipefail
# Guard clause to prevent multiple sourcing
[[ -n "${_GUARD_COMMON_SOURCED:-}" ]] && echo "common.sh already sourced." && return 0
_GUARD_COMMON_SOURCED=1

# Repo layout
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CUSTOMIZATIONS_SRC="$REPO_DIR/customizations"
# shellcheck disable=SC2034
ENFORCEMENT_SRC="$REPO_DIR/enforcement"

# Installed layout
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
INSTALL_DIR="${CUSTOM_CLAUDE_SETTINGS_HOME:-$CLAUDE_DIR/customizations/custom-claude-code-settings}"
BIN_DIR="$INSTALL_DIR/bin"
RESOURCES_DIR="$INSTALL_DIR/resources"
LOG_DIR="$INSTALL_DIR/logs"
ENFORCED_PATH="$RESOURCES_DIR/settings.enforced.json"
# shellcheck disable=SC2034
ENFORCER="$BIN_DIR/enforce-custom-claude-code-settings.py"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

# launchd
LABEL="com.user.custom-claude-code-settings.enforce"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
# shellcheck disable=SC2034
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

info() { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed${2:+ ($2)}"
}

# Substitute the @@...@@ placeholders available to customizations and templates.
render_placeholders() {
  sed \
    -e "s|@@LABEL@@|$LABEL|g" \
    -e "s|@@INSTALL_DIR@@|$INSTALL_DIR|g" \
    -e "s|@@BIN_DIR@@|$BIN_DIR|g" \
    -e "s|@@RESOURCES_DIR@@|$RESOURCES_DIR|g" \
    -e "s|@@LOG_DIR@@|$LOG_DIR|g" \
    -e "s|@@ENFORCED_PATH@@|$ENFORCED_PATH|g" \
    -e "s|@@SETTINGS_PATH@@|$SETTINGS_PATH|g" \
    -e "s|@@CLAUDE_DIR@@|$CLAUDE_DIR|g" \
    -e "s|@@HOME@@|$HOME|g" \
    "$@"
}

# Names of the customizations to install: every directory holding a
# customization.json, unless it carries a .disabled marker.
enabled_customizations() {
  local dir name
  for dir in "$CUSTOMIZATIONS_SRC"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ -f "$dir/customization.json" ]] || continue
    [[ -f "$dir/.disabled" ]] && continue
    printf '%s\n' "$name"
  done
}

service_loaded() {
  launchctl print "$SERVICE" >/dev/null 2>&1
}
