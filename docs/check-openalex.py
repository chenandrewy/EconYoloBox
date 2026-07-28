"""Quick sanity check for OpenAlex API access.

Reads OPENALEX_API_KEY through the shared credential resolver, makes one cheap
call, and prints status + rate-limit headers.

Usage:  python3 docs/check-openalex.py
Inputs: Optional OPENALEX_API_KEY resolved through `.credentials`
Outputs: OpenAlex status and rate-limit information on stdout
"""
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

import requests

_credentials_path = (
    Path(__file__).resolve().parents[1] / ".credentials" / "get-credentials.py"
)
_credentials_spec = importlib.util.spec_from_loader(
    "get_credentials",
    importlib.machinery.SourceFileLoader("get_credentials", str(_credentials_path)),
)
_credentials = importlib.util.module_from_spec(_credentials_spec)
_credentials_spec.loader.exec_module(_credentials)

URL = "https://api.openalex.org/works"
params = {"per_page": 1, "select": "id"}

key = _credentials.get_credential("OPENALEX_API_KEY", "openalex-api-key")
if key:
    params["api_key"] = key
    print(f"using key {key[:4]}…{key[-4:]} ({len(key)} chars)")
else:
    print("OPENALEX_API_KEY unset — running anonymous")

r = requests.get(URL, params=params, timeout=10)
print(f"status: {r.status_code} {r.reason}")

for h in [
    "x-ratelimit-limit",
    "x-ratelimit-remaining",
    "x-ratelimit-limit-usd",
    "x-ratelimit-prepaid-remaining-usd",
    "x-ratelimit-reset",
]:
    if h in r.headers:
        print(f"{h}: {r.headers[h]}")

if r.ok:
    print(f"meta: {r.json().get('meta')}")
    sys.exit(0)
else:
    print(f"body: {r.text[:300]}")
    sys.exit(1)
