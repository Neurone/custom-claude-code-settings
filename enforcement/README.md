# Enforcement utility

Claude Code owns `~/.claude/settings.json` and rewrites it periodically, which
can silently drop customized keys. This utility is the watchdog that puts them
back — it is *not* where customizations are defined (see `../customizations/`).

- `enforce-custom-claude-code-settings.py` — deep-merges the built
  `resources/settings.enforced.json` into `~/.claude/settings.json`, writing
  only when the result actually differs. `--check` reports drift without
  writing.
- `launchagent.plist.template` — the launchd agent that runs it: on
  `settings.json` / `settings.enforced.json` changes (`WatchPaths`), every 5
  minutes as a safety net, and at load.

Only enforced keys are touched; anything else in `settings.json` is preserved.
If `settings.json` is unparseable it is copied to `settings.json.broken-<ts>`
before being rebuilt, so nothing is lost.

It writes what it restored to `<install>/logs/enforce.log` (self-trimmed at
256 KB); launchd sends the agent's stdout/stderr to `enforce.out.log` and
`enforce.err.log` in the same directory. `scripts/logs.sh` reads all three.

Paths default to the install directory the script sits in and can be overridden
with `CUSTOM_CLAUDE_SETTINGS_TARGET`, `CUSTOM_CLAUDE_SETTINGS_ENFORCED` and
`CUSTOM_CLAUDE_SETTINGS_LOG`.
