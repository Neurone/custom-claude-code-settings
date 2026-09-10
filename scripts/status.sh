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

if status_line="$(service_status)"; then
  ok "$status_line"
else
  warn "$status_line"
fi
while IFS= read -r service_file; do
  [[ -f "$service_file" ]] || warn "service file missing: $service_file"
done < <(service_files)

if [[ -x "$ENFORCER" ]]; then
  if drift_output="$("$ENFORCER" --check)"; then
    ok "$drift_output"
  else
    warn "$drift_output"
  fi
else
  warn "enforcer not installed"
fi
