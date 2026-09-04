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
