#!/usr/bin/env bash
# Report what is installed, whether the agent is loaded, and whether
# ~/.claude/settings.json currently matches the enforced customizations.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

step "Customizations in the repo"
while IFS= read -r name; do info "enabled  $name"; done < <(enabled_customizations)
for dir in "$CUSTOMIZATIONS_SRC"/*/; do
  [[ -f "$dir/.disabled" ]] && info "disabled $(basename "$dir")"
done

step "Installed files"
if [[ -d "$INSTALL_DIR" ]]; then
  info "$INSTALL_DIR"
  find "$INSTALL_DIR" -mindepth 1 -maxdepth 2 -print | sed "s|^$INSTALL_DIR/|  |" | sort
else
  info "not installed — run scripts/install-or-update.sh"
fi

step "launchd agent ($LABEL)"
if service_loaded; then
  launchctl print "$SERVICE" | awk '
    /^[[:space:]]*state =/ || /last exit code/ || /^[[:space:]]*pid =/ {print "  " $0}'
else
  info "not loaded"
fi
if [[ -f "$PLIST_PATH" ]]; then
  info "plist: $PLIST_PATH"
else
  info "plist: missing"
fi

step "Drift check"
if [[ -x "$ENFORCER" ]]; then
  "$ENFORCER" --check | sed 's/^/  /'
else
  info "enforcer not installed"
fi
