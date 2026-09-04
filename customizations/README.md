# Customizations

One directory per customization. Everything in here is *what you want Claude
Code to look like*; the enforcement utility in `../enforcement/` is only the
watchdog that keeps it in place.

## Layout of a customization

```text
customizations/<name>/
  customization.json   required — settings fragment merged into settings.json
  bin/                 optional — executables, installed into <install>/bin/
  resources/           optional — data files, installed into <install>/resources/<name>/
  README.md            optional — docs for humans
  .disabled            optional — marker file; presence skips the customization
```

## Placeholders

`customization.json` (and any file under `resources/`) may use these
placeholders; they are substituted at install time:

| Placeholder          | Expands to                                              |
| -------------------- | ------------------------------------------------------- |
| `@@INSTALL_DIR@@`    | `~/.claude/customizations/custom-claude-code-settings`  |
| `@@BIN_DIR@@`        | `<install>/bin`                                         |
| `@@RESOURCES_DIR@@`  | `<install>/resources`                                   |
| `@@LOG_DIR@@`        | `<install>/logs`                                        |
| `@@CLAUDE_DIR@@`     | `~/.claude`                                             |
| `@@HOME@@`           | `~`                                                     |

## Adding one

1. `mkdir customizations/my-thing`
2. Write `customization.json` with just the keys you want enforced.
3. Drop any executable in `customizations/my-thing/bin/` and reference it as
   `@@BIN_DIR@@/<file>`.
4. Run `scripts/install-or-update.sh`.

Fragments are merged in directory-name order (deep merge, later wins), so keep
overlapping keys out of separate customizations.
