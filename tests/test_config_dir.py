#!/usr/bin/env python3
"""Unit tests for where the scripts look for Claude Code's config dir: the
CLAUDE_DIR override, Claude Code's own CLAUDE_CONFIG_DIR, and the default
~/.claude, plus the service label and placeholder rendering that depend on it (see scripts/lib/common.sh
and enforcement/enforce-custom-claude-code-settings.py).

common.sh is sourced in a bash subprocess; the enforcer runs as a subprocess.
HOME always points at a disposable temp dir, so nothing here touches the real
~/.claude.
"""

import json
import os
import subprocess
import tempfile
import unittest

from sandbox_env import sandboxed_environ

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
COMMON_SH = os.path.join(REPO_DIR, "scripts", "lib", "common.sh")
ENFORCER = os.path.join(REPO_DIR, "enforcement", "enforce-custom-claude-code-settings.py")

DEFAULT_LABEL = "com.user.custom-claude-code-settings.enforce"
PATH_OVERRIDES = (
    "CLAUDE_DIR",
    "CLAUDE_CONFIG_DIR",
    "CUSTOM_CLAUDE_SETTINGS_HOME",
    "CUSTOM_CLAUDE_SETTINGS_LABEL",
    "CUSTOM_CLAUDE_SETTINGS_TARGET",
)


class ConfigDirTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = os.path.join(self.tmp.name, "home")
        os.makedirs(self.home)

    def env(self, **overrides):
        env = sandboxed_environ(self.home, dropped=PATH_OVERRIDES)
        env.update(overrides)
        return env

    def common_value(self, expression, **overrides):
        script = 'source "{}"\nprintf %s "{}"'.format(COMMON_SH, expression)
        result = subprocess.run(
            ["bash", "-c", script], env=self.env(**overrides), capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_defaults_to_the_home_claude_dir_and_the_default_label(self):
        self.assertEqual(self.common_value("$CLAUDE_DIR"), os.path.join(self.home, ".claude"))
        self.assertEqual(self.common_value("$LABEL"), DEFAULT_LABEL)

    def test_claude_config_dir_relocates_the_whole_install(self):
        config_dir = os.path.join(self.tmp.name, "sandbox-config")
        overrides = {"CLAUDE_CONFIG_DIR": config_dir}
        self.assertEqual(self.common_value("$CLAUDE_DIR", **overrides), config_dir)
        self.assertEqual(
            self.common_value("$SETTINGS_PATH", **overrides), os.path.join(config_dir, "settings.json")
        )
        self.assertEqual(
            self.common_value("$INSTALL_DIR", **overrides),
            os.path.join(config_dir, "customizations", "custom-claude-code-settings"),
        )

    def test_claude_dir_wins_over_claude_config_dir(self):
        claude_dir = os.path.join(self.tmp.name, "explicit")
        overrides = {"CLAUDE_DIR": claude_dir, "CLAUDE_CONFIG_DIR": os.path.join(self.tmp.name, "other")}
        self.assertEqual(self.common_value("$CLAUDE_DIR", **overrides), claude_dir)

    def test_explicit_home_claude_dir_keeps_the_default_label(self):
        overrides = {"CLAUDE_DIR": os.path.join(self.home, ".claude")}
        self.assertEqual(self.common_value("$LABEL", **overrides), DEFAULT_LABEL)

    def test_other_config_dir_keeps_the_default_label(self):
        overrides = {"CLAUDE_CONFIG_DIR": os.path.join(self.tmp.name, "a")}
        self.assertEqual(self.common_value("$LABEL", **overrides), DEFAULT_LABEL)

    def test_placeholders_are_substituted_literally_whatever_the_config_dir_contains(self):
        tricky_dir = os.path.join(self.tmp.name, "a&b|c\\d")
        script = 'source "{}"\necho "@@CLAUDE_DIR@@ @@SETTINGS_PATH@@" | render_placeholders'.format(COMMON_SH)

        result = subprocess.run(
            ["bash", "-c", script], env=self.env(CLAUDE_DIR=tricky_dir), capture_output=True, text=True
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(), "{} {}".format(tricky_dir, os.path.join(tricky_dir, "settings.json"))
        )

    def test_explicit_label_wins_for_any_config_dir(self):
        overrides = {
            "CLAUDE_CONFIG_DIR": os.path.join(self.tmp.name, "a"),
            "CUSTOM_CLAUDE_SETTINGS_LABEL": "my.label",
        }
        self.assertEqual(self.common_value("$LABEL", **overrides), "my.label")

    def test_enforcer_targets_claude_config_dir_settings_by_default(self):
        config_dir = os.path.join(self.tmp.name, "sandbox-config")
        os.makedirs(config_dir)
        enforced = os.path.join(self.tmp.name, "settings.enforced.json")
        with open(enforced, "w", encoding="utf-8") as handle:
            json.dump({"attribution": {"commit": "", "pr": ""}}, handle)

        result = subprocess.run(
            ["python3", ENFORCER],
            env=self.env(
                CLAUDE_CONFIG_DIR=config_dir,
                CUSTOM_CLAUDE_SETTINGS_ENFORCED=enforced,
                CUSTOM_CLAUDE_SETTINGS_LOG=os.path.join(self.tmp.name, "enforce.log"),
                CUSTOM_CLAUDE_SETTINGS_BACKUP_DIR=os.path.join(self.tmp.name, "backups"),
            ),
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        with open(os.path.join(config_dir, "settings.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), {"attribution": {"commit": "", "pr": ""}})
        self.assertFalse(os.path.exists(os.path.join(self.home, ".claude")))


if __name__ == "__main__":
    unittest.main()
