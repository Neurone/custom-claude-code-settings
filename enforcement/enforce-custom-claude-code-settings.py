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

    CUSTOM_CLAUDE_SETTINGS_ENFORCED  <install-dir>/resources/settings.enforced.json
    CUSTOM_CLAUDE_SETTINGS_LOG       <install-dir>/logs/enforce.log
    CUSTOM_CLAUDE_SETTINGS_TARGET    ~/.claude/settings.json

Usage:
    enforce-custom-claude-code-settings.py            enforce, writing if needed
    enforce-custom-claude-code-settings.py --check    report drift, write nothing
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
    check_only = "--check" in argv[1:]
    unknown = [arg for arg in argv[1:] if arg != "--check"]
    if unknown:
        sys.stderr.write("unknown argument(s): {}\n".format(" ".join(unknown)))
        return 2

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
    if current is None or not isinstance(current, dict):
        if check_only:
            print("settings {} unusable ({})".format(SETTINGS_PATH, error))
            return 1
        # Never silently discard a file we could not parse: keep a copy first.
        if os.path.exists(SETTINGS_PATH) and error != "empty":
            backup = "{}.broken-{}".format(
                SETTINGS_PATH, datetime.now().strftime("%Y%m%d-%H%M%S")
            )
            try:
                shutil.copy2(SETTINGS_PATH, backup)
                log("settings unusable ({}), copied to {}".format(error, backup))
            except OSError as exc:
                log("settings unusable ({}), backup failed: {}".format(error, exc))
                return 1
        else:
            log("settings {} ({}), creating it".format(SETTINGS_PATH, error))
        current = {}

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

    try:
        atomic_write(SETTINGS_PATH, merged)
    except OSError as exc:
        log("ERROR writing {}: {}".format(SETTINGS_PATH, exc))
        return 1

    log("restored: {}".format("; ".join(diffs) if diffs else "reordered keys"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
