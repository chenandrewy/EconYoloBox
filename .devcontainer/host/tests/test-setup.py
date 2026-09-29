#!/usr/bin/env python3
# Run: python3 .devcontainer/host/tests/test-setup.py
# Inputs: setup.sh and write-local-env.sh; temporary checkouts, rc and env files.
# Outputs: unittest results; verifies registration migration and checkout identity.
from pathlib import Path
import shlex
import os
import shutil
import subprocess
import tempfile
import unittest


class SetupTests(unittest.TestCase):
    def test_environment_records_checkout_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            checkout = root / 'checkout with spaces'
            toolkit = checkout / '.devcontainer' / 'host'
            toolkit.mkdir(parents=True)
            env_file = root / 'local.env'
            script = toolkit / 'write-local-env.sh'
            source = Path(__file__).resolve().parents[1] / script.name
            # Redirect only the output destination to keep the real host env untouched.
            script.write_text(source.read_text().replace(
                'ENV_FILE=/tmp/devcontainer-local.env',
                f'ENV_FILE={shlex.quote(str(env_file))}'))
            subprocess.run(['bash', str(script)], cwd=root, check=True,
                           env={**os.environ, 'TZ': 'America/New_York'})
            values = dict(line.split('=', 1) for line in env_file.read_text().splitlines())
            self.assertEqual(values['LOCAL_CONTAINER_FOLDER'], str(checkout))
            self.assertEqual(values['TZ'], 'America/New_York')
            self.assertTrue(values['LOCAL_HOSTNAME'])
            self.assertEqual(env_file.stat().st_mode & 0o777, 0o600)

    def test_registration_and_relocation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            toolkit = root / "checkout with 'quotes' $dollars" / '.devcontainer' / 'host'
            toolkit.mkdir(parents=True)
            shutil.copy2(Path(__file__).resolve().parents[1] / 'setup.sh', toolkit)
            launcher = toolkit / 'devcontainer.zsh'
            launcher.write_text('typeset -g YBOX_TEST_LOADED=yes\n')
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
            self.assertIn('# >>> ybox host launcher >>>', registered)
            self.assertEqual(len(list(root.glob('custom.zshrc.ybox-backup-*'))), 1)
            setup()
            self.assertEqual(rc.read_text(), registered)
            self.assertEqual(len(list(root.glob('custom.zshrc.ybox-backup-*'))), 1)
            result = subprocess.run(['zsh', '-f', '-c',
                                     'source "$1"; print -r -- "$YBOX_TEST_LOADED"',
                                     'test', str(rc)], check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), 'yes')

            legacy = (original + '# >>> bbox host launcher >>>\n'
                      f'source {shlex.quote(str(launcher))}\n'
                      '# <<< bbox host launcher <<<\n')
            rc.write_text(legacy)
            setup()
            migrated = rc.read_text()
            self.assertTrue(migrated.startswith(original))
            self.assertEqual(migrated.count('source '), 1)
            self.assertIn('# >>> ybox host launcher >>>', migrated)
            self.assertNotIn('# >>> bbox host launcher >>>', migrated)
            setup()
            self.assertEqual(rc.read_text(), migrated)

            moved = root / 'renamed-checkout'
            toolkit.parent.parent.rename(moved)
            toolkit = moved / '.devcontainer' / 'host'
            setup()
            self.assertNotIn(str(launcher), rc.read_text())
            self.assertIn(str(toolkit / 'devcontainer.zsh'), rc.read_text())
            self.assertEqual(rc.read_text().count('source '), 1)

            for old_dir in ('.host', 'host', 'infra/host'):
                old_launcher = moved / old_dir / 'devcontainer.zsh'
                rc.write_text(f'source {shlex.quote(str(old_launcher))}\n')
                setup()
                self.assertNotIn(str(old_launcher), rc.read_text())
                self.assertIn(str(toolkit / 'devcontainer.zsh'), rc.read_text())

            for malformed in ('# >>> bbox host launcher >>>\n',
                              '# >>> ybox host launcher >>>\n',
                              '# >>> bbox host launcher >>>\n# <<< ybox host launcher <<<\n'):
                rc.write_text(malformed)
                with self.assertRaises(subprocess.CalledProcessError):
                    setup()
                self.assertEqual(rc.read_text(), malformed)


if __name__ == '__main__':
    unittest.main()
