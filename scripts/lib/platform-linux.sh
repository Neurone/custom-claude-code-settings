#!/usr/bin/env bash
# systemd --user backend for the service_* contract defined in common.sh.
# Source, don't run.
#
# systemd --user is unavailable in most containers (a primary environment for
# this repo): the systemctl binary can be installed with no user manager
# actually running. Every entry point degrades gracefully instead of dying —
# service_install returns 2, service_reload/service_unload/service_status
# return non-zero with a message — so install-or-update.sh, uninstall.sh and
# status.sh can all still do their settings.json work.

# shellcheck disable=SC2034  # used by install-or-update.sh/uninstall.sh
PKG_INSTALL_HINT="apt install"

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_UNIT="$UNIT_DIR/$LABEL.service"
PATH_UNIT="$UNIT_DIR/$LABEL.path"
TIMER_UNIT="$UNIT_DIR/$LABEL.timer"

service_require_cmds() {
  return 0
}

service_files() {
  printf '%s\n' "$SERVICE_UNIT" "$PATH_UNIT" "$TIMER_UNIT"
}

# Must not false-positive when the systemctl binary exists but no user
# manager does (the container case): check the socket cheaply before making
# an authoritative (but potentially slow) call to the manager itself.
_systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 || return 1
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  [[ -S "$runtime_dir/systemd/private" ]] || return 1
  systemctl --user show --property=Version >/dev/null 2>&1
}

# Render the three units, load them, and start them. Idempotent on re-run:
# `restart` (not `enable --now`) so unit content changes actually take effect
# even when the units are already active.
service_install() {
  mkdir -p "$UNIT_DIR"
  render_placeholders "$ENFORCEMENT_SRC/systemd/enforce.service.template" >"$SERVICE_UNIT"
  render_placeholders "$ENFORCEMENT_SRC/systemd/enforce.path.template" >"$PATH_UNIT"
  render_placeholders "$ENFORCEMENT_SRC/systemd/enforce.timer.template" >"$TIMER_UNIT"
  chmod 644 "$SERVICE_UNIT" "$PATH_UNIT" "$TIMER_UNIT"

  _systemd_user_available || return 2

  systemctl --user daemon-reload

  local version
  version="$(systemctl --user --version | awk 'NR==1{print $2}')"
  if [[ "$version" =~ ^[0-9]+$ ]] && ((version < 240)); then
    warn "systemd $version detected (older than 240): StandardOutput=append: is dropped on unit load, so enforce.out.log/enforce.err.log will never appear (scripts/logs.sh already tolerates missing logs)"
  fi

  [[ "$(systemctl --user show "$LABEL.path" --value -p LoadState)" = "loaded" ]] \
    || die "rendered unit failed to load: $PATH_UNIT"

  systemctl --user enable "$LABEL.path" "$LABEL.timer" >/dev/null
  systemctl --user reset-failed "$LABEL.service" "$LABEL.path" "$LABEL.timer" >/dev/null 2>&1 || true
  systemctl --user restart "$LABEL.path" "$LABEL.timer"
  systemctl --user start "$LABEL.service"
  return 0
}

service_reload() {
  local f
  for f in "$SERVICE_UNIT" "$PATH_UNIT" "$TIMER_UNIT"; do
    [[ -f "$f" ]] || return 1
  done
  _systemd_user_available || return 1
  systemctl --user daemon-reload
  systemctl --user restart "$LABEL.path" "$LABEL.timer"
  systemctl --user start "$LABEL.service"
  return 0
}

service_unload() {
  local was_active=1
  if _systemd_user_available && [[ -f "$PATH_UNIT" ]]; then
    systemctl --user is-active --quiet "$LABEL.path" && was_active=0
  fi
  if _systemd_user_available; then
    systemctl --user disable --now "$LABEL.path" "$LABEL.timer" >/dev/null 2>&1 || true
    systemctl --user stop "$LABEL.service" >/dev/null 2>&1 || true
  fi
  rm -f "$SERVICE_UNIT" "$PATH_UNIT" "$TIMER_UNIT"
  if _systemd_user_available; then
    systemctl --user daemon-reload
    systemctl --user reset-failed >/dev/null 2>&1 || true
  fi
  return "$was_active"
}

service_status() {
  if ! _systemd_user_available; then
    printf 'systemd --user manager not available: %s\n' "$LABEL"
    return 2
  fi
  if [[ ! -f "$PATH_UNIT" ]]; then
    printf 'systemd units not installed: %s\n' "$LABEL"
    return 1
  fi
  local active sub load unitfile result exit_status start_ts
  active="$(systemctl --user show "$LABEL.path" --value -p ActiveState)"
  sub="$(systemctl --user show "$LABEL.path" --value -p SubState)"
  load="$(systemctl --user show "$LABEL.path" --value -p LoadState)"
  unitfile="$(systemctl --user show "$LABEL.path" --value -p UnitFileState)"
  result="$(systemctl --user show "$LABEL.service" --value -p Result)"
  exit_status="$(systemctl --user show "$LABEL.service" --value -p ExecMainStatus)"
  start_ts="$(systemctl --user show "$LABEL.service" --value -p ExecMainStartTimestamp)"
  if [[ "$active" = "active" && "$load" = "loaded" ]]; then
    printf 'systemd watchdog loaded: %s (state: %s/%s, unit-file: %s, last run: %s, result: %s, exit: %s)\n' \
      "$LABEL" "$active" "$sub" "$unitfile" "${start_ts:-n/a}" "${result:-n/a}" "${exit_status:-n/a}"
    return 0
  fi
  printf 'systemd watchdog not active: %s (state: %s/%s)\n' "$LABEL" "$active" "$sub"
  return 1
}
