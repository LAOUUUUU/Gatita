"""Tests for the version rules in release.py. Run: python3 -m unittest discover -s scripts"""

import unittest

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


if __name__ == "__main__":
    unittest.main()
