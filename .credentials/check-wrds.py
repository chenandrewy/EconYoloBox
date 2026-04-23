#!/usr/bin/env python3
# ABOUTME: Checks that WRDS credentials are available and can connect.
#
# Run:     python .credentials/check-wrds.py
# Inputs:  WRDS credentials via env vars or host credential store
# Outputs: Prints connection status, exits 0 on success, 1 on failure

import importlib.machinery
import importlib.util
from pathlib import Path

_mod_path = str(Path(__file__).resolve().parent / "get-credentials.py")
_spec = importlib.util.spec_from_loader("get_credentials", importlib.machinery.SourceFileLoader("get_credentials", _mod_path))
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
get_credential = _mod.get_credential


def main() -> int:
    username = get_credential("WRDS_USERNAME", "wrds-username")
    password = get_credential("WRDS_PASSWORD", "wrds-password")

    if not username or not password:
        missing = []
        if not username:
            missing.append("WRDS_USERNAME / wrds-username")
        if not password:
            missing.append("WRDS_PASSWORD / wrds-password")
        print(f"FAIL: Missing credentials: {', '.join(missing)}")
        print(
            "Rerun `python .credentials/setup.py` on your host/local machine, "
            "then reopen or rebuild the devcontainer so WRDS credentials are injected."
        )
        return 1

    print("WRDS credentials found")

    import wrds

    print("Querying WRDS...")
    print("Be sure to check your 2FA device for a notification...")
    db = wrds.Connection(wrds_username=username, wrds_password=password)
    result = db.raw_sql("select 1 as ok").iloc[0, 0]
    db.close()

    if result == 1:
        print("WRDS connection OK")
        return 0
    else:
        print(f"FAIL: Unexpected query result: {result}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
