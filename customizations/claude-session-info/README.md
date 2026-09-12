# Claude Session Info

A `statusline` segment (see
[`docs/statusline-segments.md`](../statusline/docs/statusline-segments.md)) showing:
model, current directory, git branch, context-window tokens and session cost.

![The status line in Claude Code](../statusline/docs/resources/statusline-example.png)

- `bin/claude-session-info-segment.sh` — the segment (needs `jq`, `awk`, `git`)
- `resources/statusline-segment.json` — declares `order: 10` to the host
- `customization.json` — `{}`; this customization contributes no settings of
  its own, only a segment
- `customization.meta.json` — `requires: ["statusline"]`

## Customizing

Edit `bin/claude-session-info-segment.sh` and re-run
`scripts/install-or-update.sh`. The script receives the Claude Code status
payload on stdin as JSON and prints one line (no trailing newline). It reads
`.model.display_name`, `.workspace.current_dir`,
`.context_window.total_input_tokens`, `.context_window.total_output_tokens`
and `.cost.total_cost_usd`, and takes the git branch from `current_dir`.
Missing fields degrade instead of failing (`null`, `0`, `n/a`), so a smoke
test is easiest with a realistic payload:

```bash
echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},
       "context_window":{"total_input_tokens":12000,"total_output_tokens":800},
       "cost":{"total_cost_usd":0.1234}}' | ./bin/claude-session-info-segment.sh
```
