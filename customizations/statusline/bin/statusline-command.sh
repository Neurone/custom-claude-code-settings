#!/bin/bash
# Claude Code status line: model, cwd, git branch, session tokens and cost.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
dir=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$dir")

# Git branch (skip optional locks so this stays fast/non-blocking)
git_branch=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
fi

# Tokens currently in the context window (input + output)
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
total_tokens=$((input_tokens + output_tokens))

if [ "$total_tokens" -ge 1000 ]; then
  tokens_display=$(awk -v t="$total_tokens" 'BEGIN{printf "%.1fk", t/1000}')
else
  tokens_display="${total_tokens}"
fi

# Session cost in USD, if Claude Code provides it in the input
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
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
