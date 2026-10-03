#!/usr/bin/env bash
# Status line segment: model, current directory, git branch, session tokens
# and cost. See ../../statusline/docs/statusline-segments.md for the segment contract.

input=$(cat)

# One jq call for every field, joined with the unit separator: unlike a tab
# (whitespace to `read`), it keeps empty fields from collapsing.
IFS=$'\x1f' read -r model dir input_tokens output_tokens cost_usd < <(
  printf '%s' "$input" | jq -r '[
    .model.display_name,
    .workspace.current_dir,
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.cost.total_cost_usd // "")
  ] | map(tostring) | join("\u001f")'
)
dir_name=$(basename "$dir")

# Git branch (skip optional locks so this stays fast/non-blocking). Empty
# outside a repo, so no separate "is this a repo" git call is needed.
git_branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)

# Tokens currently in the context window (input + output)
total_tokens=$((input_tokens + output_tokens))

if [ "$total_tokens" -ge 1000 ]; then
  tokens_display=$(awk -v t="$total_tokens" 'BEGIN{printf "%.1fk", t/1000}')
else
  tokens_display="${total_tokens}"
fi

# Session cost in USD, if Claude Code provides it in the input
if [ -n "$cost_usd" ]; then
  cost_display=$(awk -v c="$cost_usd" 'BEGIN{printf "$%.4f", c}')
else
  cost_display="n/a"
fi

DIM='\033[2m'
CYAN='\033[2;36m'
YELLOW='\033[2;33m'
GREEN='\033[2;32m'
RESET='\033[0m'

line="${CYAN}${model}${RESET} ${DIM}${dir_name}${RESET}"
if [ -n "$git_branch" ]; then
  line="${line} ${DIM}(${git_branch})${RESET}"
fi
line="${line} ${YELLOW}Tokens: ${tokens_display}${RESET} ${GREEN}Cost: ${cost_display}${RESET}"

printf "%b" "$line"
