#!/usr/bin/env python3
"""Unit tests for the statusline host (customizations/statusline/bin/statusline-command.sh).

Each test builds a throwaway install dir (bin/ + resources/<name>/) and copies
the real host script into it, then registers fake segment executables via
statusline-segment.json manifests — no real customization or install-or-update.sh
involved, per the contract in customizations/statusline/docs/statusline-segments.md.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
HOST_SCRIPT = os.path.join(REPO_DIR, "customizations", "statusline", "bin", "statusline-command.sh")

SEPARATOR_CHAR = "│"  # │


class StatuslineHostTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.install_dir = self.tmp.name
        os.makedirs(os.path.join(self.install_dir, "bin"))
        os.makedirs(os.path.join(self.install_dir, "resources"))
        self.host_path = os.path.join(self.install_dir, "bin", "statusline-command.sh")
        shutil.copy2(HOST_SCRIPT, self.host_path)
        os.chmod(self.host_path, 0o755)

    def add_segment(self, name, order, script_body, executable=True):
        seg_dir = os.path.join(self.install_dir, "resources", name)
        os.makedirs(seg_dir, exist_ok=True)
        script_path = os.path.join(seg_dir, "segment.sh")
        with open(script_path, "w", encoding="utf-8") as handle:
            handle.write("#!/usr/bin/env bash\n" + script_body)
        os.chmod(script_path, 0o755 if executable else 0o644)
        manifest = {"order": order, "command": script_path}
        with open(os.path.join(seg_dir, "statusline-segment.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)

    def run_host(self, payload="{}"):
        return subprocess.run([self.host_path], input=payload, capture_output=True, text=True)

    def test_no_segments_installed_is_an_empty_status_line(self):
        result = self.run_host()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_segments_are_ordered_left_to_right(self):
        self.add_segment("second", 20, 'printf "B"\n')
        self.add_segment("first", 10, 'printf "A"\n')
        result = self.run_host()
        self.assertLess(result.stdout.index("A"), result.stdout.index("B"))

    def test_ties_break_by_directory_name(self):
        self.add_segment("zzz", 10, 'printf "Z"\n')
        self.add_segment("aaa", 10, 'printf "A"\n')
        result = self.run_host()
        self.assertLess(result.stdout.index("A"), result.stdout.index("Z"))

    def test_separator_appears_only_between_two_nonempty_segments(self):
        self.add_segment("a", 10, 'printf "A"\n')
        self.add_segment("b", 20, 'printf "B"\n')
        result = self.run_host()
        self.assertEqual(result.stdout.count(SEPARATOR_CHAR), 1)

    def test_empty_output_segment_is_omitted_without_a_stray_separator(self):
        self.add_segment("a", 10, 'printf "A"\n')
        self.add_segment("silent", 20, 'true\n')
        self.add_segment("c", 30, 'printf "C"\n')
        result = self.run_host()
        self.assertNotIn("silent", result.stdout)
        self.assertEqual(result.stdout.count(SEPARATOR_CHAR), 1)

    def test_failing_segment_is_replaced_by_a_marker(self):
        self.add_segment("broken", 10, "exit 1\n")
        result = self.run_host()
        self.assertIn("broken!", result.stdout)

    def test_non_executable_command_is_replaced_by_a_marker(self):
        self.add_segment("notexec", 10, 'printf "should not run"\n', executable=False)
        result = self.run_host()
        self.assertIn("notexec!", result.stdout)
        self.assertNotIn("should not run", result.stdout)

    def test_missing_command_is_replaced_by_a_marker(self):
        seg_dir = os.path.join(self.install_dir, "resources", "ghost")
        os.makedirs(seg_dir)
        manifest = {"order": 10, "command": os.path.join(seg_dir, "does-not-exist.sh")}
        with open(os.path.join(seg_dir, "statusline-segment.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)
        result = self.run_host()
        self.assertIn("ghost!", result.stdout)

    def test_relative_command_resolves_against_the_shared_bin_dir(self):
        # Manifests declare a bare filename (not an absolute, install-time
        # path) so segment resolution stays correct after ~/.claude is
        # mounted under a different $HOME, e.g. inside a container.
        script_path = os.path.join(self.install_dir, "bin", "relative-segment.sh")
        with open(script_path, "w", encoding="utf-8") as handle:
            handle.write("#!/usr/bin/env bash\nprintf 'R'\n")
        os.chmod(script_path, 0o755)

        seg_dir = os.path.join(self.install_dir, "resources", "relative")
        os.makedirs(seg_dir)
        manifest = {"order": 10, "command": "relative-segment.sh"}
        with open(os.path.join(seg_dir, "statusline-segment.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle)

        result = self.run_host()
        self.assertEqual(result.stdout, "R", result.stderr)

    def test_original_stdin_payload_is_forwarded_unchanged(self):
        self.add_segment(
            "echoer", 10,
            'input=$(cat); printf "%s" "$input" | jq -r ".model.display_name"\n',
        )
        payload = json.dumps({"model": {"display_name": "Opus 5"}})
        result = self.run_host(payload=payload)
        self.assertIn("Opus 5", result.stdout)


if __name__ == "__main__":
    unittest.main()
