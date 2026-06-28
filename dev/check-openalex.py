"""Quick sanity check for OpenAlex API access.

Reads OPENALEX_API_KEY from the env (mapped from .credentials), makes one
cheap call, and prints status + rate-limit headers.

Usage:  python dev/check-openalex.py
"""
import os
import sys

import requests

URL = "https://api.openalex.org/works"
params = {"per_page": 1, "select": "id"}

key = os.environ.get("OPENALEX_API_KEY")
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
