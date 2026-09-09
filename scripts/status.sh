#!/usr/bin/env bash
# Report what is installed, whether the agent is loaded, and whether
# ~/.claude/settings.json currently matches the enforced customizations.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

names=()
while IFS= read -r name; do names+=("$name"); done < <(all_customizations)
ok "Customizations in repo: $(join_by ", " "${names[@]}")"

if [[ -d "$INSTALL_DIR" ]]; then
  counts=()
  for sub in bin resources logs backups; do
    dir="$INSTALL_DIR/$sub"
    [[ -d "$dir" ]] || continue
    count="$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    [[ "$count" -gt 0 ]] && counts+=("$sub: $count")
  done
  suffix=""
  [[ ${#counts[@]} -gt 0 ]] && suffix=" ($(join_by ", " "${counts[@]}"))"
  ok "Installed into $INSTALL_DIR${suffix}"
else
  warn "not installed — run scripts/install-or-update.sh"
fi

if service_loaded; then
  launchd_info="$(launchctl print "$SERVICE")"
  agent_state="$(awk -F' = ' '/^\tstate = /{print $2; exit}' <<<"$launchd_info")"
  exit_code="$(awk -F' = ' '/^\tlast exit code = /{print $2; exit}' <<<"$launchd_info")"
  ok "launchd agent loaded: $LABEL (state: ${agent_state:-unknown}, exit: ${exit_code:-n/a})"
else
  warn "launchd agent not loaded: $LABEL"
fi
[[ -f "$PLIST_PATH" ]] || warn "plist missing: $PLIST_PATH"

if [[ -x "$ENFORCER" ]]; then
  if drift_output="$("$ENFORCER" --check)"; then
    ok "$drift_output"
  else
    warn "$drift_output"
  fi
else
  warn "enforcer not installed"
fi
