# statusline

Replaces the default Claude Code status line with a compact one showing:
model, current directory, git branch, context-window tokens and session cost.

- `bin/statusline-command.sh` — the status line command (needs `jq`, `awk`, `git`)
- `customization.json` — the `statusLine` settings fragment

## Customizing

Edit `bin/statusline-command.sh` and re-run `scripts/install-or-update.sh`.
The script receives the Claude Code status payload on stdin as JSON; run
`echo '{}' | ./bin/statusline-command.sh` for a quick smoke test.
