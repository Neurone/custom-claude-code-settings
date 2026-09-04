#!/usr/bin/env bash
# Install or update "custom claude settings": copy every enabled customization
# into ~/.claude/customizations/custom-claude-code-settings, build the enforced
# settings file out of their fragments, and (re)load the launchd agent that
# keeps those keys in ~/.claude/settings.json.
#
# Idempotent: safe to re-run after editing or adding a customization.
set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

require_cmd jq "brew install jq"
require_cmd python3
require_cmd launchctl

names=()
while IFS= read -r name; do names+=("$name"); done < <(enabled_customizations)
[[ ${#names[@]} -gt 0 ]] || die "no enabled customizations found in $CUSTOMIZATIONS_SRC"

step "Installing into $INSTALL_DIR"
mkdir -p "$BIN_DIR" "$RESOURCES_DIR" "$LOG_DIR"

step "Installing the enforcement utility"
install -m 755 "$ENFORCEMENT_SRC/enforce-custom-claude-code-settings.py" "$ENFORCER"
info "$ENFORCER"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

step "Installing ${#names[@]} customization(s)"
fragments=()
for name in "${names[@]}"; do
  src="$CUSTOMIZATIONS_SRC/$name"
  info "$name"

  fragment="$work_dir/$name.json"
  render_placeholders "$src/customization.json" > "$fragment"
  jq empty "$fragment" 2>/dev/null || die "$name/customization.json is not valid JSON after rendering"
  [[ "$(jq -r 'type' "$fragment")" = "object" ]] || die "$name/customization.json must contain a JSON object"
  fragments+=("$fragment")

  if [[ -d "$src/bin" ]]; then
    for exe in "$src/bin"/*; do
      [[ -f "$exe" ]] || continue
      install -m 755 "$exe" "$BIN_DIR/$(basename "$exe")"
      info "  bin/$(basename "$exe")"
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
      info "  resources/$name/$(basename "$res")"
    done
  fi
done

step "Building $ENFORCED_PATH"
# jq's `*` deep-merges objects; fragments are applied in directory-name order.
jq -s 'reduce .[] as $fragment ({}; . * $fragment)' "${fragments[@]}" > "$work_dir/settings.enforced.json"
mv "$work_dir/settings.enforced.json" "$ENFORCED_PATH"
chmod 644 "$ENFORCED_PATH"
jq -r 'paths(scalars) | join(".")' "$ENFORCED_PATH" | sed 's/^/  /'

step "Enforcing once, before handing over to launchd"
"$ENFORCER"
info "settings.json now carries:"
jq '{statusLine, showClearContextOnPlanAccept}' "$SETTINGS_PATH" 2>/dev/null | sed 's/^/  /' || true

step "(Re)loading $LABEL"
mkdir -p "$LAUNCH_AGENTS_DIR"
launchctl bootout "$SERVICE" 2>/dev/null || true
render_placeholders "$ENFORCEMENT_SRC/launchagent.plist.template" > "$PLIST_PATH"
chmod 644 "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null || die "rendered plist is invalid: $PLIST_PATH"
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
launchctl enable "$SERVICE"
info "$PLIST_PATH"

step "Done"
info "status: scripts/status.sh"
info "logs:   scripts/logs.sh"
