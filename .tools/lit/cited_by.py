#!/usr/bin/env python3
"""Find highly-cited follow-up papers for a given paper via OpenAlex.

A "follow-up" paper here means any work that cites the input paper. Output is
sorted by citation count (descending) and includes author, year, journal,
title, and citation count.

Auth: reads OPENALEX_API_KEY through the shared credential resolver. Falls back
to anonymous if unset. Note: OpenAlex uses ?api_key=..., NOT a Bearer
header — sending Authorization: Bearer hard-fails with 401.

Usage:
  cited_by.py 10.1146/annurev-financial-102620-103311
  cited_by.py https://doi.org/10.1146/annurev-financial-102620-103311 --top 50

Seeding without a DOI: pass a title instead and the script lists matching
records, each with the DOI or OpenAlex W-id that pins it; re-run with that id.
Browse-then-pick rather than auto-picking the top hit, because the first hit is
not reliably the paper you meant.

  cited_by.py "the positive economics of methodology"   # browse
  cited_by.py 10.1006/jeth.1996.0004                    # rank citers

A W-id is accepted anywhere a DOI is, which is the only handle on the many
OpenAlex records that carry no DOI (older articles, chapters, some WPs).

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
import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path
from urllib.parse import quote

import requests

API = "https://api.openalex.org/works"
TIMEOUT = 20

_credentials_path = (
    Path(__file__).resolve().parents[2] / ".credentials" / "get-credentials.py"
)
_credentials_spec = importlib.util.spec_from_loader(
    "get_credentials",
    importlib.machinery.SourceFileLoader("get_credentials", str(_credentials_path)),
)
_credentials = importlib.util.module_from_spec(_credentials_spec)
_credentials_spec.loader.exec_module(_credentials)


def looks_like_doi(s: str) -> bool:
    return s.startswith("10.")


def looks_like_work_id(s: str) -> bool:
    """OpenAlex work ids are W<digits>, bare or as an openalex.org URL."""
    return bool(re.fullmatch(r"(https?://openalex\.org/)?W\d+", s))


def normalize_work_id(s: str) -> str:
    return s.rsplit("/", 1)[-1]


def normalize_doi(s: str) -> str:
    s = s.strip()
    for prefix in ("https://doi.org/", "http://doi.org/", "doi:", "DOI:"):
        if s.startswith(prefix):
            s = s[len(prefix):]
            break
    return s


def base_params() -> dict:
    p = {}
    key = _credentials.get_credential("OPENALEX_API_KEY", "openalex-api-key")
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


SEED_SELECT = "id,doi,title,publication_year,cited_by_count,authorships"


def lookup_work_id(work_id: str) -> dict:
    """Fetch the OpenAlex record for a W-id, for records that carry no DOI."""
    params = base_params()
    params["select"] = SEED_SELECT
    r = requests.get(f"{API}/{work_id}", params=params, timeout=TIMEOUT)
    if r.status_code == 404:
        sys.exit(f"Work id not found in OpenAlex: {work_id}")
    r.raise_for_status()
    return r.json()


def search_works(query: str, limit: int) -> list[dict]:
    """Title search for the seed paper, by relevance.

    Uses filter=title.search rather than the general `search` param: the latter
    also matches abstracts and full text, so a title query drowns in the papers
    that *discuss* the seed.

    Left on OpenAlex's default relevance sort deliberately. Sorting by cites
    looks tidier but buries the target whenever a famous paper shares its
    vocabulary: for "the positive economics of methodology" it pushed the Kahn-
    Landsburg-Stockman paper (11 cites) to hit 11, below Friedman's "The
    Methodology of Positive Economics" (1573) and its reprints, i.e. off the
    default page. Relevance honors word order and returned it at hit 4.
    """
    params = base_params()
    params.update({
        "filter": f"title.search:{query}",
        "per_page": limit,
        "select": SEED_SELECT,
    })
    r = requests.get(API, params=params, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json().get("results", [])


def print_hits(query: str, hits: list[dict]) -> None:
    """Print search hits with the argument that pins each one."""
    print(f"Search: {query} — {len(hits)} hits\n", file=sys.stderr)
    for i, w in enumerate(hits, 1):
        print(f"  {i}. {(w.get('title') or '—').strip()}", file=sys.stderr)
        print(
            f"     {first_author(w)} · {w.get('publication_year') or '—'} · "
            f"{w.get('cited_by_count') or 0} cites",
            file=sys.stderr,
        )
        doi = normalize_doi(w.get("doi") or "") if w.get("doi") else None
        pin = doi or normalize_work_id(w.get("id") or "")
        print(f"     {pin}" if pin else "     (no pinnable id)", file=sys.stderr)
    print(
        "\nPick the paper you meant, then re-run with its DOI or W-id "
        "(or add --first to take hit 1).",
        file=sys.stderr,
    )


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
    ap.add_argument("seed", help="DOI, OpenAlex W-id, or a title to search for")
    ap.add_argument("--top", type=int, default=25, help="how many citers to return (default 25)")
    ap.add_argument("--first", action="store_true",
                    help="with a title query, take hit 1 instead of listing hits")
    ap.add_argument("--hits", type=int, default=10, metavar="N",
                    help="how many search hits to list (default 10)")
    args = ap.parse_args()

    raw = args.seed.strip()
    if looks_like_work_id(raw):
        seed = lookup_work_id(normalize_work_id(raw))
    elif looks_like_doi(normalize_doi(raw)):
        seed = lookup_work(normalize_doi(raw))
    else:
        hits = search_works(raw, args.hits)
        if not hits:
            sys.exit(f"No OpenAlex records with a title matching: {raw}")
        if not args.first:
            print_hits(raw, hits)
            return 0
        seed = hits[0]

    work_id = seed.get("id")
    if not work_id:
        sys.exit(f"OpenAlex returned no id for {raw}")

    print(
        f"Seed: {seed.get('title')} ({seed.get('publication_year')}) — "
        f"{seed.get('cited_by_count')} total cites — {seed.get('doi') or work_id}",
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
