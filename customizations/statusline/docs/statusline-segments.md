# Status line segments

`statusline` (`customizations/statusline/`) owns the `statusLine` key in
`settings.json` but renders nothing itself. It's a host: it collects
*segments* contributed by other customizations, orders them, and joins them
with a separator. Any customization that wants to show something in the
status line adds a manifest and an executable — no need to touch
`statusline` itself, and no scramble over who wins `statusLine`.

## Requiring the host

A segment customization needs `statusline` installed, declared in its
`customization.meta.json`:

```json
{
  "description": "HBAR price in USD with 1h/24h change",
  "requires": ["statusline"]
}
```

See `customizations/README.md` for the full `customization.meta.json` schema
and how `requires` drives install ordering and dependency checks.

## The manifest

`customizations/<name>/resources/statusline-segment.json`:

```json
{
  "order": 20,
  "command": "hbar-segment.sh"
}
```

| Field     | Meaning                                                                                     |
| --------- | ------------------------------------------------------------------------------------------- |
| `order`   | Integer. Segments are placed left to right by `(order, directory name)`. Lower sorts first. |
| `command` | Filename of the executable, installed alongside every other segment in the shared `bin/`. Resolved against `bin/` by the host at runtime (an absolute path is also accepted, taken as-is). |

Use a bare filename, not `@@BIN_DIR@@/<file>`: that placeholder bakes in the
*install-time* `$HOME`, which breaks the moment `~/.claude` is later mounted
somewhere with a different `$HOME` (e.g. a container) — the manifest would
still point at the original host path. Resolving against `bin/` at runtime,
the same way `bin/statusline-command.sh` locates its own `resources/`,
sidesteps that entirely.

`claude-session-info` uses `order: 10`, `hbar-addicted` uses `order: 20`.
Leave gaps between the numbers you pick so something can be inserted later
without renumbering everything else.

## The segment contract

The host invokes `command` with **the same JSON payload Claude Code gives the
status line, unchanged, on stdin** — a segment is effectively a miniature
status line command. See the [statusline
docs](https://code.claude.com/docs/en/statusline) for the payload shape
(`model`, `workspace`, `context_window`, `cost`, etc.).

A segment must:

- Print **one line, no trailing newline**, using `printf` (not `echo`) —
  matches the convention already used by `claude-session-info`.
- Own its ANSI colors. The host contributes no color of its own beyond the
  separator and the failure marker.
- Never block on the network. If a segment depends on a slow external
  source, fetch it in the background and render the last known value (see
  `hbar-addicted`'s `hbar-segment.sh` for the pattern: a TTL-gated background
  fetch plus rendering from a local cache).
- Print nothing (exit 0, empty stdout) when it has nothing to show. The host
  omits the segment entirely — no stray separator.
- Write its own logs to `@@LOG_DIR@@/<name>/` and its own cache to
  `@@CACHE_DIR@@/<name>/` (created by `install-or-update.sh` for every
  installed customization). Nothing outside those two directories is yours.

## Host rendering rules

- Segments are joined by `SEGMENT_SEPARATOR` (a constant at the top of
  `bin/statusline-command.sh`): ` │ ` (U+2502) in dim gray, so the boundary
  between customizations stays visible.
- A segment whose command is missing/not executable, or that exits non-zero,
  is replaced by a red `<name>!` marker — noisy on purpose, but it does not
  break the rest of the line.
- Empty stdout from a segment omits it silently (no separator either side).
- No segments installed at all (a fresh `statusline`-only install, or
  everything uninstalled but `statusline`) ⇒ empty status line, not an error.

## No right alignment

Claude Code already uses the right side of the status line row for system
notifications and, in verbose mode, the token counter — and there's no way
for a segment to know when that will happen. So segments are laid out
left to right only, in `order`; nothing pins content to the right edge.

## Testing a segment in isolation

Every segment is just a command that reads the Claude Code payload from
stdin and prints one line, so it can be exercised directly without going
through the host:

```bash
echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"}}' \
  | customizations/claude-session-info/bin/claude-session-info-segment.sh
```
