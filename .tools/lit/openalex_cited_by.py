#!/usr/bin/env python3
"""Find highly-cited follow-up papers for a given paper via OpenAlex.

A "follow-up" paper here means any work that cites the input paper. Output is
sorted by citation count (descending) and includes author, year, journal,
title, and citation count.

Auth: reads OPENALEX_API_KEY from the env (mapped from .credentials). Falls
back to anonymous if unset. Note: OpenAlex uses ?api_key=..., NOT a Bearer
header — sending Authorization: Bearer hard-fails with 401.

Usage:
  python .tools/dev/openalex_cited_by.py 10.1146/annurev-financial-102620-103311
  python .tools/dev/openalex_cited_by.py https://doi.org/10.1146/annurev-financial-102620-103311 --top 50

Looking up working papers / preprints:

  Each platform mints its own DOI; pass it the same way as a journal DOI.
  Note that the preprint and the published version are usually separate
  OpenAlex records with separate citation counts.

  - SSRN drafts:  10.2139/ssrn.<id>
      e.g. https://ssrn.com/abstract=3792366  →  10.2139/ssrn.3792366
  - NBER working papers:  10.3386/w<num>
      e.g. NBER WP 28468  →  10.3386/w28468
  - arXiv preprints:  10.48550/arXiv.<arxiv-id>
      e.g. arXiv:2301.12345  →  10.48550/arXiv.2301.12345
      (DataCite auto-mints these for every arXiv paper since ~2022.)

  Drafts without a DOI aren't reachable via this script — search OpenAlex
  directly at https://api.openalex.org/works?search=<title>.
"""
import argparse
import os
import sys
from urllib.parse import quote

import requests

API = "https://api.openalex.org/works"
TIMEOUT = 20


def normalize_doi(s: str) -> str:
    s = s.strip()
    for prefix in ("https://doi.org/", "http://doi.org/", "doi:", "DOI:"):
        if s.startswith(prefix):
            s = s[len(prefix):]
            break
    return s


def base_params() -> dict:
    p = {}
    key = os.environ.get("OPENALEX_API_KEY")
    if key:
        p["api_key"] = key
    return p


def lookup_work(doi: str) -> dict:
    """Fetch the OpenAlex record for a DOI."""
    url = f"{API}/doi:{quote(doi, safe='/')}"
    params = base_params()
    params["select"] = "id,doi,title,publication_year,cited_by_count"
    r = requests.get(url, params=params, timeout=TIMEOUT)
    if r.status_code == 404:
        sys.exit(f"DOI not found in OpenAlex: {doi}")
    r.raise_for_status()
    return r.json()


def fetch_citers(work_id: str, top: int) -> list[dict]:
    """Return up to `top` works that cite `work_id`, sorted by citations desc."""
    params = base_params()
    params.update({
        "filter": f"cites:{work_id}",
        "sort": "cited_by_count:desc",
        "per_page": min(top, 100),
        "select": (
            "id,doi,title,publication_year,cited_by_count,"
            "authorships,primary_location"
        ),
    })
    out: list[dict] = []
    cursor = "*"
    while len(out) < top:
        params["cursor"] = cursor
        r = requests.get(API, params=params, timeout=TIMEOUT)
        r.raise_for_status()
        body = r.json()
        results = body.get("results", [])
        if not results:
            break
        out.extend(results)
        cursor = body.get("meta", {}).get("next_cursor")
        if not cursor:
            break
    return out[:top]


def first_author(work: dict) -> str:
    for a in work.get("authorships") or []:
        author = (a or {}).get("author") or {}
        name = author.get("display_name")
        if name:
            others = len(work.get("authorships") or []) - 1
            return f"{name} et al." if others > 0 else name
    return "—"


def journal(work: dict) -> str:
    loc = work.get("primary_location") or {}
    src = loc.get("source") or {}
    return src.get("display_name") or "—"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("doi", help="DOI of the seed paper (raw, doi: form, or https URL)")
    ap.add_argument("--top", type=int, default=25, help="how many citers to return (default 25)")
    args = ap.parse_args()

    doi = normalize_doi(args.doi)
    seed = lookup_work(doi)
    work_id = seed.get("id")
    if not work_id:
        sys.exit(f"OpenAlex returned no id for {doi}")

    print(
        f"Seed: {seed.get('title')} ({seed.get('publication_year')}) — "
        f"{seed.get('cited_by_count')} total cites — {seed.get('doi')}",
        file=sys.stderr,
    )

    citers = fetch_citers(work_id, args.top)
    if not citers:
        print("No citing works found.", file=sys.stderr)
        return 1

    rows = [
        (
            first_author(w),
            w.get("publication_year") or "—",
            journal(w),
            (w.get("title") or "").strip(),
            w.get("cited_by_count") or 0,
        )
        for w in citers
    ]

    # Already sorted desc by the API, but re-sort defensively.
    rows.sort(key=lambda r: r[4], reverse=True)

    widths = [
        max(len(str(r[i])) for r in rows + [("Author", "Year", "Journal", "Title", "Cites")])
        for i in range(5)
    ]
    # Cap title width so the table stays readable.
    widths[3] = min(widths[3], 80)

    def fmt(row):
        title = row[3]
        if len(title) > widths[3]:
            title = title[: widths[3] - 1] + "…"
        return (
            f"{str(row[4]):>{widths[4]}}  "
            f"{str(row[1]):<{widths[1]}}  "
            f"{str(row[0]):<{widths[0]}}  "
            f"{str(row[2]):<{widths[2]}}  "
            f"{title}"
        )

    print(fmt(("Author", "Year", "Journal", "Title", "Cites")))
    print("-" * (sum(widths) + 8))
    for row in rows:
        print(fmt(row))
    return 0


if __name__ == "__main__":
    sys.exit(main())
