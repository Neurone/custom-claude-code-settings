# Customizations

One directory per customization. Everything in here is *what you want Claude
Code to look like*; the enforcement utility in `../enforcement/` is only the
watchdog that keeps it in place.

## Layout of a customization

```text
customizations/<name>/
  customization.json   required — settings fragment merged into settings.json
  bin/                 optional — executables, installed flat into <install>/bin/
  resources/           optional — data files, installed into <install>/resources/<name>/
  README.md            optional — docs for humans
```

`bin/` is flattened into a single shared `<install>/bin/`, so give executables
names unlikely to clash with another customization's.

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

## Adding one

1. `mkdir customizations/my-thing`
2. Write `customization.json` with just the keys you want enforced.
3. Drop any executable in `customizations/my-thing/bin/` and reference it as
   `@@BIN_DIR@@/<file>`.
4. Run `scripts/install-or-update.sh`.

Fragments are merged in directory-name order (deep merge, later wins), so keep
overlapping keys out of separate customizations.
