# Maintenance scripts

Everything that touches your machine lives here; nothing else in this repo
installs, moves or deletes files.

| Script | What it does |
| ------ | ------------ |
| `install-or-update.sh [name...]` | Install/update the named customizations plus their dependencies (default: everything in the repo), *union'd* with whatever's already installed, and (re)load the watchdog service |
| `status.sh` | Catalog of every customization (installed state, dependencies, description), watchdog state, and whether settings.json drifted |
| `enforce-now.sh` | Run the enforcement utility once, immediately |
| `logs.sh [-f\|<lines>] [name]` | Show (or follow) the watchdog logs, or one customization's own logs under `logs/<name>/` |
| `uninstall.sh [--keep-files] [name...]` | Unload the watchdog service, strip the named customizations' keys out of settings.json (default: everything installed), and remove their installed files, logs and cache (`--keep-files` keeps the install dir). Refuses to remove a customization still required by an installed dependent — no implicit cascade. The service is always fully torn down; if some customizations remain, re-run `install-or-update.sh` to resume enforcing them. |
| `shellcheck.sh` | Run `shellcheck -x` over every `*.sh` in the repo (dev only) |
| `test-all.sh` | Single entry point for the whole test suite: the commands above, natively, only on macOS; `test-linux.sh`, always (dev only) |
| `test-linux.sh` | Docker-based: the full test suite (`tests/`) run against Linux/GNU coreutils, plus install/status/enforce-now/uninstall verification with and without a `systemd --user` manager. If Docker isn't available and this host is already Linux, runs the (complete) test suite directly here instead; the install/uninstall verification needs a disposable container, so it only runs via Docker (dev only) |

`lib/common.sh` holds the shared paths, the dependency-resolution and
install-manifest helpers (`resolve_dependencies`, `installed_customizations`,
`write_install_manifest`, `list_contains`, ...), and the `@@...@@` placeholder
rendering, and sources the platform-specific service backend
(`lib/platform-darwin.sh` or `lib/platform-linux.sh`, chosen by `uname -s`) —
source it, don't run it.

Overrides (mostly for testing): `CLAUDE_DIR` and `CUSTOM_CLAUDE_SETTINGS_HOME`
for these scripts; `CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS` to point at a
different customizations source directory (used by the dependency-resolution
tests against fixtures instead of the repo's own `customizations/`);
`CUSTOM_CLAUDE_SETTINGS_TARGET`, `CUSTOM_CLAUDE_SETTINGS_ENFORCED`,
`CUSTOM_CLAUDE_SETTINGS_LOG`, `CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR` and
`CUSTOM_CLAUDE_SETTINGS_LABEL` for the enforcement utility itself.
