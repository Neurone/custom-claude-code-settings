# Customizations

One directory per customization. Everything in here is *what you want Claude
Code to look like*; the enforcement utility in `../enforcement/` is only the
watchdog that keeps it in place.

## Layout of a customization

```text
customizations/<name>/
  customization.json         required — settings fragment merged into settings.json
  customization.meta.json    optional — description and dependencies (see below)
  bin/                       optional — executables, installed flat into <install>/bin/
  resources/                 optional — data files, installed into <install>/resources/<name>/
  README.md                  optional — docs for humans
```

`bin/` is flattened into a single shared `<install>/bin/`, so give executables
names unlikely to clash with another customization's.

A customization that contributes nothing to `settings.json` of its own (for
example a `statusline` segment that only adds a `resources/` manifest) still
needs a `customization.json` — just make it `{}`.

## Dependencies

`customization.meta.json` declares what a customization needs and, for
`status.sh`, what it's for:

```json
{
  "description": "HBAR price in USD with 1h/24h change",
  "requires": ["statusline"]
}
```

| Field       | Meaning                                                        |
| ----------- | --------------------------------------------------------------- |
| `description` | One line shown by `scripts/status.sh`.                        |
| `requires`    | Names of other customizations this one needs installed first. |

`scripts/install-or-update.sh` expands whatever you name on the command line
to its full transitive closure — installing `hbar-addicted` also installs
`statusline` and says so — and the result is a *union* with whatever's
already installed, never a replacement. `scripts/uninstall.sh` refuses to
remove a customization still required by one that stays installed, telling
you which one and the command to remove both. An unknown dependency name or a
dependency cycle is an error (`scripts/status.sh` reports it as a warning
instead, so the catalog still prints).

Fragments are merged **in topological order** (dependencies first, later
wins on overlapping keys) instead of directory-name order, so a customization
can override a setting from something it requires — see `hbar-addicted`,
which needs `statusline` and deep-merges `statusLine.refreshInterval` on top
of `statusline`'s own `statusLine.command`.

If you're contributing a `statusline` segment specifically, see
[`statusline/docs/statusline-segments.md`](statusline/docs/statusline-segments.md)
for the full manifest/stdin/stdout contract.

## Placeholders

`customization.json` and any file directly under `resources/` may use these
placeholders; they are substituted at install time. (Subdirectories of
`resources/` are copied verbatim — no substitution happens inside them.)

| Placeholder          | Expands to                                              |
| -------------------- | ------------------------------------------------------- |
| `@@INSTALL_DIR@@`    | `~/.claude/customizations/custom-claude-code-settings`  |
| `@@BIN_DIR@@`        | `<install>/bin`                                         |
| `@@RESOURCES_DIR@@`  | `<install>/resources`                                   |
| `@@LOG_DIR@@`        | `<install>/logs`                                        |
| `@@LOG_PATH@@`       | `<install>/logs/enforce.log`                            |
| `@@BACKUP_DIR@@`     | `<install>/backups`                                     |
| `@@CACHE_DIR@@`      | `<install>/cache`                                       |
| `@@ENFORCED_PATH@@`  | `<install>/resources/settings.enforced.json`            |
| `@@SETTINGS_PATH@@`  | `~/.claude/settings.json`                               |
| `@@CLAUDE_DIR@@`     | `~/.claude`                                             |
| `@@HOME@@`           | `~`                                                     |
| `@@LABEL@@`          | `com.user.custom-claude-code-settings.enforce`          |

`@@ENFORCED_PATH@@`, `@@SETTINGS_PATH@@` and `@@LABEL@@` exist mainly for the
launchd/systemd templates, but the same rendering is applied to
customizations.

`@@CLAUDE_DIR@@` and `@@INSTALL_DIR@@` follow the `CLAUDE_DIR` and
`CUSTOM_CLAUDE_SETTINGS_HOME` environment overrides; the table shows the
defaults.

`scripts/install-or-update.sh` also creates `<install>/logs/<name>/` and
`<install>/cache/<name>/` for every installed customization — that's where
yours should write its own logs and volatile state (`@@LOG_DIR@@/<name>` and
`@@CACHE_DIR@@/<name>` once installed), never anywhere else. Both are removed
by `scripts/uninstall.sh` when the customization is.

## Adding one

1. `mkdir customizations/my-thing`
2. Write `customization.json` with just the keys you want enforced (`{}` if
   none — see above).
3. If it needs another customization installed first, add
   `customization.meta.json` with a `requires` list.
4. Drop any executable in `customizations/my-thing/bin/` and reference it as
   `@@BIN_DIR@@/<file>`.
5. Run `scripts/install-or-update.sh`.
