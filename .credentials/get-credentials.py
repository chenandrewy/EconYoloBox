# ABOUTME: Shared credential retrieval module.
# ABOUTME: Returns credentials from env vars (container) or host credential store (macOS/Windows).
#
# Usage:  from importlib.machinery import SourceFileLoader; mod = SourceFileLoader("gc", ".credentials/get-credentials.py").load_module()
# Inputs: Environment variables or host OS credential store entries, credentials-map.json
# Outputs: Credential values as strings

from __future__ import annotations

import json
import os
import platform
import subprocess
from pathlib import Path

_CREDENTIALS_JSON = Path(__file__).resolve().parent / "credentials-map.json"


def _load_credential_map() -> dict[str, str]:
    with open(_CREDENTIALS_JSON) as f:
        return json.load(f)


def _read_macos_secret(target: str) -> str:
    result = subprocess.run(
        ["security", "find-generic-password", "-s", target, "-w"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _read_windows_secret(target: str) -> str:
    script = (
        "if (-not (Get-Command Get-StoredCredential -ErrorAction SilentlyContinue)) "
        "{ Write-Error 'Get-StoredCredential command not available. Install CredentialManager module.'; exit 1 }\n"
        f"$cred = Get-StoredCredential -Target '{target}'\n"
        f"if (-not $cred) {{ Write-Error \"Credential '{target}' not found in Windows Credential Manager.\"; exit 1 }}\n"
        "$cred.GetNetworkCredential().Password"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def _read_from_store(target: str) -> str:
    """Read a credential from the host OS credential store."""
    system = platform.system()
    if system == "Darwin":
        return _read_macos_secret(target)
    elif system == "Windows":
        return _read_windows_secret(target)
    return ""


def get_credential(env_var: str, keychain_target: str) -> str:
    """Return credential from env var if set, else from host credential store.

    Returns empty string if not found in either location.
    """
    value = os.environ.get(env_var, "")
    if value:
        return value
    return _read_from_store(keychain_target)


def get_all_credentials() -> tuple[dict[str, str], list[str]]:
    """Resolve all credentials defined in credentials-map.json.

    Returns (found, missing) where found is {env_var: value} and missing is
    a list of keychain targets that could not be resolved.
    """
    credential_map = _load_credential_map()
    found = {}
    missing = []
    for target, env_var in credential_map.items():
        value = get_credential(env_var, target)
        if value:
            found[env_var] = value
        else:
            missing.append(target)
    return found, missing
