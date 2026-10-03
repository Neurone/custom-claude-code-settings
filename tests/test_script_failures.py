#!/usr/bin/env python3
"""Unit tests for how the maintenance scripts behave when something is wrong:
an enforcer failure must be reported, and a bad catalog must not abort status.sh.

Every run targets a config dir other than $HOME/.claude, so no service manager
is ever involved.
"""

import json
import os
import subprocess
import tempfile
import unittest

from sandbox_env import sandboxed_environ

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SCRIPTS_DIR = os.path.join(REPO_DIR, "scripts")
COMMON_SH = os.path.join(SCRIPTS_DIR, "lib", "common.sh")
CLAUDE_DIR_VARIABLES = ("CLAUDE_DIR", "CLAUDE_CONFIG_DIR")


class ScriptFailureTestCase(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.home]))
        self.claude_dir = os.path.join(self.home, "config")
        os.makedirs(self.claude_dir)
        self.settings_path = os.path.join(self.claude_dir, "settings.json")

    def run_script(self, script, *args, **env_overrides):
        env = sandboxed_environ(self.home, dropped=CLAUDE_DIR_VARIABLES)
        env["CLAUDE_DIR"] = self.claude_dir
        env.update(env_overrides)
        return subprocess.run(["bash", os.path.join(SCRIPTS_DIR, script), *args], env=env, capture_output=True, text=True)

    def write_settings(self, text):
        with open(self.settings_path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def make_catalog(self, **meta_by_name):
        catalog = os.path.join(self.home, "catalog")
        for name, meta_text in meta_by_name.items():
            os.makedirs(os.path.join(catalog, name))
            with open(os.path.join(catalog, name, "customization.json"), "w", encoding="utf-8") as handle:
                handle.write("{}")
            if meta_text is not None:
                with open(os.path.join(catalog, name, "customization.meta.json"), "w", encoding="utf-8") as handle:
                    handle.write(meta_text)
        os.makedirs(catalog, exist_ok=True)
        return catalog


class EnforcerFailureTest(ScriptFailureTestCase):
    def test_install_reports_why_the_enforcer_refused_a_broken_settings_file(self):
        self.write_settings("{ broken")

        result = self.run_script("install-or-update.sh", "no-attribution")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not enforce", result.stderr)
        self.assertIn("settings unusable", result.stderr)

    def test_install_leaves_a_broken_settings_file_untouched(self):
        self.write_settings("{ broken")

        self.run_script("install-or-update.sh", "no-attribution")

        with open(self.settings_path, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), "{ broken")

    def test_enforce_now_reports_why_the_enforcer_refused_a_broken_settings_file(self):
        self.run_script("install-or-update.sh", "no-attribution")
        self.write_settings("{ broken")

        result = self.run_script("enforce-now.sh")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not enforce", result.stderr)
        self.assertIn("settings unusable", result.stderr)

    def test_install_names_the_backup_it_made_when_settings_change(self):
        self.write_settings(json.dumps({"model": "opus"}))

        result = self.run_script("install-or-update.sh", "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"Enforced settings\.json \(backup: settings\.json\.bak-\d{8}-\d{6}\)")


class StatusRobustnessTest(ScriptFailureTestCase):
    def test_status_lists_a_customization_whose_meta_file_is_malformed(self):
        catalog = self.make_catalog(foo="{ nope")

        result = self.run_script("status.sh", CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS=catalog)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("foo", result.stdout)

    def test_status_with_an_empty_catalog_does_not_fail(self):
        catalog = self.make_catalog()

        result = self.run_script("status.sh", CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS=catalog)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("unbound variable", result.stderr)


class RenderPlaceholdersTest(ScriptFailureTestCase):
    def render(self, template, home):
        script = 'source "{}"\nprintf "%s" "$1" | render_placeholders'.format(COMMON_SH)
        env = sandboxed_environ(home, dropped=CLAUDE_DIR_VARIABLES)
        return subprocess.run(["bash", "-c", script, "bash", template], env=env, capture_output=True, text=True, check=True).stdout

    def test_special_characters_in_a_value_are_inserted_literally(self):
        special_home = r"/tmp/a&b|c\d"

        self.assertEqual(self.render("@@HOME@@/x", special_home), special_home + "/x")

    def test_every_occurrence_and_every_placeholder_on_a_line_is_replaced(self):
        rendered = self.render("@@HOME@@ @@HOME@@ @@CLAUDE_DIR@@", "/h")

        self.assertEqual(rendered, "/h /h /h/.claude")


if __name__ == "__main__":
    unittest.main()
