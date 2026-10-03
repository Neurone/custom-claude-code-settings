# Maintenance scripts

Everything that touches your machine lives here; nothing else in this repo
installs, moves or deletes files.

| Script | What it does |
| ------ | ------------ |
| `install-or-update.sh [name...]` | Install/update the named customizations plus their dependencies (default: everything in the repo), *union'd* with whatever's already installed, enforce them in settings.json and, for `~/.claude` only, (re)load the watchdog service |
| `status.sh` | Catalog of every customization (installed state, dependencies, description), watchdog state, and whether settings.json drifted |
| `enforce-now.sh` | Run the enforcement utility once, immediately |
| `logs.sh [-f\|<lines>] [name]` | Show (or follow) the watchdog logs, or one customization's own logs under `logs/<name>/` |
| `uninstall.sh [--keep-files] [name...]` | Strip the named customizations' keys out of settings.json (default: everything installed), and remove their installed files, logs and cache (`--keep-files` keeps the install dir). Refuses to remove a customization still required by an installed dependent — no implicit cascade. Removing everything from `~/.claude` also unloads its watchdog service; removing only some customizations rebuilds `settings.enforced.json` and reloads the service so the remaining ones keep being enforced. |
| `shellcheck.sh` | Run `shellcheck -x` over every `*.sh` in the repo (dev only) |
| `test-all.sh` | Single entry point for the whole test suite: the commands above, natively, only on macOS; `test-linux.sh`, always (dev only) |
| `test-linux.sh` | Docker-based: the full test suite (`tests/`) run against Linux/GNU coreutils, plus install/status/enforce-now/uninstall verification with and without a `systemd --user` manager. If Docker isn't available and this host is already Linux, runs the (complete) test suite directly here instead; the install/uninstall verification needs a disposable container, so it only runs via Docker (dev only) |

`lib/common.sh` holds the shared paths, the dependency-resolution and
install-manifest helpers (`resolve_dependencies`, `installed_customizations`,
`write_install_manifest`, `list_contains`, ...), and the `@@...@@` placeholder
rendering, and sources the platform-specific service backend
(`lib/platform-darwin.sh` or `lib/platform-linux.sh`, chosen by `uname -s`) —
source it, don't run it.

Config dir: every script sources `lib/select-claude-dir.sh` before `common.sh`.
If `CLAUDE_DIR` or Claude Code's own `CLAUDE_CONFIG_DIR` is set (`CLAUDE_DIR` wins),
that is the only dir. Otherwise it is every existing dir among `~/.claude` and
`~/.secure-ai/claude-code/config`: with both present, the script is re-run once per
dir with the same arguments (a failure in one does not skip the other; the exit
status is non-zero). If neither exists, `install-or-update.sh` (the only script that sets
`ASK_CLAUDE_DIR=1`) asks `Claude Code config dir [~/.claude]:`
when stdin is a terminal (Enter keeps the default; a leading `~` is expanded; the
path must be absolute), else uses `~/.claude`. Only `~/.claude` gets a watchdog
(`watchdog_wanted` in `lib/common.sh`); any other config dir, secure-ai's included,
only gets the one-time enforcement, and `install-or-update.sh`, `uninstall.sh` and
`status.sh` skip the service steps for it.

Overrides: `CLAUDE_DIR` and `CUSTOM_CLAUDE_SETTINGS_HOME` for these scripts.
Mostly for testing: `CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS` to point at a
different customizations source directory (used by the dependency-resolution
tests against fixtures instead of the repo's own `customizations/`) and
`CUSTOM_CLAUDE_SETTINGS_LABEL` for the launchd/systemd service label;
`XDG_CONFIG_HOME` (Linux) for where the systemd user units are written, which
otherwise default to `$HOME/.config`;
`CUSTOM_CLAUDE_SETTINGS_TARGET`, `CUSTOM_CLAUDE_SETTINGS_ENFORCED`,
`CUSTOM_CLAUDE_SETTINGS_LOG` and `CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR` for the
enforcement utility itself (`lib/common.sh` exports them so it agrees with the
scripts).

`lib/common.sh` turns on `set -euo pipefail` for every script that sources it;
a script that must tolerate a failure switches `errexit` off only around that
block (`status.sh`, while listing the catalog). If the enforcer itself fails (for
example on an unparseable `settings.json`), `install-or-update.sh` and
`enforce-now.sh` stop with the last entry of its log instead of exiting silently.
