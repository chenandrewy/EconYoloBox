#!/usr/bin/env python3
# ABOUTME: Interactively saves project credentials to host OS credential storage.
#
# Run:     python .credentials/setup.py
# Inputs:  Interactive prompts based on credentials-map.json
# Outputs: Saves credentials to macOS Keychain or Windows Credential Manager

from __future__ import annotations

import getpass
import json
import platform
import subprocess
import sys
from pathlib import Path

_CREDENTIALS_JSON = Path(__file__).resolve().parent / "credentials-map.json"

# Group keychain targets by prefix (e.g. "wrds-username" -> group "wrds")
# and define which ones are secret (all except those ending in "-username")
_SECRET_SUFFIXES = ("-password", "-api-key", "-token", "-secret")


def _load_groups() -> dict[str, dict[str, dict]]:
    with open(_CREDENTIALS_JSON) as f:
        credential_map = json.load(f)

    groups: dict[str, dict[str, dict]] = {}
    for target, env_var in credential_map.items():
        parts = target.split("-", 1)
        group_name = parts[0]
        is_secret = any(target.endswith(s) for s in _SECRET_SUFFIXES)
        prompt = f"{env_var}: "
        groups.setdefault(group_name, {})
        groups[group_name][target] = {"prompt": prompt, "secret": is_secret}

    return groups


def _save_macos_secret(target: str, value: str) -> bool:
    result = subprocess.run(
        [
            "security",
            "add-generic-password",
            "-a",
            getpass.getuser(),
            "-s",
            target,
            "-w",
            value,
            "-U",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def _save_windows_secret(target: str, value: str) -> bool:
    result = subprocess.run(
        [
            "cmdkey",
            f"/generic:{target}",
            "/user:default",
            f"/pass:{value}",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def main() -> int:
    system_name = platform.system()
    if system_name == "Darwin":
        save_fn = _save_macos_secret
        store_name = "macOS Keychain"
    elif system_name == "Windows":
        save_fn = _save_windows_secret
        store_name = "Windows Credential Manager"
    else:
        print(f"Unsupported platform: {system_name}", file=sys.stderr)
        print("Use this script on macOS or Windows.", file=sys.stderr)
        return 1

    groups = _load_groups()
    saved_any = False

    for group_name, targets in groups.items():
        print(f"\n--- {group_name.upper()} ---")
        print("(press Enter to skip)")

        values: dict[str, str] = {}
        skipped = False
        for target, opts in targets.items():
            if opts["secret"]:
                value = getpass.getpass(opts["prompt"])
            else:
                value = input(opts["prompt"]).strip()
            if not value:
                print(f"  Skipping {group_name} credentials.")
                skipped = True
                break
            values[target] = value

        if skipped:
            continue

        all_ok = True
        for target, value in values.items():
            if not save_fn(target, value):
                print(f"  Failed to save {target} to {store_name}.", file=sys.stderr)
                all_ok = False

        if all_ok:
            print(f"  Saved {group_name} credentials to {store_name}:")
            for target in values:
                print(f"    - {target}")
            saved_any = True

    if saved_any:
        print("\nCredentials saved. They will be available to all scripts via .credentials/get-credentials.py.")
    else:
        print("\nNo credentials were saved.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
