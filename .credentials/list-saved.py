#!/usr/bin/env python3
# ABOUTME: Lists which mapped credentials exist in the host OS credential store.
#
# Run:     python .credentials/list-saved.py
# Inputs:  credentials-map.json
# Outputs: saved/missing status for each credential target, without printing values

from __future__ import annotations

import json
import platform
import subprocess
import sys
from pathlib import Path

_CREDENTIALS_JSON = Path(__file__).resolve().parent / "credentials-map.json"


def _load_credential_map() -> dict[str, str]:
    with open(_CREDENTIALS_JSON) as f:
        return json.load(f)


def _macos_secret_exists(target: str) -> bool:
    result = subprocess.run(
        ["security", "find-generic-password", "-s", target],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def _windows_secret_exists(target: str) -> bool:
    script = (
        "if (-not (Get-Command Get-StoredCredential -ErrorAction SilentlyContinue)) "
        "{ exit 1 }\n"
        f"$cred = Get-StoredCredential -Target '{target}'\n"
        "if ($cred) { exit 0 }\n"
        "exit 1"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def _store_checker():
    system_name = platform.system()
    if system_name == "Darwin":
        return _macos_secret_exists, "macOS Keychain"
    if system_name == "Windows":
        return _windows_secret_exists, "Windows Credential Manager"
    return None, ""


def main() -> int:
    exists_fn, store_name = _store_checker()
    if exists_fn is None:
        print(f"Unsupported platform: {platform.system()}", file=sys.stderr)
        print("Use this script on macOS or Windows.", file=sys.stderr)
        return 1

    credential_map = _load_credential_map()
    saved = 0

    print(f"Credential store: {store_name}")
    print()

    for target, env_var in credential_map.items():
        exists = exists_fn(target)
        status = "saved" if exists else "missing"
        if exists:
            saved += 1
        print(f"{status:7} {target:24} {env_var}")

    print()
    print(f"{saved} of {len(credential_map)} credentials saved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
