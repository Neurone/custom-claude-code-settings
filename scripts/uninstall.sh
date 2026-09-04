#!/usr/bin/env bash
# Stop enforcing: unload the launchd agent and remove the install directory.
#
# The keys already written into ~/.claude/settings.json are left alone — they
# simply stop being restored when Claude Code drops them. Pass --keep-files to
# only unload the agent.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

keep_files=false
[[ "${1:-}" = "--keep-files" ]] && keep_files=true

step "Unloading $LABEL"
if launchctl bootout "$SERVICE" 2>/dev/null; then
  info "booted out"
else
  info "was not loaded"
fi
if [[ -f "$PLIST_PATH" ]]; then
  rm -f "$PLIST_PATH"
  info "removed $PLIST_PATH"
fi

if $keep_files; then
  step "Keeping $INSTALL_DIR (--keep-files)"
else
  step "Removing $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    info "removed"
  else
    info "nothing to remove"
  fi
fi

step "Done"
info "settings.json was not modified; the statusLine command it points at is gone,"
info "so clear that key with /config if you are not reinstalling."
