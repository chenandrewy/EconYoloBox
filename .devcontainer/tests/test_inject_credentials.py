#!/usr/bin/env python3
# Run:     python3 .devcontainer/tests/test_inject_credentials.py
# Inputs:  Temporary paths and mocked credential values
# Outputs: unittest results; no project files are modified

import importlib.machinery
import importlib.util
import os
import stat
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "inject-credentials.py"


def load_module():
    spec = importlib.util.spec_from_loader(
        "inject_credentials_under_test",
        importlib.machinery.SourceFileLoader(
            "inject_credentials_under_test",
            str(MODULE_PATH),
        ),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CredentialInjectionTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.secret_file = Path(self.temp_dir.name) / "credentials.env"
        self.module.ENV_FILE = self.secret_file

    def test_write_credentials_uses_mode_600(self):
        self.module._write_credentials(
            {
                "FIRST_TOKEN": "first",
                "SECOND_TOKEN": "value=with=equals",
            }
        )
        self.assertEqual(
            self.secret_file.read_text(encoding="utf-8"),
            "FIRST_TOKEN=first\nSECOND_TOKEN=value=with=equals\n",
        )
        mode = stat.S_IMODE(self.secret_file.stat().st_mode)
        self.assertEqual(mode, 0o600)

    def test_write_credentials_rejects_multiline_values(self):
        with self.assertRaisesRegex(ValueError, "MULTILINE_TOKEN"):
            self.module._write_credentials(
                {"MULTILINE_TOKEN": "first line\nsecond line"}
            )

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "O_NOFOLLOW unavailable")
    def test_write_credentials_does_not_follow_symlinks(self):
        target = Path(self.temp_dir.name) / "target"
        target.write_text("do not replace", encoding="utf-8")
        self.secret_file.symlink_to(target)
        with self.assertRaises(OSError):
            self.module._write_credentials({"TEST_TOKEN": "secret"})
        self.assertEqual(target.read_text(encoding="utf-8"), "do not replace")

    def test_write_credentials_replaces_docker_created_directory(self):
        self.secret_file.mkdir()
        self.module._write_credentials({"TEST_TOKEN": "secret"})
        self.assertEqual(
            self.secret_file.read_text(encoding="utf-8"),
            "TEST_TOKEN=secret\n",
        )

    def test_write_credentials_refuses_nonempty_directory(self):
        self.secret_file.mkdir()
        (self.secret_file / "keep").write_text("data", encoding="utf-8")
        with self.assertRaises(OSError):
            self.module._write_credentials({"TEST_TOKEN": "secret"})
        self.assertTrue((self.secret_file / "keep").exists())

if __name__ == "__main__":
    unittest.main()
