#!/usr/bin/env python3
# Run:     python3 infra/credentials/tests/test_get_credentials.py
# Inputs:  Mocked environment and host store
# Outputs: unittest results; no project files are modified

import importlib.machinery
import importlib.util
import os
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

    def test_environment_comes_first(self):
        with (
            mock.patch.dict(os.environ, {"TEST_TOKEN": "environment"}),
            mock.patch.object(self.module, "_read_from_store", return_value="host-value") as store,
        ):
            value = self.module.get_credential("TEST_TOKEN", "test-token")
        self.assertEqual(value, "environment")
        store.assert_not_called()

    def test_falls_back_to_host_store(self):
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch.object(self.module, "_read_from_store", return_value="host-value"),
        ):
            value = self.module.get_credential("TEST_TOKEN", "test-token")
        self.assertEqual(value, "host-value")

    def test_empty_environment_value_falls_back(self):
        with (
            mock.patch.dict(os.environ, {"TEST_TOKEN": ""}),
            mock.patch.object(self.module, "_read_from_store", return_value=""),
        ):
            self.assertEqual(self.module.get_credential("TEST_TOKEN", "test-token"), "")

    def test_no_secret_file_is_read(self):
        self.assertFalse(hasattr(self.module, "_MOUNTED_CREDENTIALS_FILE"))
        self.assertFalse(hasattr(self.module, "_read_mounted_credentials"))


if __name__ == "__main__":
    unittest.main()
