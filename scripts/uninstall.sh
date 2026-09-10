#!/usr/bin/env bash
# Uninstall: unload the watchdog service, then actually strip the enforced
# keys back out of ~/.claude/settings.json (not just stop enforcing them).
#
# Usage: uninstall.sh [--keep-files] [name...]
# With no names, every customization is uninstalled: settings.json is
# cleaned up, the service is unloaded, and the install directory is removed
# (unless --keep-files, which only unloads the service).
# Naming one or more customizations removes only those: their keys are
# stripped from settings.json and their files deleted, but the service is
# reloaded afterwards to keep enforcing whatever customizations remain.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd jq "$PKG_INSTALL_HINT jq"
require_cmd python3
service_require_cmds

keep_files=false
names=()
for arg in "$@"; do
  if [[ "$arg" = "--keep-files" ]]; then
    keep_files=true
  else
    names+=("$arg")
  fi
done

if [[ ${#names[@]} -eq 0 ]]; then
  while IFS= read -r name; do names+=("$name"); done < <(all_customizations)
fi
[[ ${#names[@]} -gt 0 ]] || die "no customizations found in $CUSTOMIZATIONS_SRC"
for name in "${names[@]}"; do
  customization_exists "$name" || die "unknown customization: $name; available: $(available_customizations_line)"
done

# Whatever isn't being removed should keep being enforced.
remaining=()
while IFS= read -r name; do
  is_removed=false
  for removed in "${names[@]}"; do
    [[ "$name" = "$removed" ]] && is_removed=true && break
  done
  $is_removed || remaining+=("$name")
done < <(all_customizations)

# Only a definitive uninstall (nothing left to enforce) tears the service
# down; a partial uninstall reloads it once the remaining fragments are
# rebuilt below, and service_reload is safe to call whether or not the
# service is currently running.
if [[ ${#remaining[@]} -eq 0 ]]; then
  if service_unload; then
    ok "Unloaded $LABEL"
  else
    ok "$LABEL was not loaded"
  fi
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
build_settings_fragment "$work_dir/removed.json" "${names[@]}"

# A definitive uninstall (nothing left to enforce, $INSTALL_DIR itself gets
# removed below) would otherwise write the settings.json backup into
# $BACKUP_DIR just before deleting that same directory. Redirect it to
# $CLAUDE_DIR, which survives, instead.
remove_backup_dir="$BACKUP_DIR"
if [[ ${#remaining[@]} -eq 0 ]] && ! $keep_files; then
  remove_backup_dir="$CLAUDE_DIR"
fi
remove_output="$(CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR="$remove_backup_dir" python3 "$ENFORCEMENT_SRC/enforce-custom-claude-code-settings.py" --remove "$work_dir/removed.json")"
backup_suffix=""
if [[ "$remove_output" == *"backup saved to"* ]]; then
  backup_suffix=" (backup: $(basename "${remove_output#backup saved to }"))"
fi
ok "Removed config for $(join_by ", " "${names[@]}") from settings.json${backup_suffix}"

if [[ -d "$INSTALL_DIR" ]]; then
  removed_files=()
  for name in "${names[@]}"; do
    if [[ -d "$CUSTOMIZATIONS_SRC/$name/bin" ]]; then
      for exe in "$CUSTOMIZATIONS_SRC/$name/bin"/*; do
        [[ -f "$exe" ]] || continue
        rm -f "$BIN_DIR/$(basename "$exe")"
        removed_files+=("bin/$(basename "$exe")")
      done
    fi
    if [[ -d "$RESOURCES_DIR/$name" ]]; then
      rm -rf "${RESOURCES_DIR:?}/$name"
      removed_files+=("resources/$name")
    fi
  done
  removed_suffix=""
  [[ ${#removed_files[@]} -gt 0 ]] && removed_suffix=" ($(join_by ", " "${removed_files[@]}"))"
  ok "Removed installed files for $(join_by ", " "${names[@]}")${removed_suffix}"
fi

if [[ ${#remaining[@]} -eq 0 ]]; then
  if $keep_files; then
    ok "Kept $INSTALL_DIR (--keep-files)"
  elif [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed $INSTALL_DIR"
  else
    ok "Nothing to remove — $INSTALL_DIR was already gone"
  fi
elif [[ -d "$INSTALL_DIR" ]]; then
  build_settings_fragment "$work_dir/enforced.json" "${remaining[@]}"
  mv "$work_dir/enforced.json" "$ENFORCED_PATH"
  chmod 644 "$ENFORCED_PATH"
  ok "Rebuilt settings.enforced.json — still enforcing: $(join_by ", " "${remaining[@]}")"

  if service_reload; then
    ok "Reloaded $LABEL"
  else
    warn "service files missing, run scripts/install-or-update.sh to restore the watchdog"
  fi
else
  ok "Not installed — nothing to reload for: $(join_by ", " "${remaining[@]}")"
fi
