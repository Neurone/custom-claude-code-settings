#!/usr/bin/env python3
"""Unit tests for the hbar-addicted fetcher and segment.

No real network: a fake curl is prepended to PATH for the fetcher tests,
returning CoinMarketCap-shaped chart JSON (see chart_response()). Both
scripts derive their own install dir from their own location
($(dirname "$0")/..), so each test copies the real script into a throwaway
bin/ and works from there.
"""

import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*m")


def strip_ansi(text):
    return ANSI_ESCAPE_RE.sub("", text)


REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
HBAR_BIN_DIR = os.path.join(REPO_DIR, "customizations", "hbar-addicted", "bin")
FETCHER = os.path.join(HBAR_BIN_DIR, "hbar-price-fetch.sh")
SEGMENT = os.path.join(HBAR_BIN_DIR, "hbar-segment.sh")


def chart_response(points, error_code="0"):
    """Build a CoinMarketCap chart-API JSON body from (epoch, price) pairs."""
    points_json = ",".join(
        '{{"s":"{}","v":[{}],"c":{{}}}}'.format(epoch, price) for epoch, price in points
    )
    return '{{"data":{{"points":[{}]}},"status":{{"error_code":"{}"}}}}'.format(
        points_json, error_code
    )


class HbarPriceFetchTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.install_dir = os.path.join(self.tmp.name, "install")
        os.makedirs(os.path.join(self.install_dir, "bin"))
        self.fetcher = os.path.join(self.install_dir, "bin", "hbar-price-fetch.sh")
        shutil.copy2(FETCHER, self.fetcher)
        os.chmod(self.fetcher, 0o755)
        self.fake_bin = os.path.join(self.tmp.name, "fakebin")
        os.makedirs(self.fake_bin)
        self.history_path = os.path.join(self.install_dir, "cache", "hbar-addicted", "price-history.tsv")
        self.log_path = os.path.join(self.install_dir, "logs", "hbar-addicted", "price.log")

    def set_fake_curl(self, body):
        path = os.path.join(self.fake_bin, "curl")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("#!/usr/bin/env bash\n" + body + "\n")
        os.chmod(path, 0o755)

    def set_fake_curl_json(self, response_json):
        # Heredoc with a quoted delimiter so bash doesn't try to expand
        # anything ($, braces, ...) inside the JSON body.
        self.set_fake_curl("cat <<'EOF'\n" + response_json + "\nEOF")

    def run_fetch(self):
        env = dict(os.environ)
        env["PATH"] = self.fake_bin + os.pathsep + env["PATH"]
        return subprocess.run([self.fetcher], env=env, capture_output=True, text=True)

    def read_history(self):
        if not os.path.exists(self.history_path):
            return []
        with open(self.history_path, encoding="utf-8") as handle:
            return [line.rstrip("\n").split("\t") for line in handle if line.strip()]

    def read_log(self):
        if not os.path.exists(self.log_path):
            return ""
        with open(self.log_path, encoding="utf-8") as handle:
            return handle.read()

    def test_valid_response_replaces_history_with_all_points(self):
        # Compare parsed floats, not raw strings: jq's number-to-string
        # formatting differs across versions (e.g. jq 1.6 prints "0.0700" as
        # "0.07"), which is irrelevant here since hbar-segment.sh only ever
        # reads these values back through awk's own float parsing.
        now = int(time.time())
        points = [(now - 3600, "0.0700"), (now, "0.074696")]
        self.set_fake_curl_json(chart_response(points))
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        history = self.read_history()
        self.assertEqual([epoch for epoch, _ in history], [str(epoch) for epoch, _ in points])
        self.assertEqual([float(price) for _, price in history], [float(price) for _, price in points])

    def test_malformed_response_is_rejected_and_logged_without_touching_history(self):
        self.set_fake_curl('echo "not-json"')
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_history(), [])
        self.assertIn("malformed response", self.read_log())

    def test_api_error_code_is_rejected_and_logged_without_touching_history(self):
        self.set_fake_curl_json(chart_response([], error_code="400"))
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read_history(), [])
        self.assertIn("API error", self.read_log())

    def test_curl_failure_is_logged(self):
        self.set_fake_curl('echo "connection failed" >&2; exit 7')
        result = self.run_fetch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("curl failed (exit 7)", self.read_log())

    def test_points_older_than_24h_are_dropped(self):
        now = int(time.time())
        old_epoch = now - 100000  # > 24h
        points = [(old_epoch, "0.05"), (now, "0.08")]
        self.set_fake_curl_json(chart_response(points))
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        history = self.read_history()
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0][1], "0.08")

    def test_points_within_the_retention_margin_past_24h_are_kept(self):
        # hbar-segment.sh checks 24h coverage against its own (later) render
        # time, not this fetch's, so the retained history must reach a bit
        # past the 24h mark or the 24h change dashes out right after a fetch.
        now = int(time.time())
        margin_epoch = now - 86400 - 1000  # past 24h, within RETENTION_MARGIN_SECONDS
        points = [(margin_epoch, "0.05"), (now, "0.08")]
        self.set_fake_curl_json(chart_response(points))
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        history = self.read_history()
        self.assertEqual(len(history), 2)

    def test_stale_lock_is_cleared_and_fetch_proceeds(self):
        lock_dir = os.path.join(self.install_dir, "cache", "hbar-addicted", ".fetch.lock")
        os.makedirs(lock_dir)
        old_time = time.time() - 120  # > 60s stale threshold
        os.utime(lock_dir, (old_time, old_time))
        self.set_fake_curl_json(chart_response([(int(time.time()), "0.09")]))
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(os.path.isdir(lock_dir))
        self.assertEqual(self.read_history()[0][1], "0.09")

    def test_fresh_lock_blocks_the_fetch(self):
        lock_dir = os.path.join(self.install_dir, "cache", "hbar-addicted", ".fetch.lock")
        os.makedirs(lock_dir)
        self.set_fake_curl('echo "0.09"')
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_history(), [])


class HbarSegmentTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.install_dir = os.path.join(self.tmp.name, "install")
        os.makedirs(os.path.join(self.install_dir, "bin"))
        self.segment = os.path.join(self.install_dir, "bin", "hbar-segment.sh")
        shutil.copy2(SEGMENT, self.segment)
        os.chmod(self.segment, 0o755)
        # A no-op stand-in for the fetcher: the segment launches it in the
        # background whenever data is missing/stale, and it must never touch
        # the real network during a test.
        stub_fetcher = os.path.join(self.install_dir, "bin", "hbar-price-fetch.sh")
        with open(stub_fetcher, "w", encoding="utf-8") as handle:
            handle.write("#!/usr/bin/env bash\ntrue\n")
        os.chmod(stub_fetcher, 0o755)
        self.history_path = os.path.join(self.install_dir, "cache", "hbar-addicted", "price-history.tsv")
        os.makedirs(os.path.dirname(self.history_path))

    def write_history(self, samples):
        with open(self.history_path, "w", encoding="utf-8") as handle:
            for epoch, price in samples:
                handle.write("{}\t{}\n".format(epoch, price))

    def run_segment(self):
        return subprocess.run([self.segment], input="{}", capture_output=True, text=True)

    def test_no_history_at_all_is_rendered_as_na(self):
        result = self.run_segment()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("HBAR n/a", result.stdout)

    def test_single_sample_shows_a_dash_for_uncovered_windows(self):
        now = int(time.time())
        self.write_history([(now, "0.074696")])
        result = self.run_segment()
        output = strip_ansi(result.stdout)
        self.assertIn("HBAR $0.0747", output)
        self.assertIn("(1h)", output)
        self.assertIn("(24h)", output)
        self.assertIn("-", output)

    def test_1h_and_24h_changes_use_the_nearest_sample_to_each_window(self):
        now = int(time.time())
        self.write_history([
            (now - 86400, "0.0900"),  # 24h reference: price went down since then
            (now - 3600, "0.0700"),   # 1h reference: price went up since then
            (now, "0.0747"),
        ])
        result = self.run_segment()
        output = strip_ansi(result.stdout)
        self.assertIn("▲6.71% (1h)", output)
        self.assertIn("▼17.00% (24h)", output)

    def test_last_update_time_reflects_the_latest_cached_sample_even_when_stale(self):
        stale_epoch = int(time.time()) - 1200  # well past the old STALE threshold
        self.write_history([(stale_epoch, "0.0747")])
        result = self.run_segment()
        expected_time = time.strftime("@%H:%M", time.localtime(stale_epoch))
        self.assertIn(expected_time, strip_ansi(result.stdout))

    def test_last_update_time_is_formatted_as_hh_mm_for_todays_sample(self):
        now = int(time.time())
        self.write_history([(now, "0.0747")])
        result = self.run_segment()
        self.assertRegex(result.stdout, r"@\d{2}:\d{2}")


if __name__ == "__main__":
    unittest.main()
