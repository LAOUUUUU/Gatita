"""Tests for release.py: the version rules and the progress line. Run: python3 -m unittest discover -s scripts"""

import io
import sys
import tempfile
import unittest
from pathlib import Path

import release

PROJECT = """
\t\t\t\tCURRENT_PROJECT_VERSION = 3;
\t\t\t\tMARKETING_VERSION = 0.0.3;
\t\t\t\tCURRENT_PROJECT_VERSION = 3;
\t\t\t\tMARKETING_VERSION = 0.0.3;
"""


class VersionRules(unittest.TestCase):
    def test_reads_the_version_and_build(self):
        self.assertEqual(release.read_project_version(PROJECT), ("0.0.3", 3))

    def test_writes_every_target(self):
        updated = release.write_project_version(PROJECT, "0.0.4", 4)
        self.assertEqual(release.read_project_version(updated), ("0.0.4", 4))
        self.assertEqual(updated.count("MARKETING_VERSION = 0.0.4;"), 2)

    def test_targets_that_disagree_are_refused(self):
        mixed = PROJECT.replace("MARKETING_VERSION = 0.0.3;", "MARKETING_VERSION = 0.0.2;", 1)
        with self.assertRaises(SystemExit):
            release.read_project_version(mixed)

    def test_a_version_has_three_numbers(self):
        for bad in ["0.0", "0.0.3.1", "0.0.3-beta", "v0.0.4", ""]:
            with self.assertRaises(SystemExit, msg=bad):
                release.check_version(bad)
        release.check_version("0.0.4")

    def test_a_bump_must_go_up(self):
        with self.assertRaises(SystemExit):
            release.check_version("0.0.3", current="0.0.3")
        with self.assertRaises(SystemExit):
            release.check_version("0.0.2", current="0.0.3")
        release.check_version("0.0.10", current="0.0.9")

    def test_numbers_compare_as_numbers(self):
        self.assertGreater(release.parse("0.0.10"), release.parse("0.0.9"))
        self.assertGreater(release.parse("0.1.0"), release.parse("0.0.99"))


class ProgressLine(unittest.TestCase):
    def test_a_bar_fills_with_the_fraction(self):
        self.assertEqual(release.bar(0, 10), "░" * 10)
        self.assertEqual(release.bar(0.5, 10), "█" * 5 + "░" * 5)
        self.assertEqual(release.bar(1, 10), "█" * 10)
        self.assertEqual(release.bar(1.7, 4), "█" * 4)
        self.assertEqual(release.bar(-1, 4), "░" * 4)

    def test_times_read_as_minutes_and_seconds(self):
        self.assertEqual(release.duration(0), "0:00")
        self.assertEqual(release.duration(65.4), "1:05")
        self.assertEqual(release.duration(3600), "60:00")

    def test_a_step_goes_by_its_log_and_its_time(self):
        self.assertEqual(release.step_fraction(0, 100, seconds=0, usual_seconds=100), 0)
        self.assertEqual(release.step_fraction(50, 100, seconds=50, usual_seconds=100), 0.5)
        self.assertAlmostEqual(release.step_fraction(100, 100, seconds=0, usual_seconds=100), 0.495,
                               msg="a burst of log lines alone moves it only half way")
        self.assertEqual(release.step_fraction(0, 0, seconds=5, usual_seconds=10), 0.5, "no log: time alone")
        self.assertEqual(release.step_fraction(0, 0, seconds=0, usual_seconds=0), 0)

    def test_a_step_never_looks_finished_before_it_ends(self):
        self.assertEqual(release.step_fraction(500, 100, seconds=500, usual_seconds=100), 0.99)

    def test_steps_count_by_how_long_they_usually_take(self):
        weights = [100, 300]
        self.assertEqual(release.overall(weights, step=0, fraction=0.5), 0.125)
        self.assertEqual(release.overall(weights, step=1, fraction=0), 0.25)
        self.assertEqual(release.overall(weights, step=2, fraction=0), 1.0)

    def test_the_line_names_the_step(self):
        self.assertEqual(release.status_line(2, 4, "Mac app", 0.5, 75, width=10),
                         "Step 2 of 4  Mac app  █████░░░░░  50%  1:15")

    def test_the_last_run_sets_what_to_expect(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "steps.json"
            self.assertEqual(release.load_history(path), {})
            self.assertEqual(release.expected({}, "mac"), release.USUAL_STEPS["mac"])
            release.remember_step(path, "mac", lines=2090, seconds=222)
            history = release.load_history(path)
            self.assertEqual(release.expected(history, "mac"), {"lines": 2090, "seconds": 222})
            path.write_text("not json", encoding="utf-8")
            self.assertEqual(release.load_history(path), {})


class ProgressRun(unittest.TestCase):
    def run_steps(self, script: str) -> tuple[str, Path]:
        folder = Path(tempfile.mkdtemp())
        shown = io.StringIO()
        progress = release.Progress([("mac", "Mac app")], folder / "steps.json", stream=shown)
        progress.run("mac", [sys.executable, "-c", script], folder / "mac.log")
        progress.finish()
        return shown.getvalue(), folder

    def test_a_step_writes_its_log_and_reaches_100_percent(self):
        shown, folder = self.run_steps("print('one'); print('two'); print('three')")
        self.assertEqual((folder / "mac.log").read_text(encoding="utf-8"), "one\ntwo\nthree\n")
        self.assertIn("Step 1 of 1  Mac app", shown)
        self.assertIn("100%", shown)
        self.assertEqual(release.load_history(folder / "steps.json")["mac"]["lines"], 3)

    def test_a_failed_step_stops_with_its_last_lines(self):
        with self.assertRaises(SystemExit) as stopped:
            self.run_steps("import sys; print('error: it broke'); sys.exit(3)")
        self.assertIn("error: it broke", str(stopped.exception))


if __name__ == "__main__":
    unittest.main()
