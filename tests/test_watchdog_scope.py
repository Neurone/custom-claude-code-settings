#!/usr/bin/env python3
"""Unit tests for which config dirs get a watchdog service: the native Claude
Code one (~/.claude) does; every other dir, secure-ai's sandbox config dir
(~/.secure-ai/claude-code/config) included, does not, since nothing there rewrites
settings.json. Their customizations are still applied once.

Runs the real install-or-update.sh / uninstall.sh / status.sh with HOME pointed at
a disposable temp dir and launchctl/systemctl replaced by stubs on PATH, so no
service of the real user is touched.
"""

import glob
import json
import os
import subprocess
import tempfile
import unittest

from sandbox_env import sandboxed_environ

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SCRIPTS_DIR = os.path.join(REPO_DIR, "scripts")


class WatchdogScopeTestCase(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.home]))
        self.service_calls = os.path.join(self.home, "service-manager-calls.log")
        self.stub_bin = self.make_service_manager_stubs()
        self.native_dir = os.path.join(self.home, ".claude")
        self.secure_ai_dir = os.path.join(self.home, ".secure-ai", "claude-code", "config")

    def make_service_manager_stubs(self):
        stub_bin = os.path.join(self.home, "stub-bin")
        os.makedirs(stub_bin)
        for command, exit_code in (("launchctl", 0), ("systemctl", 1)):
            stub = os.path.join(stub_bin, command)
            with open(stub, "w", encoding="utf-8") as handle:
                handle.write('#!/bin/sh\necho "{} $*" >> "{}"\nexit {}\n'.format(command, self.service_calls, exit_code))
            os.chmod(stub, 0o755)
        return stub_bin

    def run_script(self, script, claude_dir, *args):
        env = sandboxed_environ(self.home, dropped=("CLAUDE_DIR", "CLAUDE_CONFIG_DIR"))
        env["CLAUDE_DIR"] = claude_dir
        env["PATH"] = self.stub_bin + os.pathsep + env["PATH"]
        return subprocess.run(
            ["bash", os.path.join(SCRIPTS_DIR, script), *args], env=env, capture_output=True, text=True
        )

    def service_files(self):
        patterns = ("Library/LaunchAgents/*.plist", ".config/systemd/user/*")
        return [path for pattern in patterns for path in glob.glob(os.path.join(self.home, pattern))]

    def settings_of(self, claude_dir):
        with open(os.path.join(claude_dir, "settings.json"), encoding="utf-8") as handle:
            return json.load(handle)

    def test_native_dir_gets_a_watchdog_service(self):
        result = self.run_script("install-or-update.sh", self.native_dir, "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.service_files(), [])

    def test_other_dir_gets_no_watchdog_service_but_is_enforced_once(self):
        other_dir = os.path.join(self.home, "somewhere-else")

        result = self.run_script("install-or-update.sh", other_dir, "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.service_files(), [])
        self.assertEqual(self.settings_of(other_dir), {"attribution": {"commit": "", "pr": ""}})

    def test_trailing_slash_does_not_make_native_dir_look_other(self):
        result = self.run_script("install-or-update.sh", self.native_dir + "/", "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.service_files(), [])

    def test_secure_ai_dir_gets_no_watchdog_service(self):
        result = self.run_script("install-or-update.sh", self.secure_ai_dir, "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.service_files(), [])
        self.assertFalse(os.path.exists(self.service_calls), "the service manager must not be called")
        self.assertIn("No watchdog", result.stdout)

    def test_secure_ai_dir_still_gets_its_customizations_applied_once(self):
        self.run_script("install-or-update.sh", self.secure_ai_dir, "no-attribution")

        self.assertEqual(self.settings_of(self.secure_ai_dir), {"attribution": {"commit": "", "pr": ""}})

    def test_trailing_slash_does_not_make_secure_ai_dir_get_a_watchdog(self):
        result = self.run_script("install-or-update.sh", self.secure_ai_dir + "/", "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.service_files(), [])

    def test_uninstall_of_secure_ai_dir_strips_the_keys_without_touching_the_service_manager_to_reload(self):
        self.run_script("install-or-update.sh", self.secure_ai_dir, "no-attribution", "statusline")

        result = self.run_script("uninstall.sh", self.secure_ai_dir, "no-attribution")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("attribution", self.settings_of(self.secure_ai_dir))
        self.assertNotIn("service files missing", result.stderr)

    def test_full_uninstall_of_secure_ai_dir_leaves_the_native_dirs_watchdog_in_place(self):
        self.run_script("install-or-update.sh", self.native_dir, "no-attribution")
        self.run_script("install-or-update.sh", self.secure_ai_dir, "no-attribution")
        native_service_files = sorted(self.service_files())

        result = self.run_script("uninstall.sh", self.secure_ai_dir)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(self.service_files()), native_service_files)
        self.assertNotIn("Unloaded", result.stdout)

    def test_status_of_secure_ai_dir_does_not_warn_about_a_missing_watchdog(self):
        self.run_script("install-or-update.sh", self.secure_ai_dir, "no-attribution")

        result = self.run_script("status.sh", self.secure_ai_dir)

        self.assertNotIn("not loaded", result.stderr)
        self.assertNotIn("service file missing", result.stderr)


if __name__ == "__main__":
    unittest.main()
