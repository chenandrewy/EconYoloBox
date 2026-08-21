#!/usr/bin/env python3
# ABOUTME: Reads project credentials from host credential storage and writes a
# ABOUTME: temporary file that is bind-mounted read-only into the Dev Container.
#
# Run:     python .devcontainer/inject-credentials.py
# Inputs:  Host OS credential entries via .credentials/get-credentials.py
# Outputs: /tmp/devcontainer-credentials.env (mode 600) with all found credentials

import importlib.machinery
import importlib.util
import os
import stat
import sys
from pathlib import Path

_mod_path = str(Path(__file__).resolve().parent.parent / ".credentials" / "get-credentials.py")
_spec = importlib.util.spec_from_loader("get_credentials", importlib.machinery.SourceFileLoader("get_credentials", _mod_path))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
get_all_credentials = _mod.get_all_credentials

ENV_FILE = Path("/tmp/devcontainer-credentials.env")


def _write_credentials(found: dict[str, str]) -> None:
    """Write credentials securely without following a pre-existing symlink."""
    invalid = [
        env_var
        for env_var, value in found.items()
        if "\n" in value or "\r" in value
    ]
    if invalid:
        names = ", ".join(invalid)
        raise ValueError(f"Credential values must be single-line: {names}")

    # If the container was started while the mount source was missing (e.g.
    # after a host reboot cleared /tmp), Docker recreates the source as an
    # empty directory. rmdir refuses to remove a non-empty one, so anything
    # with real content still fails loudly below instead of being deleted.
    if not ENV_FILE.is_symlink() and ENV_FILE.is_dir():
        os.rmdir(ENV_FILE)

    flags = os.O_WRONLY | os.O_CREAT
    if hasattr(os, "O_NONBLOCK"):
        flags |= os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW

    fd = os.open(ENV_FILE, flags, 0o600)
    try:
        file_stat = os.fstat(fd)
        if not stat.S_ISREG(file_stat.st_mode):
            raise OSError(f"{ENV_FILE} is not a regular file")
        if hasattr(os, "getuid") and file_stat.st_uid != os.getuid():
            raise PermissionError(f"{ENV_FILE} is not owned by the current user")
        os.fchmod(fd, 0o600)
        os.ftruncate(fd, 0)
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            fd = -1
            for env_var, value in found.items():
                file.write(f"{env_var}={value}\n")
    finally:
        if fd >= 0:
            os.close(fd)


def main() -> int:
    found, missing = get_all_credentials()

    if missing:
        print(f"Warning: could not load: {', '.join(missing)}", file=sys.stderr)
        print("Run `python .credentials/setup.py` on your host to save them.", file=sys.stderr)

    if not found:
        print("No credentials found. Container will start without them.", file=sys.stderr)
        # The bind-mount source must exist even when no credentials are available.
        try:
            _write_credentials({})
        except (OSError, ValueError) as error:
            print(f"Could not create credential mount source: {error}", file=sys.stderr)
            return 1
        return 0

    try:
        _write_credentials(found)
    except (OSError, ValueError) as error:
        print(f"Could not write credentials securely: {error}", file=sys.stderr)
        return 1

    print(f"Credentials written to {ENV_FILE}: {', '.join(found.keys())}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
