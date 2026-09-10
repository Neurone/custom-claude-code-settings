# Maintenance scripts

Everything that touches your machine lives here; nothing else in this repo
installs, moves or deletes files.

| Script | What it does |
| ------ | ------------ |
| `install-or-update.sh [name...]` | Install/update the named customizations (default: all enabled) and (re)load the watchdog service |
| `status.sh` | What is installed, watchdog state, and whether settings.json drifted |
| `enforce-now.sh` | Run the enforcement utility once, immediately |
| `logs.sh [-f\|<lines>]` | Show (or follow) the enforcement logs |
| `uninstall.sh [--keep-files] [name...]` | Unload the watchdog service, strip the named customizations' keys out of settings.json (default: all), and remove their installed files (`--keep-files` keeps the install dir). The service is always fully torn down; if some customizations remain, re-run `install-or-update.sh` to resume enforcing them. |
| `shellcheck.sh` | Run `shellcheck -x` over every `*.sh` in the repo (dev only) |
| `test-linux.sh` | Docker-based Linux smoke test: with and without a `systemd --user` manager (dev only) |

`lib/common.sh` holds the shared paths and the `@@...@@` placeholder
rendering, and sources the platform-specific service backend
(`lib/platform-darwin.sh` or `lib/platform-linux.sh`, chosen by `uname -s`) —
source it, don't run it.

Overrides (mostly for testing): `CLAUDE_DIR` and `CUSTOM_CLAUDE_SETTINGS_HOME`
for these scripts; `CUSTOM_CLAUDE_SETTINGS_TARGET`,
`CUSTOM_CLAUDE_SETTINGS_ENFORCED`, `CUSTOM_CLAUDE_SETTINGS_LOG`,
`CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR` and `CUSTOM_CLAUDE_SETTINGS_LABEL` for the
enforcement utility itself.
