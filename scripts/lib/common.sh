#!/usr/bin/env bash
# Shared paths and helpers for the maintenance scripts. Source, don't run.

set -euo pipefail
# Guard clause to prevent multiple sourcing
[[ -n "${_GUARD_COMMON_SOURCED:-}" ]] && echo "common.sh already sourced." && return 0
_GUARD_COMMON_SOURCED=1

# Repo layout
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CUSTOMIZATIONS_SRC="${CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS:-$REPO_DIR/customizations}"
# shellcheck disable=SC2034
ENFORCEMENT_SRC="$REPO_DIR/enforcement"

# Installed layout
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
INSTALL_DIR="${CUSTOM_CLAUDE_SETTINGS_HOME:-$CLAUDE_DIR/customizations/custom-claude-code-settings}"
BIN_DIR="$INSTALL_DIR/bin"
RESOURCES_DIR="$INSTALL_DIR/resources"
LOG_DIR="$INSTALL_DIR/logs"
LOG_PATH="$LOG_DIR/enforce.log"
BACKUP_DIR="$INSTALL_DIR/backups"
# shellcheck disable=SC2034
CACHE_DIR="$INSTALL_DIR/cache"
ENFORCED_PATH="$RESOURCES_DIR/settings.enforced.json"
# shellcheck disable=SC2034
INSTALL_MANIFEST="$RESOURCES_DIR/installed.json"
# shellcheck disable=SC2034
ENFORCER="$BIN_DIR/enforce-custom-claude-code-settings.py"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

# The Python enforcer re-derives these same paths on its own (from $HOME and
# its own install location) when these env vars are unset. Export them so a
# CLAUDE_DIR/CUSTOM_CLAUDE_SETTINGS_HOME override here always wins, instead
# of the two sides agreeing only by coincidence in the default case.
export CUSTOM_CLAUDE_SETTINGS_TARGET="$SETTINGS_PATH"
export CUSTOM_CLAUDE_SETTINGS_ENFORCED="$ENFORCED_PATH"
export CUSTOM_CLAUDE_SETTINGS_LOG="$LOG_PATH"
export CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR="$BACKUP_DIR"

# Service identifier. Rendered into templates as @@LABEL@@ and used as-is by
# both backends (launchd Label, systemd unit basename), so its value must stay
# identical across platforms.
LABEL="${CUSTOM_CLAUDE_SETTINGS_LABEL:-com.user.custom-claude-code-settings.enforce}"

# shellcheck disable=SC2034  # C_BOLD is used by scripts that source this file
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_RESET=''
fi

info() { printf '  %s\n' "$*"; }
step() { printf '= %s\n' "$*"; }
ok()   { printf '%s\xe2\x9c\x93%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s warning: %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s\xe2\x9c\x97%s error: %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Join arguments with a separator, e.g. join_by ", " a b c -> "a, b, c".
join_by() {
  local sep="$1"
  shift
  local out="" first=true item
  for item in "$@"; do
    if $first; then out="$item"; first=false; else out="$out$sep$item"; fi
  done
  printf '%s' "$out"
}

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
    -e "s|@@LOG_PATH@@|$LOG_PATH|g" \
    -e "s|@@BACKUP_DIR@@|$BACKUP_DIR|g" \
    -e "s|@@CACHE_DIR@@|$CACHE_DIR|g" \
    -e "s|@@ENFORCED_PATH@@|$ENFORCED_PATH|g" \
    -e "s|@@SETTINGS_PATH@@|$SETTINGS_PATH|g" \
    -e "s|@@CLAUDE_DIR@@|$CLAUDE_DIR|g" \
    -e "s|@@HOME@@|$HOME|g" \
    "$@"
}

# Names of every customization directory that holds a customization.json.
all_customizations() {
  local dir name
  for dir in "$CUSTOMIZATIONS_SRC"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ -f "$dir/customization.json" ]] || continue
    printf '%s\n' "$name"
  done
}

customization_exists() {
  [[ -f "$CUSTOMIZATIONS_SRC/$1/customization.json" ]]
}

# Comma-separated list of every known customization name, for error messages.
available_customizations_line() {
  local names
  names="$(all_customizations | paste -sd, - | sed 's/,/, /g')"
  printf '%s' "${names:-none found}"
}

# True (rc 0) if ITEM is among ITEMS. Linear scan: bash 3.2 (macOS) has no
# associative arrays, so this is the portable substitute for a set lookup.
list_contains() {
  local item="$1"
  shift
  local candidate
  for candidate in "$@"; do
    [[ "$candidate" = "$item" ]] && return 0
  done
  return 1
}

# The "description" field of NAME's optional customization.meta.json, or "".
customization_description() {
  local meta="$CUSTOMIZATIONS_SRC/$1/customization.meta.json"
  [[ -f "$meta" ]] || return 0
  jq -r '.description // ""' "$meta"
}

