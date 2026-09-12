#!/usr/bin/env bash
# Report what is installed, whether the agent is loaded, and whether
# ~/.claude/settings.json currently matches the enforced customizations.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

CHECK=$'\xe2\x9c\x93'
CROSS=$'\xe2\x9c\x97'
DASH='-'

printf 'Available customizations (%s installed %s not installed):\n\n' "${C_GREEN}${CHECK}${C_RESET}" "${C_RED}${CROSS}${C_RESET}"

names=()
while IFS= read -r name; do names+=("$name"); done < <(all_customizations)

installed=()
while IFS= read -r name; do installed+=("$name"); done < <(installed_customizations)

# Validate the whole dependency graph in one shot; die()'s exit only ends
# this command substitution's subshell, so a bad graph becomes a warning here
# instead of aborting status.sh.
if [[ ${#names[@]} -gt 0 ]] && ! graph_error="$(resolve_dependencies "${names[@]}" 2>&1 >/dev/null)"; then
  warn "dependency graph problem: $graph_error"
fi

name_width=0
needs_width=0
rows=()
for name in "${names[@]}"; do
  requires=()
  while IFS= read -r dep; do [[ -n "$dep" ]] && requires+=("$dep"); done < <(customization_requires "$name" 2>/dev/null)
  if [[ ${#requires[@]} -eq 0 ]]; then
    needs="$DASH"
  else
    needs="needs $(join_by ", " "${requires[@]}")"
  fi
  desc="$(customization_description "$name" 2>/dev/null)"
  rows+=("$name"$'\x1f'"$needs"$'\x1f'"$desc")
  [[ ${#name} -gt $name_width ]] && name_width=${#name}
  [[ ${#needs} -gt $needs_width ]] && needs_width=${#needs}
done

# printf's %-*s pads by byte count, not character count, so a multi-byte
# UTF-8 character (CHECK/CROSS are, but those are never padded, only ever
# printed as-is) would misalign columns; ${#str} is itself byte-based under
# a non-UTF-8 locale (the C/POSIX default of many containers), so every
# padded field (name, needs, DASH) is kept plain ASCII rather than trusting
# either to count multi-byte characters correctly.
pad_field() {
  local str="$1" width="$2" pad
  pad=$((width - ${#str}))
  ((pad < 0)) && pad=0
  printf '%s%*s' "$str" "$pad" ""
}

for row in "${rows[@]+"${rows[@]}"}"; do
  IFS=$'\x1f' read -r row_name row_needs row_desc <<<"$row"
  if list_contains "$row_name" "${installed[@]+"${installed[@]}"}"; then
    mark="${C_GREEN}${CHECK}${C_RESET}"
  else
    mark="${C_RED}${CROSS}${C_RESET}"
  fi
  printf '  %s %s   %s   %s\n' "$mark" "$(pad_field "$row_name" "$name_width")" "$(pad_field "$row_needs" "$needs_width")" "$row_desc"
done
printf '\n'

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
