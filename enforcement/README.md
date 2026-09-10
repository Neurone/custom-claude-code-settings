# Enforcement utility

Claude Code owns `~/.claude/settings.json` and rewrites it periodically, which
can silently drop customized keys. This utility is the watchdog that puts them
back — it is *not* where customizations are defined (see `../customizations/`).

- `enforce-custom-claude-code-settings.py` — deep-merges the built
  `resources/settings.enforced.json` into `~/.claude/settings.json`, writing
  only when the result actually differs. `--check` reports drift without
  writing. `--remove FRAGMENT` does the opposite: it strips FRAGMENT's keys
  back out of `settings.json` (used by `scripts/uninstall.sh`).
- `launchd/launchagent.plist.template` — the launchd agent that runs it, on
  macOS: on `settings.json` / `settings.enforced.json` changes (`WatchPaths`),
  every 5 minutes as a safety net, and at load.
- `systemd/enforce.{service,path,timer}.template` — the equivalent
  `systemd --user` units, on Linux: `enforce.path` watches `settings.json`
  (`PathModified`) and `settings.enforced.json` (`PathChanged`) and triggers
  `enforce.service`; `enforce.timer` re-runs it every 5 minutes as a safety
  net, 30s after each user-manager startup.

## Linux without a `systemd --user` manager

Many containers ship the `systemctl` binary with no user manager actually
running — exactly the case `scripts/install-or-update.sh` detects and
degrades from: it still installs the customizations and runs the enforcer
once, it just prints a warning instead of a watchdog. Re-run
`scripts/enforce-now.sh` (or wire your own cron/supervisor) to reapply after
that.

On a real (non-container) headless Linux box, a user's systemd instance
normally stops when their last session ends. Run
`loginctl enable-linger "$USER"` once (as that user or root) to keep it — and
this watchdog — running without a login session.

Only enforced keys are touched; anything else in `settings.json` is preserved.
Before any write, the current `settings.json` is copied to
`<install>/backups/settings.json.bak-<ts>` (or
`<install>/backups/settings.json.broken-<ts>` if it was unparseable) so
nothing is lost; the backup path is printed and logged.

It writes what it restored to `<install>/logs/enforce.log` (self-trimmed at
256 KB); the watchdog sends its stdout/stderr to `enforce.out.log` and
`enforce.err.log` in the same directory (systemd < 240 drops that directive
silently, so those two just never appear — see below). `scripts/logs.sh`
reads all three.

Paths default to the install directory the script sits in and can be overridden
with `CUSTOM_CLAUDE_SETTINGS_TARGET`, `CUSTOM_CLAUDE_SETTINGS_ENFORCED`,
`CUSTOM_CLAUDE_SETTINGS_LOG` and `CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR`.