# The "requires" list of NAME's optional customization.meta.json, one name per
# line; nothing if the file or the field is absent.
customization_requires() {
  local meta="$CUSTOMIZATIONS_SRC/$1/customization.meta.json"
  [[ -f "$meta" ]] || return 0
  jq -r '.requires[]? // empty' "$meta"
}

# Internal DFS helper for resolve_dependencies. Relies on bash's dynamic
# scoping: result/visiting/visited are locals of the calling
# resolve_dependencies invocation, not of this function.
_resolve_dependencies_visit() {
  local name="$1"
  customization_exists "$name" || die "unknown customization: $name; available: $(available_customizations_line)"
  list_contains "$name" "${visited[@]+"${visited[@]}"}" && return 0
  list_contains "$name" "${visiting[@]+"${visiting[@]}"}" && die "dependency cycle detected involving: $name"
  visiting+=("$name")
  local dep
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    _resolve_dependencies_visit "$dep"
  done < <(customization_requires "$name")
  local -a remaining=()
  local v
  for v in "${visiting[@]+"${visiting[@]}"}"; do
    [[ "$v" = "$name" ]] || remaining+=("$v")
  done
  visiting=("${remaining[@]+"${remaining[@]}"}")
  visited+=("$name")
  result+=("$name")
}

# Transitive closure of NAMES..., in topological order (dependencies before
# dependents). Dies on an unknown customization or a dependency cycle.
resolve_dependencies() {
  local -a result=()
  local -a visiting=()
  local -a visited=()
  local name
  for name in "$@"; do
    _resolve_dependencies_visit "$name"
  done
  # printf still runs its format once even with zero args (emitting a spurious
  # blank line), so guard explicitly instead of relying on it to print nothing.
  ((${#result[@]})) && printf '%s\n' "${result[@]}"
  return 0
}

# Names listed in $INSTALL_MANIFEST, one per line; nothing if it doesn't exist yet.
installed_customizations() {
  [[ -f "$INSTALL_MANIFEST" ]] || return 0
  jq -r '.customizations[]? // empty' "$INSTALL_MANIFEST"
}

# Overwrite $INSTALL_MANIFEST with exactly NAMES....
write_install_manifest() {
  mkdir -p "$RESOURCES_DIR"
  jq -n --args '{"customizations": $ARGS.positional}' -- "$@" >"$INSTALL_MANIFEST"
}

# Render NAME's customization.json into OUT, validating it's a JSON object
# after placeholder substitution.
render_customization_fragment() {
  local name="$1" out="$2"
  render_placeholders "$CUSTOMIZATIONS_SRC/$name/customization.json" >"$out"
  jq empty "$out" 2>/dev/null || die "$name/customization.json is not valid JSON after rendering"
  [[ "$(jq -r 'type' "$out")" = "object" ]] || die "$name/customization.json must contain a JSON object"
}

# Deep-merge one JSON object per fragment file into a single object, written
# to $1. Later fragments win on overlapping keys.
merge_fragments() {
  local out="$1"
  shift
  jq -s 'reduce .[] as $fragment ({}; . * $fragment)' "$@" >"$out"
}

# Render and deep-merge the customization.json of each given name into one
# JSON object, written to $1. Later names win on overlapping keys, same rule
# as install-or-update.sh's own merge.
build_settings_fragment() {
  local out="$1"
  shift
  local work_dir
  work_dir="$(mktemp -d)"
  local fragments=()
  local name fragment
  for name in "$@"; do
    fragment="$work_dir/$name.json"
    render_customization_fragment "$name" "$fragment"
    fragments+=("$fragment")
  done
  merge_fragments "$out" "${fragments[@]}"
  rm -rf "$work_dir"
}

# Platform-specific service backend (launchd on macOS, systemd on Linux).
# Contract implemented by both, this is the whole surface:
#   service_require_cmds  die on missing hard deps
#   service_files         print one absolute service-definition path per line
#   service_install       render + load. rc 0 = loaded, 2 = files written but
#                          no usable service manager
#   service_reload        rc 0 = reloaded, 1 = service files missing
#   service_unload        rc 0 = was loaded, 1 = was not; also removes the
#                          service files
#   service_status        print one human-readable line. rc 0 loaded,
#                          1 not loaded, 2 manager unusable
case "$(uname -s)" in
  Darwin)
    # shellcheck source=SCRIPTDIR/platform-darwin.sh
    source "$(dirname -- "${BASH_SOURCE[0]}")/platform-darwin.sh"
    ;;
  Linux)
    # shellcheck source=SCRIPTDIR/platform-linux.sh
    source "$(dirname -- "${BASH_SOURCE[0]}")/platform-linux.sh"
    ;;
  *) die "unsupported platform: $(uname -s)" ;;
esac
