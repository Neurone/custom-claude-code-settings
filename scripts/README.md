# Maintenance scripts

Everything that touches your machine lives here; nothing else in this repo
installs, moves or deletes files.

| Script                                       | What it does                                                                          |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| `install-or-update.sh [name...]`             | Install/update the named customizations (default: all enabled) and (re)load the agent |
| `status.sh`                                  | What is installed, agent state, and whether settings.json drifted                     |
| `enforce-now.sh`                              | Run the enforcement utility once, immediately                                         |
| `logs.sh [-f\|<lines>]`                      | Show (or follow) the enforcement logs                                                 |
| `uninstall.sh [--keep-files] [name...]`      | Unload the agent, strip the named customizations' keys out of settings.json (default: all), and remove their installed files (`--keep-files` keeps the install dir). If some customizations remain, the agent is reloaded to keep enforcing them. |
| `shellcheck.sh`                               | Run `shellcheck -x` over every `*.sh` in the repo (dev only)                           |

`lib/common.sh` holds the shared paths, the `@@...@@` placeholder rendering and
the launchd identifiers — source it, don't run it.

Overrides (mostly for testing): `CLAUDE_DIR` and `CUSTOM_CLAUDE_SETTINGS_HOME`
for these scripts; `CUSTOM_CLAUDE_SETTINGS_TARGET`,
`CUSTOM_CLAUDE_SETTINGS_ENFORCED` and `CUSTOM_CLAUDE_SETTINGS_LOG` for the
enforcement utility itself.
