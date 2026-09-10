#!/usr/bin/env bash
# launchd backend for the service_* contract defined in common.sh. Source, don't run.

# shellcheck disable=SC2034  # used by install-or-update.sh/uninstall.sh
PKG_INSTALL_HINT="brew install"

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

service_require_cmds() {
  require_cmd launchctl
  require_cmd plutil
}

service_files() {
  printf '%s\n' "$PLIST_PATH"
}

_launchd_loaded() {
  launchctl print "$SERVICE" >/dev/null 2>&1
}

# Render the plist, validate it, and (re)load it into launchd. launchd is
# always available once launchctl exists (service_require_cmds already
# checked), so this backend never returns 2.
service_install() {
  mkdir -p "$LAUNCH_AGENTS_DIR"
  launchctl bootout "$SERVICE" 2>/dev/null || true
  render_placeholders "$ENFORCEMENT_SRC/launchd/launchagent.plist.template" >"$PLIST_PATH"
  chmod 644 "$PLIST_PATH"
  plutil -lint "$PLIST_PATH" >/dev/null || die "rendered plist is invalid: $PLIST_PATH"
  launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
  launchctl enable "$SERVICE"
  return 0
}

# Safe to call whether or not the agent is currently loaded: bootstrapping an
# already-loaded service is an error, so always bootout first (idempotent).
service_reload() {
  [[ -f "$PLIST_PATH" ]] || return 1
  launchctl bootout "$SERVICE" 2>/dev/null || true
  launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
  launchctl enable "$SERVICE"
  return 0
}

service_unload() {
  local rc=1
  launchctl bootout "$SERVICE" 2>/dev/null && rc=0
  rm -f "$PLIST_PATH"
  return "$rc"
}

service_status() {
  if _launchd_loaded; then
    local launchd_info agent_state exit_code
    launchd_info="$(launchctl print "$SERVICE")"
    agent_state="$(awk -F' = ' '/^\tstate = /{print $2; exit}' <<<"$launchd_info")"
    exit_code="$(awk -F' = ' '/^\tlast exit code = /{print $2; exit}' <<<"$launchd_info")"
    printf 'launchd agent loaded: %s (state: %s, exit: %s)\n' "$LABEL" "${agent_state:-unknown}" "${exit_code:-n/a}"
    return 0
  fi
  printf 'launchd agent not loaded: %s\n' "$LABEL"
  return 1
}
