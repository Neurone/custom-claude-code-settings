#!/usr/bin/env python3
"""Unit tests for sandbox_env.sandboxed_environ, which keeps the scripts under
test away from the real user's files."""

import os
import unittest
from unittest import mock

from sandbox_env import sandboxed_environ


class SandboxedEnvironTestCase(unittest.TestCase):
    def test_home_is_the_given_directory(self):
        with mock.patch.dict(os.environ, {"HOME": "/real/home"}):
            self.assertEqual(sandboxed_environ("/tmp/throwaway")["HOME"], "/tmp/throwaway")

    def test_xdg_config_home_of_the_host_is_not_inherited(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/real/home/.config"}):
            self.assertNotIn("XDG_CONFIG_HOME", sandboxed_environ("/tmp/throwaway"))

    def test_requested_variables_are_dropped(self):
        with mock.patch.dict(os.environ, {"CLAUDE_DIR": "/real/claude"}):
            self.assertNotIn("CLAUDE_DIR", sandboxed_environ("/tmp/throwaway", dropped=("CLAUDE_DIR",)))

    def test_other_variables_are_kept(self):
        with mock.patch.dict(os.environ, {"PATH": "/usr/bin"}):
            self.assertEqual(sandboxed_environ("/tmp/throwaway")["PATH"], "/usr/bin")

    def test_process_environment_is_left_untouched(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/real/home/.config"}):
            sandboxed_environ("/tmp/throwaway")
            self.assertEqual(os.environ["XDG_CONFIG_HOME"], "/real/home/.config")


if __name__ == "__main__":
    unittest.main()
