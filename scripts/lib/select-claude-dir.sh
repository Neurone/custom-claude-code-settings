#!/usr/bin/env bash
# Decides which Claude Code config dir(s) the calling script manages. Source it
# *before* common.sh, which derives every path (and the service label) from
# CLAUDE_DIR.
#
#   - CLAUDE_DIR or CLAUDE_CONFIG_DIR already set: that dir only, no question.
#   - otherwise, every config dir that exists among ~/.claude and secure-ai's
#     ~/.secure-ai/claude-code/config. With several, the calling script is re-run
#     once per dir with the same arguments, then this one exits.
#   - none exists: ~/.claude, except when the caller sets ASK_CLAUDE_DIR=1 (only
#     the installer does, as nothing else has anything to act on in a dir that
#     doesn't exist yet) and stdin is a terminal: then it asks, default ~/.claude.

# shellcheck source=SCRIPTDIR/secure-ai.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/secure-ai.sh"

if [[ -z "${CLAUDE_DIR:-}" && -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  existing_claude_dirs=()
  for candidate_claude_dir in "$HOME/.claude" "$SECURE_AI_CLAUDE_CONFIG_DIR"; do
    [[ -d "$candidate_claude_dir" ]] && existing_claude_dirs+=("$candidate_claude_dir")
  done

  if [[ ${#existing_claude_dirs[@]} -gt 1 ]]; then
    multi_dir_status=0
    # `bash status.sh` from inside scripts/ leaves BASH_SOURCE[1] without a
    # slash, which would be looked up in PATH instead of run from here.
    calling_script="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)/$(basename -- "${BASH_SOURCE[1]}")"
    for candidate_claude_dir in "${existing_claude_dirs[@]}"; do
      printf '= Config dir: %s\n' "$candidate_claude_dir" >&2
      CLAUDE_DIR="$candidate_claude_dir" "$calling_script" "$@" || multi_dir_status=1
    done
    exit "$multi_dir_status"
  elif [[ ${#existing_claude_dirs[@]} -eq 1 ]]; then
    export CLAUDE_DIR="${existing_claude_dirs[0]}"
  elif [[ "${ASK_CLAUDE_DIR:-}" == 1 && -t 0 ]]; then
    read -r -p "Claude Code config dir [~/.claude]: " selected_claude_dir ||
      { printf 'error: no config dir given\n' >&2; exit 1; }
    selected_claude_dir="${selected_claude_dir:-$HOME/.claude}"
    case "$selected_claude_dir" in
      \~) selected_claude_dir="$HOME" ;;
      \~/*) selected_claude_dir="$HOME/${selected_claude_dir#\~/}" ;;
    esac
    [[ "$selected_claude_dir" == /* ]] ||
      { printf 'error: the config dir must be an absolute path: %s\n' "$selected_claude_dir" >&2; exit 1; }
    export CLAUDE_DIR="$selected_claude_dir"
    unset selected_claude_dir
  fi
  unset existing_claude_dirs candidate_claude_dir multi_dir_status
fi
