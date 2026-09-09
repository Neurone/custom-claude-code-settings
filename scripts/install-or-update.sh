#!/usr/bin/env bash
# Install or update "custom claude settings": copy the selected customizations
# into ~/.claude/customizations/custom-claude-code-settings, build the enforced
# settings file out of their fragments, and (re)load the launchd agent that
# keeps those keys in ~/.claude/settings.json.
#
# Usage: install-or-update.sh [name...]
# With no names, every customization is installed. Naming one or more
# customizations installs only those.
#
# Idempotent: safe to re-run after editing or adding a customization.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd jq "brew install jq"
require_cmd python3
require_cmd launchctl

names=()
if [[ $# -gt 0 ]]; then
  for name in "$@"; do
    customization_exists "$name" || die "unknown customization: $name; available: $(available_customizations_line)"
    names+=("$name")
  done
else
  while IFS= read -r name; do names+=("$name"); done < <(all_customizations)
fi
[[ ${#names[@]} -gt 0 ]] || die "no customizations found in $CUSTOMIZATIONS_SRC"

mkdir -p "$BIN_DIR" "$RESOURCES_DIR" "$LOG_DIR" "$BACKUP_DIR"
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
  render_placeholders "$src/customization.json" > "$fragment"
  jq empty "$fragment" 2>/dev/null || die "$name/customization.json is not valid JSON after rendering"
  [[ "$(jq -r 'type' "$fragment")" = "object" ]] || die "$name/customization.json must contain a JSON object"
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
done
extra_suffix=""
[[ ${#extra_files[@]} -gt 0 ]] && extra_suffix=" (+$(join_by ", " "${extra_files[@]}"))"
ok "Customizations installed: $(join_by ", " "${names[@]}")${extra_suffix}"

# jq's `*` deep-merges objects; fragments are applied in directory-name order.
jq -s 'reduce .[] as $fragment ({}; . * $fragment)' "${fragments[@]}" > "$work_dir/settings.enforced.json"
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

mkdir -p "$LAUNCH_AGENTS_DIR"
launchctl bootout "$SERVICE" 2>/dev/null || true
render_placeholders "$ENFORCEMENT_SRC/launchagent.plist.template" > "$PLIST_PATH"
chmod 644 "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null || die "rendered plist is invalid: $PLIST_PATH"
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
launchctl enable "$SERVICE"
ok "Reloaded $LABEL"

printf '\n%sStatus:%s scripts/status.sh   %sLogs:%s scripts/logs.sh\n' "$C_BOLD" "$C_RESET" "$C_BOLD" "$C_RESET"
