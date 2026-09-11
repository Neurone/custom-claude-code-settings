# Custom Claude Code Settings

Customize Claude Code settings — status line first — and keep those customizations from
being silently dropped.

![The status line in Claude Code](docs/resources/statusline-example.png)

Claude Code owns `~/.claude/settings.json` and rewrites it on its own; keys you
add by hand can disappear. So this repo has two halves:

- **customizations** (`customizations/`) — what you want Claude Code to look
  like. Each one is a directory with a settings fragment plus any executables
  and resources it needs.
- **enforcement** (`enforcement/`) — a small watchdog (`launchd` on macOS,
  `systemd X--user` on Linux) that deep-merges those fragments (combined at
  install time into a single `settings.enforced.json`) back into
  `settings.json` whenever it drifts. A utility, not the point.

## Install

```bash
scripts/install-or-update.sh              # every customization
scripts/install-or-update.sh statusline   # only the named customization(s)
```

Requires `jq`, `python3`, and macOS or Linux. On Linux, if no `systemd --user`
manager is available (common in containers — one of this repo's primary
environments), the customizations are still installed and enforced once;
you just don't get the always-on watchdog. See `enforcement/README.md` for
what that degradation looks like and how to keep a user manager alive on a
headless box. Re-run the installer after editing or adding a customization.

## Day to day

```bash
scripts/status.sh          # installed? watchdog loaded? settings drifted?
scripts/logs.sh -f         # watch the watchdog
scripts/enforce-now.sh     # re-apply right now
scripts/uninstall.sh       # stop enforcing everything and undo it in settings.json
scripts/uninstall.sh statusline  # undo only the named customization(s)
```

## Adding a customization

```bash
mkdir -p customizations/my-thing
cat > customizations/my-thing/customization.json <<'JSON'
{ "someSetting": true }
JSON
scripts/install-or-update.sh
```

Executables go in `customizations/my-thing/bin/` and are referenced from the
fragment as `@@BIN_DIR@@/<file>`; see `customizations/README.md` for the full
list of placeholders.

## How enforcement behaves

- Only enforced keys are touched — everything else in `settings.json` is kept.
- The file is rewritten only when the merge result actually differs, and always
  atomically (temp file + rename).
- An unparseable (or non-object) `settings.json` is never rewritten: it's left
  exactly as-is, a copy is saved to
  `<install-dir>/backups/settings.json.broken-<timestamp>` for forensics, and
  the reason is logged.
- Triggers: on `settings.json` or `settings.enforced.json` changing on disk
  (`WatchPaths` on launchd, a `.path` unit on systemd), at load/start, plus a
  5-minute safety net.

## Caveat

Managed (enterprise) settings win over user settings, so a key pinned by a
managed policy cannot be overridden here — the enforcer will keep writing it
and Claude Code will keep ignoring it.
