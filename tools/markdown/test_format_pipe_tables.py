#!/usr/bin/env python3
"""Run: python3 -m unittest discover -s /yolobox/tools/markdown -v

Inputs: formatter module and temporary Markdown fixtures.
Outputs: unittest results; temporary files are cleaned up automatically.
"""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("format-pipe-tables.py")
SPEC = importlib.util.spec_from_file_location("formatter", SCRIPT)
formatter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(formatter)


class FormatterTests(unittest.TestCase):
    def test_alignment_and_idempotence(self):
        source = "Name | Qty | Mid\n--- | ---: | :---:\nx | 12 | y\n"
        expected = ("| Name |  Qty |  Mid  |\n"
                    "| ---- | ---: | :---: |\n"
                    "| x    |   12 |   y   |\n")
        self.assertEqual(formatter.format_markdown(source), (expected, []))
        self.assertEqual(formatter.format_markdown(expected), (expected, []))

    def test_escaped_pipes_and_backslashes(self):
        self.assertEqual(formatter.split_row(r"| `a\|b` | c\\ |"), [r"`a\|b`", r"c\\"])
        self.assertEqual(formatter.split_row(r"a | b\|"), ["a", r"b\|"])
        source = "| A | B |\n|---|---|\n| `a\\|b` | c |\n"
        formatted, warnings = formatter.format_markdown(source)
        self.assertFalse(warnings)
        self.assertIn("`a\\|b`", formatted)
        self.assertEqual(formatter.format_markdown(formatted)[0], formatted)

    def test_fences_and_non_tables(self):
        table = "| A | B |\n|---|---|\n|x|y|\n"
        source = ("````markdown\n" + table + "```\n" + table + "````\n"
                  "~~~\n" + table + "~~~\n"
                  "    | A | B |\n    |---|---|\n"
                  "> | A | B |\n> |---|---|\n"
                  "A | B\nordinary prose\n")
        self.assertEqual(formatter.format_markdown(source), (source, []))

    def test_ragged_table_is_unchanged(self):
        source = "Intro\n\n| A | B |\n|---|---|\n|x|y|z|\n"
        result, warnings = formatter.format_markdown(source)
        self.assertEqual(result, source)
        self.assertEqual(warnings[0][0], 3)

    def test_unicode_and_line_endings(self):
        source = "|A|B|\r\n|---|---|\r\n|界界|e\u0301|"
        expected = "| A    | B   |\r\n| ---- | --- |\r\n| 界界 | e\u0301   |"
        self.assertEqual(formatter.format_markdown(source), (expected, []))

    def test_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.md"
            original = b"\xef\xbb\xbf|a|b|\r\n|---|---|\r\n|1|2|"
            path.write_bytes(original)

            def run(*args):
                return subprocess.run([sys.executable, str(SCRIPT), *args, str(path)],
                                      capture_output=True)

            self.assertEqual(run("--check").returncode, 1)
            preview = run()
            self.assertEqual(preview.returncode, 0)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(run("--in-place").returncode, 0)
            self.assertEqual(path.read_bytes(), preview.stdout)
            self.assertTrue(preview.stdout.startswith(b"\xef\xbb\xbf"))
            self.assertEqual(run("--check").returncode, 0)
            self.assertEqual(run("--in-place").returncode, 0)
            self.assertEqual(path.read_bytes(), preview.stdout)


if __name__ == "__main__":
    unittest.main()
