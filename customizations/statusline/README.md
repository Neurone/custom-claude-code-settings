# statusline

Replaces the default Claude Code status line with a compact one showing:
model, current directory, git branch, context-window tokens and session cost.

![The status line in Claude Code](../../docs/resources/statusline-example.png)

- `bin/statusline-command.sh` — the status line command (needs `jq`, `awk`, `git`)
- `customization.json` — the `statusLine` settings fragment

## Customizing

Edit `bin/statusline-command.sh` and re-run `scripts/install-or-update.sh`.
The script receives the Claude Code status payload on stdin as JSON and prints
one line (no trailing newline). It reads `.model.display_name`,
`.workspace.current_dir`, `.context_window.total_input_tokens`,
`.context_window.total_output_tokens` and `.cost.total_cost_usd`, and takes the
git branch from `current_dir`. Missing fields degrade instead of failing
(`null`, `0`, `n/a`), so a smoke test is easiest with a realistic payload:

```bash
echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},
       "context_window":{"total_input_tokens":12000,"total_output_tokens":800},
       "cost":{"total_cost_usd":0.1234}}' | ./bin/statusline-command.sh
```
