#!/usr/bin/env python3
"""Unit tests for the post-install hook support in
scripts/install-or-update.sh: a customization's optional bin/post-install.sh
runs once, right after that customization's own files are installed, with
INSTALL_DIR as $1 - see customizations/README.md's "Install-time hooks".

Runs the real install-or-update.sh against tests/fixtures/customizations
with CLAUDE_DIR and HOME pointed at disposable temp dirs, and launchctl/systemctl
replaced by stubs on PATH, so nothing here touches the real repo customizations,
~/.claude or the user's launchd/systemd services.
"""

import os
import subprocess
import tempfile
import unittest

from sandbox_env import sandboxed_environ

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
INSTALL_SCRIPT = os.path.join(REPO_DIR, "scripts", "install-or-update.sh")
UNINSTALL_SCRIPT = os.path.join(REPO_DIR, "scripts", "uninstall.sh")
FIXTURES_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "fixtures", "customizations")


class PostInstallHookTestCase(unittest.TestCase):
    def setUp(self):
        self.claude_dir = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.claude_dir]))
        self.install_dir = os.path.join(self.claude_dir, "customizations", "custom-claude-code-settings")
        self.home = tempfile.mkdtemp()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", self.home]))
        self.stub_bin = self.make_service_manager_stubs()

    def make_service_manager_stubs(self):
        """launchctl accepts everything; systemctl reports no user manager, which
        install-or-update.sh tolerates with a warning."""
        stub_bin = os.path.join(self.home, "stub-bin")
        os.makedirs(stub_bin)
        for command, exit_code in (("launchctl", 0), ("systemctl", 1)):
            stub = os.path.join(stub_bin, command)
            with open(stub, "w", encoding="utf-8") as handle:
                handle.write("#!/bin/sh\nexit {}\n".format(exit_code))
            os.chmod(stub, 0o755)
        return stub_bin

    def run_script(self, script, *names):
        env = sandboxed_environ(self.home)
        env["CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS"] = FIXTURES_DIR
        env["CLAUDE_DIR"] = self.claude_dir
        env["PATH"] = self.stub_bin + os.pathsep + env["PATH"]
        return subprocess.run(
            ["bash", script, *names], env=env, capture_output=True, text=True
        )

    def run_install(self, *names):
        return self.run_script(INSTALL_SCRIPT, *names)

    def test_hook_runs_with_install_dir_as_first_argument(self):
        result = self.run_install("with-post-install-hook")
        self.assertEqual(result.returncode, 0, result.stderr)

        marker = os.path.join(self.install_dir, "post-install-hook-received-install-dir.txt")
        self.assertTrue(os.path.isfile(marker), result.stderr)
        with open(marker, encoding="utf-8") as handle:
            self.assertEqual(handle.read(), self.install_dir)

    def test_hook_is_not_flattened_into_the_shared_bin_dir(self):
        result = self.run_install("with-post-install-hook")
        self.assertEqual(result.returncode, 0, result.stderr)

        hook_in_shared_bin = os.path.join(self.install_dir, "bin", "post-install.sh")
        self.assertFalse(os.path.exists(hook_in_shared_bin))

    def test_failing_hook_is_a_warning_not_a_fatal_error(self):
        result = self.run_install("with-failing-post-install-hook")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("post-install hook failed", result.stderr)

        manifest = os.path.join(self.install_dir, "resources", "installed.json")
        self.assertTrue(os.path.isfile(manifest))

    def test_uninstall_does_not_report_the_hook_as_a_removed_bin_file(self):
        self.run_install("with-post-install-hook")

        result = self.run_script(UNINSTALL_SCRIPT, "with-post-install-hook")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("post-install.sh", result.stdout)

    def test_customization_without_a_hook_installs_without_error(self):
        result = self.run_install("standalone")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
