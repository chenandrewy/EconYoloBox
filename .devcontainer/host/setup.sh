#!/bin/bash
# Run: bash /path/to/checkout/.devcontainer/host/setup.sh [--rc-file PATH]
# Inputs: this checkout's launcher; ${ZDOTDIR:-$HOME}/.zshrc by default.
# Outputs: a backed-up, idempotent launcher registration and prerequisite report.
# Requires Python 3. Installs no software and does not start Docker or a container.
#
# The registration is a managed block at the end of the rc file:
# Existing bbox-marked blocks are migrated to the ybox markers.
#
#   # >>> ybox host launcher >>>
#   source /path/to/checkout/.devcontainer/host/devcontainer.zsh
#   # <<< ybox host launcher <<<
#
# The path is this checkout's, shell-quoted if needed. Rerunning cuts out the
# old block and appends a fresh one, so the block moves back to the end (after
# the user's completion setup) and follows a moved checkout. Outside the block,
# only bare `source`/`.` lines for this same launcher (the previous README's
# registration) are removed; everything else is kept byte for byte. A changed
# file is backed up first to <rc>.ybox-backup-XXXXXX beside it; a missing,
# duplicated or out-of-order marker aborts with no changes.
set -euo pipefail

toolkit_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc_file="${ZDOTDIR:-$HOME}/.zshrc"
if [ "$#" -gt 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != --rc-file ]; then
        echo 'Usage: bash .devcontainer/host/setup.sh [--rc-file PATH]' >&2
        exit 2
    fi
    rc_file=$2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo 'Missing python3. Install Python 3, then rerun setup.' >&2
    exit 1
fi

python3 - "$toolkit_dir/devcontainer.zsh" "$rc_file" <<'PY'
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile

launcher = Path(sys.argv[1])
# Earlier layouts kept the launcher in .host/, host/, or infra/host/.
checkout = launcher.parent.parent.parent
old_launchers = [checkout / d / launcher.name for d in ('.host', 'host', 'infra/host')]
rc = Path(sys.argv[2]).expanduser()
begin = '# >>> ybox host launcher >>>'
end = '# <<< ybox host launcher <<<'
legacy_begin = '# >>> bbox host launcher >>>'
legacy_end = '# <<< bbox host launcher <<<'
if not launcher.is_file():
    sys.exit(f'Launcher not found: {launcher}')
if rc.is_symlink() and not rc.exists():
    sys.exit(f'Refusing to overwrite dangling symlink: {rc}')
original = rc.read_text() if rc.exists() else ''
lines = original.splitlines(keepends=True)
starts = [i for i, line in enumerate(lines) if line.rstrip('\r\n') in (begin, legacy_begin)]
ends = [i for i, line in enumerate(lines) if line.rstrip('\r\n') in (end, legacy_end)]
if starts or ends:
    if (len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]
            or (lines[starts[0]].rstrip('\r\n'), lines[ends[0]].rstrip('\r\n'))
            not in ((begin, end), (legacy_begin, legacy_end))):
        sys.exit(f'Malformed host launcher setup block in {rc}; no changes made.')

# Migrate simple registrations from the previous README without evaluating rc code.
def is_legacy(line):
    try:
        words = shlex.split(line, comments=True)
    except ValueError:
        return False
    if len(words) != 2 or words[0] not in ('source', '.'):
        return False
    path = words[1].replace('${HOME}', str(Path.home())).replace('$HOME', str(Path.home()))
    return Path(path).expanduser() in (launcher, *old_launchers)

kept = []
for i, line in enumerate(lines):
    if starts and starts[0] <= i <= ends[0]:
        continue
    if not is_legacy(line):
        kept.append(line)
prefix = ''.join(kept)
if prefix and not prefix.endswith('\n'):
    prefix += '\n'
updated = prefix + f'{begin}\nsource {shlex.quote(str(launcher))}\n{end}\n'
if updated == original:
    print(f'Already configured: {rc}')
else:
    rc.parent.mkdir(parents=True, exist_ok=True)
    if rc.exists():
        fd, backup = tempfile.mkstemp(prefix=rc.name + '.ybox-backup-', dir=rc.parent)
        os.close(fd)
        shutil.copy2(rc, backup)
        print(f'Backup: {backup}')
    rc.write_text(updated)
    print(f'Configured: {rc}')
PY

for prerequisite in zsh docker devcontainer code; do
    if command -v "$prerequisite" >/dev/null 2>&1; then
        printf 'Found: %s\n' "$prerequisite"
    else
        case "$prerequisite" in
            zsh) echo 'Missing zsh: install zsh to use ybox.' ;;
            docker) echo 'Missing docker: install and start Docker Desktop.' ;;
            devcontainer) echo 'Missing devcontainer: install Node.js/npm, then run npm install -g @devcontainers/cli.' ;;
            code) echo "Missing code (needed for --code): in VS Code, run Shell Command: Install 'code' command in PATH." ;;
        esac
    fi
done
printf '\n%s\n' 'Open a new host zsh terminal (or run exec zsh).' \
    'From the checkout root, run ybox --code. Docker Desktop must be running.'
