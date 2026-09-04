# Custom Claude Code Settings

Customize Claude Code settings — status line first — and keep those customizations from
being silently dropped.

Claude Code owns `~/.claude/settings.json` and rewrites it on its own; keys you
add by hand can disappear. So this repo has two halves:

- **customizations** (`customizations/`) — what you want Claude Code to look
  like. Each one is a directory with a settings fragment plus any executables
  and resources it needs.
- **enforcement** (`enforcement/`) — a small launchd-driven watchdog that
  deep-merges those fragments back into `settings.json` whenever it drifts. A
  utility, not the point.

## Install

```bash
scripts/install-or-update.sh
```

Requires `jq`, `python3` and macOS (`launchctl`). Re-run it after editing or
adding a customization.

## Layout

```text
customizations/                               what to customize
  statusline/                                 model · dir · branch · tokens · cost
    customization.json                        settings fragment
    bin/statusline-command.sh
  clear-context-on-plan-accept/               settings-only customization
enforcement/                                  the watchdog utility
  enforce-custom-claude-code-settings.py
  launchagent.plist.template
scripts/                                      install / update / maintenance
  install-or-update.sh
  status.sh
  enforce-now.sh
  logs.sh
  uninstall.sh
  lib/common.sh
```

Installed side, all under one ad-hoc directory:

```text
~/.claude/customizations/custom-claude-code-settings/
  bin/         enforce-custom-claude-code-settings.py, statusline-command.sh, …
  resources/   settings.enforced.json (built from the fragments), per-customization data
  logs/        enforce.log, enforce.out.log, enforce.err.log
~/Library/LaunchAgents/com.user.custom-claude-code-settings.enforce.plist
```

Nothing is written outside that directory, the LaunchAgents plist, and the
enforced keys inside `~/.claude/settings.json`.

## Day to day

```bash
scripts/status.sh          # installed? agent loaded? settings drifted?
scripts/logs.sh -f         # watch the watchdog
scripts/enforce-now.sh     # re-apply right now
scripts/uninstall.sh       # stop enforcing
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
list of placeholders and for the `.disabled` marker that skips a customization.

## How enforcement behaves

- Only enforced keys are touched — everything else in `settings.json` is kept.
- The file is rewritten only when the merge result actually differs, and always
  atomically (temp file + rename).
- An unparseable `settings.json` is copied to `settings.json.broken-<timestamp>`
  before being rebuilt.
- Triggers: `WatchPaths` on `settings.json` and `settings.enforced.json`, at
  load, plus a 5-minute safety net.

## Caveat

Managed (enterprise) settings win over user settings, so a key pinned by a
managed policy cannot be overridden here — the enforcer will keep writing it
and Claude Code will keep ignoring it.
