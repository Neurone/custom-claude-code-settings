#!/usr/bin/env python3
"""Keep the customized keys present in ~/.claude/settings.json.

This is the watchdog half of "custom claude settings": the customizations
themselves live in <install-dir>/resources/settings.enforced.json (built by
scripts/install-or-update.sh out of customizations/*/customization.json).
Claude Code rewrites settings.json on its own from time to time and can drop
those keys; this script puts them back.

Instead of overwriting the whole file (which would lose any legitimate change
made by Claude Code), it deep-merges the enforced keys into the existing
settings and only rewrites the file when the result actually differs.

Layout, all relative to the directory this script is installed into
(<install-dir>/bin), overridable via environment variables:

    CUSTOM_CLAUDE_SETTINGS_ENFORCED    <install-dir>/resources/settings.enforced.json
    CUSTOM_CLAUDE_SETTINGS_LOG         <install-dir>/logs/enforce.log
    CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR  <install-dir>/backups
    CUSTOM_CLAUDE_SETTINGS_TARGET      ~/.claude/settings.json

Usage:
    enforce-custom-claude-code-settings.py                 enforce, writing if needed
    enforce-custom-claude-code-settings.py --check          report drift, write nothing
    enforce-custom-claude-code-settings.py --remove FRAGMENT   strip FRAGMENT's keys
                                                                out of the target settings
"""

import json
import os
import shutil
import sys
import tempfile
from datetime import datetime

HOME = os.path.expanduser("~")
INSTALL_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

SETTINGS_PATH = os.environ.get(
    "CUSTOM_CLAUDE_SETTINGS_TARGET", os.path.join(HOME, ".claude", "settings.json")
)
ENFORCED_PATH = os.environ.get(
    "CUSTOM_CLAUDE_SETTINGS_ENFORCED",
    os.path.join(INSTALL_DIR, "resources", "settings.enforced.json"),
)
LOG_PATH = os.environ.get(
    "CUSTOM_CLAUDE_SETTINGS_LOG", os.path.join(INSTALL_DIR, "logs", "enforce.log")
)
BACKUP_DIR = os.environ.get(
    "CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR", os.path.join(INSTALL_DIR, "backups")
)

# Keep at most this many bytes of log history.
LOG_MAX_BYTES = 256 * 1024


