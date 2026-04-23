#!/usr/bin/env python3
# ABOUTME: Reads project credentials from host credential storage and writes a
# ABOUTME: temporary env file for the Dev Container to consume.
#
# Run:     python .devcontainer/inject-credentials.py
# Inputs:  Host OS credential entries via .credentials/get-credentials.py
# Outputs: /tmp/devcontainer-credentials.env (mode 600) with all found credentials

import importlib.machinery
import importlib.util
import os
import subprocess
import sys
from pathlib import Path

_mod_path = str(Path(__file__).resolve().parent.parent / ".credentials" / "get-credentials.py")
_spec = importlib.util.spec_from_loader("get_credentials", importlib.machinery.SourceFileLoader("get_credentials", _mod_path))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
get_all_credentials = _mod.get_all_credentials

ENV_FILE = "/tmp/devcontainer-credentials.env"


def main() -> int:
    found, missing = get_all_credentials()

    if missing:
        print(f"Warning: could not load: {', '.join(missing)}", file=sys.stderr)
        print("Run `python .credentials/setup.py` on your host to save them.", file=sys.stderr)

    if not found:
        print("No credentials found. Container will start without them.", file=sys.stderr)
        # Write an empty file so --env-file doesn't fail
        fd = os.open(ENV_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.close(fd)
        return 0

    env_lines = [f"{env_var}={value}" for env_var, value in found.items()]

    fd = os.open(ENV_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(env_lines) + "\n")

    print(f"Credentials written to {ENV_FILE}: {', '.join(found.keys())}")

    subprocess.Popen(
        ["bash", "-c", f"sleep 600 && rm -f {ENV_FILE}"],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    print(f"Scheduled auto-delete of {ENV_FILE} in 600 seconds")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
