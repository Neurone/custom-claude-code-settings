#!/usr/bin/env python3
"""Unit tests for the interactive "which Claude Code config dir?" question
(scripts/lib/select-claude-dir.sh), asked by the installer before scripts/lib/common.sh derives
every path from CLAUDE_DIR.

The script is sourced in a bash subprocess whose stdin is either a pseudo-terminal
carrying the typed answer (interactive) or /dev/null (not interactive). HOME always
points at a disposable temp dir, so nothing here touches the real ~/.claude.
"""

import os
import pty
import subprocess
import tempfile
import unittest

from sandbox_env import sandboxed_environ

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
SELECT_SH = os.path.join(REPO_DIR, "scripts", "lib", "select-claude-dir.sh")
COMMON_SH = os.path.join(REPO_DIR, "scripts", "lib", "common.sh")

DIR_OVERRIDES = ("CLAUDE_DIR", "CLAUDE_CONFIG_DIR", "ASK_CLAUDE_DIR")


class SelectClaudeDirTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = os.path.join(self.tmp.name, "home")
        os.makedirs(self.home)

    def env(self, **overrides):
        env = sandboxed_environ(self.home, dropped=DIR_OVERRIDES)
        env.update(overrides)
        return env

    def run_script(self, stdin, **overrides):
        script = 'source "{}"\nsource "{}"\nprintf %s "$CLAUDE_DIR"'.format(SELECT_SH, COMMON_SH)
        return subprocess.run(
            ["bash", "-c", script], stdin=stdin, env=self.env(**overrides), capture_output=True, text=True
        )

    def answer(self, typed, **overrides):
        """Run as the installer does (ASK_CLAUDE_DIR=1) with a terminal on stdin
        that has `typed` waiting to be read."""
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        os.write(master, typed.encode())
        return self.run_script(slave, ASK_CLAUDE_DIR="1", **overrides)

    def test_no_question_unless_the_caller_asks_for_one(self):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        os.write(master, b"/ignored\n")

        result = self.run_script(slave)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.path.join(self.home, ".claude"))
        self.assertEqual(result.stderr, "")

    def test_empty_answer_selects_the_home_claude_dir(self):
        result = self.answer("\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.path.join(self.home, ".claude"))

    def test_typed_absolute_path_is_used(self):
        chosen = os.path.join(self.tmp.name, "secure-ai-config")

        result = self.answer(chosen + "\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, chosen)

    def test_leading_tilde_expands_to_home(self):
        result = self.answer("~/.secure-ai/claude-code/config\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.path.join(self.home, ".secure-ai", "claude-code", "config"))

    def test_relative_path_is_rejected(self):
        result = self.answer("some/where\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("absolute", result.stderr)

    def test_closed_input_is_rejected_instead_of_guessing(self):
        result = self.answer("\x04")  # Ctrl-D at an empty prompt

        self.assertNotEqual(result.returncode, 0)

    def test_the_question_names_the_default(self):
        result = self.answer("\n")

        self.assertIn("~/.claude", result.stderr)

    def test_no_question_without_a_terminal(self):
        result = self.run_script(subprocess.DEVNULL)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, os.path.join(self.home, ".claude"))
        self.assertEqual(result.stderr, "")

    def test_claude_dir_override_skips_the_question(self):
        chosen = os.path.join(self.tmp.name, "explicit")

        result = self.answer("/ignored\n", CLAUDE_DIR=chosen)

        self.assertEqual(result.stdout, chosen)
        self.assertEqual(result.stderr, "")

    def test_claude_config_dir_override_skips_the_question(self):
        chosen = os.path.join(self.tmp.name, "sandbox-config")

        result = self.answer("/ignored\n", CLAUDE_CONFIG_DIR=chosen)

        self.assertEqual(result.stdout, chosen)
        self.assertEqual(result.stderr, "")

    def write_probe(self, exit_code=0):
        """A script that sources select-claude-dir.sh and reports the dir and
        arguments it was started with; returns its path."""
        probe = os.path.join(self.tmp.name, "probe.sh")
        with open(probe, "w", encoding="utf-8") as handle:
            handle.write(
                '#!/usr/bin/env bash\nsource "{}"\nsource "{}"\necho "$CLAUDE_DIR $*"\nexit {}\n'.format(
                    SELECT_SH, COMMON_SH, exit_code
                )
            )
        os.chmod(probe, 0o755)
        return probe

    def run_each_dir(self, stdin=subprocess.DEVNULL, exit_code=0, **overrides):
        """Run the probe and return the completed process."""
        probe = self.write_probe(exit_code)
        result = subprocess.run(
            [probe, "alpha", "beta"], stdin=stdin, env=self.env(**overrides), capture_output=True, text=True
        )
        return result

    def make_dir(self, *parts):
        path = os.path.join(self.home, *parts)
        os.makedirs(path)
        return path

    def test_existing_home_claude_dir_is_used_without_asking(self):
        claude_dir = self.make_dir(".claude")
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)

        result = self.run_each_dir(stdin=slave)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [claude_dir + " alpha beta"])
        self.assertNotIn("config dir [", result.stderr)

    def test_existing_secure_ai_config_dir_alone_is_used(self):
        secure_ai_dir = self.make_dir(".secure-ai", "claude-code", "config")

        result = self.run_each_dir()

        self.assertEqual(result.stdout.splitlines(), [secure_ai_dir + " alpha beta"])

    def test_every_existing_config_dir_gets_its_own_run_with_the_same_arguments(self):
        claude_dir = self.make_dir(".claude")
        secure_ai_dir = self.make_dir(".secure-ai", "claude-code", "config")

        result = self.run_each_dir()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(), [claude_dir + " alpha beta", secure_ai_dir + " alpha beta"]
        )

    def test_each_dir_is_rerun_when_the_script_was_started_by_bare_file_name(self):
        claude_dir = self.make_dir(".claude")
        secure_ai_dir = self.make_dir(".secure-ai", "claude-code", "config")
        probe = self.write_probe()

        result = subprocess.run(
            ["bash", os.path.basename(probe), "alpha"],
            cwd=os.path.dirname(probe),
            stdin=subprocess.DEVNULL,
            env=self.env(),
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [claude_dir + " alpha", secure_ai_dir + " alpha"])

    def test_override_restricts_the_run_to_that_dir_even_if_others_exist(self):
        self.make_dir(".claude")
        self.make_dir(".secure-ai", "claude-code", "config")
        chosen = os.path.join(self.tmp.name, "only-this")

        result = self.run_each_dir(CLAUDE_CONFIG_DIR=chosen)

        self.assertEqual(result.stdout.splitlines(), [chosen + " alpha beta"])

    def test_failure_in_one_dir_does_not_skip_the_other_and_fails_the_whole_run(self):
        self.make_dir(".claude")
        self.make_dir(".secure-ai", "claude-code", "config")

        result = self.run_each_dir(exit_code=3)

        self.assertEqual(len(result.stdout.splitlines()), 2)
        self.assertNotEqual(result.returncode, 0)

    def test_trailing_slash_does_not_change_whether_the_dir_gets_a_watchdog(self):
        native = os.path.join(self.home, ".claude")
        script = 'source "{}"\nprintf "%s " "$CLAUDE_DIR"\nwatchdog_wanted && printf yes || printf no'.format(COMMON_SH)

        def dir_and_watchdog(claude_dir):
            result = subprocess.run(
                ["bash", "-c", script], env=self.env(CLAUDE_DIR=claude_dir), capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

        self.assertEqual(dir_and_watchdog(native + "/"), native + " yes")
        self.assertEqual(dir_and_watchdog(native + "//"), native + " yes")


if __name__ == "__main__":
    unittest.main()
