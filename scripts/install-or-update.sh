#!/usr/bin/env bash
# Install or update "custom claude settings": copy the selected customizations
# into ~/.claude/customizations/custom-claude-code-settings, build the enforced
# settings file out of their fragments, and (re)load the watchdog service that
# keeps those keys in ~/.claude/settings.json.
#
# Usage: install-or-update.sh [name...]
# With no names, every customization is installed. Naming one or more
# customizations installs those plus their dependencies (customization.meta.json
# "requires"), added to whatever is already installed — it's a union, not a
# replacement. Use uninstall.sh to shrink the installed set.
#
# Idempotent: safe to re-run after editing or adding a customization.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd jq "$PKG_INSTALL_HINT jq"
require_cmd python3
service_require_cmds

requested=()
if [[ $# -gt 0 ]]; then
  for name in "$@"; do
    customization_exists "$name" || die "unknown customization: $name; available: $(available_customizations_line)"
    requested+=("$name")
  done
else
  while IFS= read -r name; do requested+=("$name"); done < <(all_customizations)
fi
[[ ${#requested[@]} -gt 0 ]] || die "no customizations found in $CUSTOMIZATIONS_SRC"

names=()
while IFS= read -r name; do names+=("$name"); done < <(resolve_dependencies "${requested[@]}")
if [[ $# -gt 0 ]]; then
  for name in "${names[@]}"; do
    list_contains "$name" "${requested[@]}" || info "pulled in dependency: $name"
  done
fi

previously_installed=()
while IFS= read -r name; do previously_installed+=("$name"); done < <(installed_customizations)
union_names=("${names[@]}")
for name in "${previously_installed[@]+"${previously_installed[@]}"}"; do
  list_contains "$name" "${union_names[@]}" || union_names+=("$name")
done
final_names=()
while IFS= read -r name; do final_names+=("$name"); done < <(resolve_dependencies "${union_names[@]}")
names=("${final_names[@]}")

mkdir -p "$BIN_DIR" "$RESOURCES_DIR" "$LOG_DIR" "$BACKUP_DIR" "$CACHE_DIR"
ok "Installed into $INSTALL_DIR"

install -m 755 "$ENFORCEMENT_SRC/enforce-custom-claude-code-settings.py" "$ENFORCER"
ok "Enforcement utility installed"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fragments=()
extra_files=()
for name in "${names[@]}"; do
  src="$CUSTOMIZATIONS_SRC/$name"

  fragment="$work_dir/$name.json"
  render_customization_fragment "$name" "$fragment"
  fragments+=("$fragment")

  if [[ -d "$src/bin" ]]; then
    for exe in "$src/bin"/*; do
      [[ -f "$exe" ]] || continue
      install -m 755 "$exe" "$BIN_DIR/$(basename "$exe")"
      extra_files+=("bin/$(basename "$exe")")
    done
  fi

  if [[ -d "$src/resources" ]]; then
    dest="$RESOURCES_DIR/$name"
    rm -rf "$dest"
    mkdir -p "$dest"
    for res in "$src/resources"/*; do
      [[ -e "$res" ]] || continue
      if [[ -d "$res" ]]; then
        cp -R "$res" "$dest/"
      else
        render_placeholders "$res" > "$dest/$(basename "$res")"
      fi
      extra_files+=("resources/$name/$(basename "$res")")
    done
  fi

  mkdir -p "$LOG_DIR/$name" "$CACHE_DIR/$name"
done
extra_suffix=""
[[ ${#extra_files[@]} -gt 0 ]] && extra_suffix=" (+$(join_by ", " "${extra_files[@]}"))"
ok "Customizations installed: $(join_by ", " "${names[@]}")${extra_suffix}"

write_install_manifest "${names[@]}"
ok "Wrote install manifest ($INSTALL_MANIFEST)"

# Fragments are applied in topological order (dependencies first), so a
# customization can override keys of what it requires.
merge_fragments "$work_dir/settings.enforced.json" "${fragments[@]}"
mv "$work_dir/settings.enforced.json" "$ENFORCED_PATH"
chmod 644 "$ENFORCED_PATH"
enforced_keys=()
while IFS= read -r key; do enforced_keys+=("$key"); done < <(jq -r 'paths(scalars) | join(".")' "$ENFORCED_PATH")
ok "Built settings.enforced.json (${#enforced_keys[@]} keys: $(join_by ", " "${enforced_keys[@]}"))"

enforcer_output="$("$ENFORCER")"
backup_suffix=""
if [[ "$enforcer_output" == *"backup saved to"* ]]; then
  backup_suffix=" (backup: $(basename "${enforcer_output#backup saved to }"))"
fi
ok "Enforced settings.json${backup_suffix}"

if service_install; then
  ok "Reloaded $LABEL"
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    warn "no user service manager available — the watchdog is not running; re-apply manually with scripts/enforce-now.sh"
  else
    die "failed to install the watchdog service (exit $rc)"
  fi
fi

printf '\n%sStatus:%s scripts/status.sh   %sLogs:%s scripts/logs.sh\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