def log(message):
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > LOG_MAX_BYTES:
            with open(LOG_PATH, "r", encoding="utf-8") as handle:
                tail = handle.read()[-LOG_MAX_BYTES // 2 :]
            with open(LOG_PATH, "w", encoding="utf-8") as handle:
                handle.write(tail)
        stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write("{} {}\n".format(stamp, message))
    except OSError:
        # Logging must never break the actual job.
        pass


def load_json(path):
    """Return (data, error). data is None when the file is missing or invalid."""
    if not os.path.exists(path):
        return None, "missing"
    try:
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        return None, "unreadable: {}".format(exc)
    if not text.strip():
        return None, "empty"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as exc:
        return None, "invalid JSON: {}".format(exc)


def deep_merge(base, override):
    """Return a copy of base with override applied recursively.

    Nested dicts are merged key by key; any other type in override replaces
    the value in base outright.
    """
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def deep_remove(current, fragment):
    """Return a copy of current with fragment's leaf keys stripped out.

    A nested object is dropped entirely once removing the fragment's keys
    leaves it empty; anything the user added alongside those keys (not part
    of the fragment) is preserved.
    """
    result = dict(current)
    for key, value in fragment.items():
        if key not in result:
            continue
        if isinstance(value, dict) and isinstance(result[key], dict):
            nested = deep_remove(result[key], value)
            if nested:
                result[key] = nested
            else:
                del result[key]
        else:
            del result[key]
    return result


def removed_paths(current, fragment, prefix=""):
    """List the dotted key paths that deep_remove would actually drop."""
    paths = []
    for key, value in fragment.items():
        if key not in current:
            continue
        path = "{}.{}".format(prefix, key) if prefix else key
        if isinstance(value, dict) and isinstance(current[key], dict):
            paths.extend(removed_paths(current[key], value, path))
        else:
            paths.append(path)
    return paths


def changed_paths(current, desired, prefix=""):
    """List the dotted key paths where desired differs from current."""
    diffs = []
    for key, value in desired.items():
        path = "{}.{}".format(prefix, key) if prefix else key
        if isinstance(value, dict) and isinstance(current.get(key), dict):
            diffs.extend(changed_paths(current[key], value, path))
        elif key not in current:
            diffs.append("{} (missing)".format(path))
        elif current[key] != value:
            diffs.append("{} (was {})".format(path, json.dumps(current[key])))
    return diffs


def backup_existing(path):
    """Copy path to a timestamped backup in BACKUP_DIR before it gets overwritten.

    Returns the backup path, or None if there was nothing to back up.
    """
    if not os.path.exists(path):
        return None
    os.makedirs(BACKUP_DIR, exist_ok=True)
    backup_name = "{}.bak-{}".format(
        os.path.basename(path), datetime.now().strftime("%Y%m%d-%H%M%S")
    )
    backup = os.path.join(BACKUP_DIR, backup_name)
    shutil.copy2(path, backup)
    return backup


def atomic_write(path, data):
    """Write JSON to path via a temp file in the same directory, then rename."""
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".settings-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        if os.path.exists(path):
            shutil.copymode(path, tmp_path)
        else:
            os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, path)
    except BaseException:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def main(argv):
    args = list(argv[1:])
    check_only = False
    remove_fragment_path = None
    unknown = []

    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--check":
            check_only = True
        elif arg == "--remove":
            i += 1
            if i >= len(args):
                sys.stderr.write("--remove requires a path argument\n")
                return 2
            remove_fragment_path = args[i]
        else:
            unknown.append(arg)
        i += 1
    if unknown:
        sys.stderr.write("unknown argument(s): {}\n".format(" ".join(unknown)))
        return 2
    if check_only and remove_fragment_path:
        sys.stderr.write("--check and --remove are mutually exclusive\n")
        return 2

    if remove_fragment_path:
        fragment, error = load_json(remove_fragment_path)
        if fragment is None:
            message = "ERROR removal fragment {}: {}".format(remove_fragment_path, error)
            log(message)
            sys.stderr.write(message + "\n")
            return 1
        if not isinstance(fragment, dict):
            sys.stderr.write("removal fragment must contain a JSON object\n")
            return 1

        current, error = load_json(SETTINGS_PATH)
        if current is None or not isinstance(current, dict):
            log("settings {} unusable or missing ({}), nothing to remove".format(SETTINGS_PATH, error))
            return 0

        updated = deep_remove(current, fragment)
        if updated == current:
            return 0

        backup = backup_existing(SETTINGS_PATH)

        try:
            atomic_write(SETTINGS_PATH, updated)
        except OSError as exc:
            log("ERROR writing {}: {}".format(SETTINGS_PATH, exc))
            return 1

        message = "removed: {}".format("; ".join(removed_paths(current, fragment)) or "keys")
        if backup:
            message += "; backup saved to {}".format(backup)
            print("backup saved to {}".format(backup))
        log(message)
        return 0

    desired, error = load_json(ENFORCED_PATH)
    if desired is None:
        message = "ERROR enforced file {}: {}".format(ENFORCED_PATH, error)
        log(message)
        if check_only:
            print(message)
        return 1
    if not isinstance(desired, dict):
        message = "ERROR enforced file must contain a JSON object"
        log(message)
        if check_only:
            print(message)
        return 1

    current, error = load_json(SETTINGS_PATH)
    if current is not None and not isinstance(current, dict):
        current, error = None, "not a JSON object"

    if current is None:
        if check_only:
            print("settings {} unusable ({})".format(SETTINGS_PATH, error))
            return 1
        if error in ("missing", "empty"):
            # Nothing of value to lose: safe to start from a blank settings file.
            log("settings {} ({}), creating it".format(SETTINGS_PATH, error))
            current = {}
        else:
            # The file has content we could not parse: never touch it, since a
            # partial rewrite would silently discard whatever it contains
            # (hooks, model, etc.) alongside our own keys. Back it up for
            # forensics and leave the original in place.
            message = "settings unusable ({}), leaving {} untouched".format(error, SETTINGS_PATH)
            try:
                os.makedirs(BACKUP_DIR, exist_ok=True)
                backup_name = "{}.broken-{}".format(
                    os.path.basename(SETTINGS_PATH), datetime.now().strftime("%Y%m%d-%H%M%S")
                )
                backup = os.path.join(BACKUP_DIR, backup_name)
                shutil.copy2(SETTINGS_PATH, backup)
                message += "; backup saved to {}".format(backup)
                print("backup saved to {}".format(backup))
            except OSError as exc:
                message += "; backup failed: {}".format(exc)
            log(message)
            return 1

    merged = deep_merge(current, desired)
    diffs = changed_paths(current, desired)

    if check_only:
        if merged == current:
            print("in sync: {} matches {}".format(SETTINGS_PATH, ENFORCED_PATH))
            return 0
        print("drift detected in {}:".format(SETTINGS_PATH))
        for diff in diffs or ["key order only"]:
            print("  - {}".format(diff))
        return 1

    if merged == current:
        return 0

    backup = backup_existing(SETTINGS_PATH)

    try:
        atomic_write(SETTINGS_PATH, merged)
    except OSError as exc:
        log("ERROR writing {}: {}".format(SETTINGS_PATH, exc))
        return 1

    message = "restored: {}".format("; ".join(diffs) if diffs else "reordered keys")
    if backup:
        message += "; backup saved to {}".format(backup)
        print("backup saved to {}".format(backup))
    log(message)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
