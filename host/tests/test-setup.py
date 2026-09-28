#!/usr/bin/env python3
# Run: python3 host/tests/test-setup.py
# Inputs: setup.sh; uses temporary checkouts and rc files, never your real .zshrc.
# Outputs: unittest results; verifies preservation, quoting, migration, and reruns.
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


class SetupTests(unittest.TestCase):
    def test_registration_and_relocation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toolkit = root / "checkout with 'quotes' $dollars" / 'host'
            toolkit.mkdir(parents=True)
            shutil.copy2(Path(__file__).resolve().parents[1] / 'setup.sh', toolkit)
            launcher = toolkit / 'devcontainer.zsh'
            launcher.write_text('typeset -g BBOX_TEST_LOADED=yes\n')
            rc = root / 'custom.zshrc'
            original = '# Existing settings\nexport KEEP_ME=yes\n'
            rc.write_text(original + f'source {shlex.quote(str(launcher))}\n')

            def setup():
                return subprocess.run(['bash', str(toolkit / 'setup.sh'), '--rc-file', str(rc)],
                                      check=True, capture_output=True, text=True)

            setup()
            registered = rc.read_text()
            self.assertTrue(registered.startswith(original))
            self.assertEqual(registered.count('source '), 1)
            self.assertEqual(len(list(root.glob('custom.zshrc.bbox-backup-*'))), 1)
            setup()
            self.assertEqual(rc.read_text(), registered)
            self.assertEqual(len(list(root.glob('custom.zshrc.bbox-backup-*'))), 1)
            result = subprocess.run(['zsh', '-f', '-c',
                                     'source "$1"; print -r -- "$BBOX_TEST_LOADED"',
                                     'test', str(rc)], check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), 'yes')

            moved = root / 'renamed-checkout'
            toolkit.parent.rename(moved)
            toolkit = moved / 'host'
            setup()
            self.assertNotIn(str(launcher), rc.read_text())
            self.assertIn(str(toolkit / 'devcontainer.zsh'), rc.read_text())
            self.assertEqual(rc.read_text().count('source '), 1)

            old_launcher = toolkit.parent / '.host' / 'devcontainer.zsh'
            rc.write_text(f'source {shlex.quote(str(old_launcher))}\n')
            setup()
            self.assertNotIn(str(old_launcher), rc.read_text())
            self.assertIn(str(toolkit / 'devcontainer.zsh'), rc.read_text())

            malformed = '# >>> bbox host launcher >>>\n'
            rc.write_text(malformed)
            with self.assertRaises(subprocess.CalledProcessError):
                setup()
            self.assertEqual(rc.read_text(), malformed)


if __name__ == '__main__':
    unittest.main()
