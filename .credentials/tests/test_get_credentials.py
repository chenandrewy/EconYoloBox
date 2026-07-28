#!/usr/bin/env python3
# Run:     python3 .credentials/tests/test_get_credentials.py
# Inputs:  Temporary credential files created by each test
# Outputs: unittest results; no project files are modified

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "get-credentials.py"


def load_module():
    spec = importlib.util.spec_from_loader(
        "get_credentials_under_test",
        importlib.machinery.SourceFileLoader(
            "get_credentials_under_test",
            str(MODULE_PATH),
        ),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CredentialResolutionTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.secret_file = Path(self.temp_dir.name) / "credentials.env"
        self.module._MOUNTED_CREDENTIALS_FILE = self.secret_file

    def test_environment_overrides_mounted_file(self):
        self.secret_file.write_text("TEST_TOKEN=mounted\n", encoding="utf-8")
        with mock.patch.dict(os.environ, {"TEST_TOKEN": "environment"}):
            value = self.module.get_credential("TEST_TOKEN", "test-token")
        self.assertEqual(value, "environment")

    def test_reads_values_from_mounted_file(self):
        self.secret_file.write_text(
            "# comment\n"
            "TEST_TOKEN=value=with=equals\n"
            "MALFORMED\n",
            encoding="utf-8",
        )
        with mock.patch.dict(os.environ, {}, clear=True):
            value = self.module.get_credential("TEST_TOKEN", "test-token")
        self.assertEqual(value, "value=with=equals")

    def test_reads_file_afresh_so_updates_are_visible(self):
        self.secret_file.write_text("TEST_TOKEN=mounted\n", encoding="utf-8")
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                self.module.get_credential("TEST_TOKEN", "test-token"),
                "mounted",
            )
            self.secret_file.write_text("", encoding="utf-8")
            with mock.patch.object(
                self.module,
                "_read_from_store",
                return_value="",
            ):
                self.assertEqual(
                    self.module.get_credential("TEST_TOKEN", "test-token"),
                    "",
                )

    def test_falls_back_to_host_store_when_file_is_absent(self):
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch.object(
                self.module,
                "_read_from_store",
                return_value="host-value",
            ),
        ):
            value = self.module.get_credential("TEST_TOKEN", "test-token")
        self.assertEqual(value, "host-value")


if __name__ == "__main__":
    unittest.main()
