#!/usr/bin/env python3
"""Unit tests for enforcement/enforce-custom-claude-code-settings.py.

Runs the script as a subprocess (its paths are read from environment
variables at import time, so this is the simplest way to exercise it against
disposable temp directories) and asserts on exit code, resulting files, and
log output.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SCRIPT = os.path.join(REPO_DIR, "enforcement", "enforce-custom-claude-code-settings.py")

ENFORCED_CONTENT = {
    "showClearContextOnPlanAccept": True,
    "attribution": {"commit": "", "pr": ""},
    "statusLine": {"type": "command", "command": "/opt/statusline-command.sh"},
}


class EnforceScriptTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.settings_path = os.path.join(self.tmp.name, "settings.json")
        self.enforced_path = os.path.join(self.tmp.name, "settings.enforced.json")
        self.log_path = os.path.join(self.tmp.name, "logs", "enforce.log")
        self.backup_dir = os.path.join(self.tmp.name, "backups")
        with open(self.enforced_path, "w", encoding="utf-8") as handle:
            json.dump(ENFORCED_CONTENT, handle)

    def write_settings(self, text):
        with open(self.settings_path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def read_settings(self):
        with open(self.settings_path, "r", encoding="utf-8") as handle:
            return handle.read()

    def read_log(self):
        if not os.path.exists(self.log_path):
            return ""
        with open(self.log_path, "r", encoding="utf-8") as handle:
            return handle.read()

    def backups(self):
        if not os.path.exists(self.backup_dir):
            return []
        return os.listdir(self.backup_dir)

    def run_script(self, *args):
        env = dict(os.environ)
        env.update(
            {
                "CUSTOM_CLAUDE_SETTINGS_TARGET": self.settings_path,
                "CUSTOM_CLAUDE_SETTINGS_ENFORCED": self.enforced_path,
                "CUSTOM_CLAUDE_SETTINGS_LOG": self.log_path,
                "CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR": self.backup_dir,
            }
        )
        return subprocess.run(
            [sys.executable, SCRIPT, *args],
            env=env,
            capture_output=True,
            text=True,
        )

    def test_missing_settings_file_is_created(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.read_settings()), ENFORCED_CONTENT)
        self.assertIn("creating it", self.read_log())

    def test_empty_settings_file_is_populated(self):
        self.write_settings("")
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(self.read_settings()), ENFORCED_CONTENT)

    def test_valid_settings_are_deep_merged(self):
        self.write_settings(json.dumps({"model": "sonnet", "showClearContextOnPlanAccept": False}))
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        merged = json.loads(self.read_settings())
        self.assertEqual(merged["model"], "sonnet")
        self.assertEqual(merged["showClearContextOnPlanAccept"], True)
        self.assertEqual(merged["attribution"], ENFORCED_CONTENT["attribution"])

    def test_already_in_sync_does_not_rewrite_file(self):
        self.write_settings(json.dumps(ENFORCED_CONTENT))
        before = os.path.getmtime(self.settings_path)
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(os.path.getmtime(self.settings_path), before)
        self.assertEqual(self.backups(), [])

    def test_invalid_json_is_left_untouched(self):
        broken = '{\n  "model": "sonnet",\n  "hooks": {\n    "PreToolUse": [\n'  # truncated/invalid JSON
        self.write_settings(broken)
        result = self.run_script()

        self.assertEqual(result.returncode, 1)
        # The original broken file must be preserved exactly, not replaced
        # with only the enforced keys.
        self.assertEqual(self.read_settings(), broken)

        log_contents = self.read_log()
        self.assertIn("settings unusable", log_contents)
        self.assertIn("leaving", log_contents)
        self.assertIn("untouched", log_contents)

        # A copy of the broken file is kept for forensics, in the backup dir
        # only (never overwriting the real settings file).
        backups = self.backups()
        self.assertEqual(len(backups), 1)
        with open(os.path.join(self.backup_dir, backups[0]), "r", encoding="utf-8") as handle:
            self.assertEqual(handle.read(), broken)

    def test_valid_json_but_not_an_object_is_left_untouched(self):
        self.write_settings(json.dumps([1, 2, 3]))
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(self.read_settings()), [1, 2, 3])
        self.assertIn("not a JSON object", self.read_log())

    def test_check_only_never_writes(self):
        broken = "{not valid json"
        self.write_settings(broken)
        result = self.run_script("--check")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.read_settings(), broken)
        self.assertEqual(self.backups(), [])
        self.assertIn("unusable", result.stdout)


if __name__ == "__main__":
    unittest.main()
