#!/usr/bin/env python3
"""Unit tests for the dependency-resolution and install-manifest helpers in
scripts/lib/common.sh.

common.sh is meant to be sourced, not run, so each test sources it in a bash
subprocess and calls the helper directly. CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS
points at tests/fixtures/customizations instead of the repo's own
customizations/, and CLAUDE_DIR at a disposable temp dir, so nothing here
touches the real repo customizations or ~/.claude.
"""

import os
import subprocess
import tempfile
import unittest

REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
COMMON_SH = os.path.join(REPO_DIR, "scripts", "lib", "common.sh")
FIXTURES_DIR = os.path.join(os.path.dirname(os.path.realpath(__file__)), "fixtures", "customizations")


def run_bash(snippet, claude_dir=None):
    env = dict(os.environ)
    env["CUSTOM_CLAUDE_SETTINGS_CUSTOMIZATIONS"] = FIXTURES_DIR
    env["CLAUDE_DIR"] = claude_dir or tempfile.mkdtemp()
    script = 'source "{}"\n{}'.format(COMMON_SH, snippet)
    return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)


class ResolveDependenciesTestCase(unittest.TestCase):
    def test_transitive_closure_in_topological_order(self):
        result = run_bash("resolve_dependencies top")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["base", "mid", "top"])

    def test_dedupes_a_dependency_shared_by_multiple_requested_names(self):
        result = run_bash("resolve_dependencies top mid base")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["base", "mid", "top"])

    def test_customization_with_no_requires_resolves_to_itself(self):
        result = run_bash("resolve_dependencies standalone")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["standalone"])

    def test_zero_requested_names_resolves_to_nothing_without_error(self):
        result = run_bash("resolve_dependencies; echo rc=$?")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "rc=0")

    def test_unresolvable_requires_target_dies(self):
        result = run_bash("resolve_dependencies needs-missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown customization", result.stderr)
        self.assertIn("does-not-exist", result.stderr)

    def test_unknown_requested_name_dies(self):
        result = run_bash("resolve_dependencies totally-bogus")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown customization: totally-bogus", result.stderr)

    def test_dependency_cycle_dies(self):
        result = run_bash("resolve_dependencies cyclic-a")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cycle", result.stderr)


class MetadataHelpersTestCase(unittest.TestCase):
    def test_description_from_meta_file(self):
        result = run_bash("customization_description top")
        self.assertEqual(result.stdout.strip(), "Top of the chain")

    def test_description_defaults_to_empty_without_a_meta_file(self):
        result = run_bash("customization_description standalone; echo rc=$?")
        self.assertEqual(result.stdout, "rc=0\n")

    def test_requires_from_meta_file(self):
        result = run_bash("customization_requires top")
        self.assertEqual(result.stdout.split(), ["mid"])

    def test_requires_defaults_to_empty_without_a_meta_file(self):
        result = run_bash("customization_requires standalone; echo rc=$?")
        self.assertEqual(result.stdout.strip(), "rc=0")


class ListContainsTestCase(unittest.TestCase):
    def test_item_present(self):
        result = run_bash("list_contains b a b c && echo yes || echo no")
        self.assertEqual(result.stdout.strip(), "yes")

    def test_item_absent(self):
        result = run_bash("list_contains z a b c && echo yes || echo no")
        self.assertEqual(result.stdout.strip(), "no")

    def test_empty_candidate_list(self):
        result = run_bash("list_contains z && echo yes || echo no")
        self.assertEqual(result.stdout.strip(), "no")


class InstallManifestTestCase(unittest.TestCase):
    def test_write_then_read_roundtrip(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            result = run_bash("write_install_manifest base mid top", claude_dir=claude_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = run_bash("installed_customizations", claude_dir=claude_dir)
            self.assertEqual(result.stdout.split(), ["base", "mid", "top"])

    def test_writing_zero_names_produces_an_empty_manifest(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            run_bash("write_install_manifest", claude_dir=claude_dir)
            result = run_bash("installed_customizations; echo rc=$?", claude_dir=claude_dir)
            self.assertEqual(result.stdout.strip(), "rc=0")

    def test_missing_manifest_reads_as_empty_without_error(self):
        with tempfile.TemporaryDirectory() as claude_dir:
            result = run_bash("installed_customizations; echo rc=$?", claude_dir=claude_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "rc=0")


if __name__ == "__main__":
    unittest.main()
