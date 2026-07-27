#!/usr/bin/env python3
"""Rank recent papers that cite a given paper, via Google Scholar.

`query` is sent verbatim to Scholar's search box, so a title, a title plus
authors, a DOI, or operators like author:"chen" all work. The FIRST hit becomes
the seed — check the "Seed:" line on stderr, or pass --cluster to pin it.

Usage:
  # seed by search; default window is the past 3 years, ranked by total cites
  python .tools/lit/cited_by.py "Does Academic Research Destroy Stock Return Predictability"

  # add authors to disambiguate a common title
  python .tools/lit/cited_by.py "Replicating anomalies hou xue zhang"

  # pin the seed by cluster id and skip the search
  python .tools/lit/cited_by.py --cluster 18219577721106400043 --since 2023

  # rank by citations per year to surface fast-rising work
  python .tools/lit/cited_by.py "..." --rank cpy --since 2024 --top 30

--since is a calendar year (earliest publication year to include), default three
years back. See README.md for source choice, ranking, and blocking notes.
"""
import argparse
import random
import re
import shutil
import sys
import textwrap
import time
from datetime import datetime
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0 Safari/537.36"
)
HEADERS = {"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"}
BASE = "https://scholar.google.com/scholar"
TIMEOUT = 25
PER_PAGE = 10  # Scholar's fixed page size
CURRENT_YEAR = datetime.now(ZoneInfo("America/New_York")).year


class Unreachable(Exception):
    """Network-layer failure reaching Scholar — almost always the firewall.

    scholar.l.google.com is Google anycast whose IPs rotate; if the current one
    isn't in the allowlisted CIDRs in init-firewall.sh the connection is dropped
    with 'No route to host'. Distinct from a Scholar-layer block (CAPTCHA/429),
    which returns a real HTTP response.
    """


def get(params: dict) -> tuple[requests.Response, bool]:
    """One GET against Scholar. Returns (response, blocked).

    Raises Unreachable on a network-layer failure (firewall / DNS / timeout)
    so the caller can tell "the packets never arrived" apart from "Scholar
    refused us" — the two need different fixes.
    """
    try:
        r = requests.get(BASE, params=params, headers=HEADERS, timeout=TIMEOUT)
    except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
        raise Unreachable(
            "could not reach scholar.google.com — suspect the firewall, not Scholar.\n"
            "  Google rotated its anycast IP out of the allowlisted CIDRs.\n"
            "  Fix: dig +short scholar.google.com, find which block it lands in,\n"
            "  add that CIDR to the Google/Scholar loop in .devcontainer/init-firewall.sh,\n"
            "  then re-run the firewall script (needs sudo / container rebuild)."
        ) from e
    blocked = ("gs_captcha" in r.text) or ("/sorry/" in r.url) or (r.status_code == 429)
    return r, blocked


def cluster_from_result(div) -> tuple[str | None, int | None]:
    """Extract (cluster_id, cite_count) from a result's footer 'Cited by N' link."""
    for a in div.select("div.gs_fl a"):
        href = a.get("href", "")
        text = a.get_text()
        m = re.search(r"cites=(\d+)", href)
        if m and "Cited by" in text:
            n = re.search(r"Cited by\s+([\d,]+)", text)
            count = int(n.group(1).replace(",", "")) if n else None
            return m.group(1), count
    return None, None


def parse_year(byline: str) -> int | None:
    """Pull a 4-digit publication year out of a Scholar byline."""
    m = re.findall(r"\b((?:19|20)\d{2})\b", byline)
    return int(m[-1]) if m else None


def parse_venue(byline: str) -> str:
    """Best-effort venue from a Scholar byline: 'AUTHORS - VENUE, YEAR - SOURCE'."""
    parts = byline.split(" - ")
    if len(parts) < 2:
        return "—"
    middle = parts[1]
    middle = re.sub(r",?\s*(?:19|20)\d{2}.*$", "", middle).strip()
    return middle or "—"


def first_author(byline: str) -> str:
    """First author + 'et al.' if there are more, from the byline's author segment."""
    authors = byline.split(" - ")[0].strip()
    if not authors:
        return "—"
    more = ("," in authors) or ("…" in authors)
    first = authors.split(",")[0].replace("…", "").strip()
    return f"{first} et al." if more else first


def parse_results(html: str) -> list[dict]:
    soup = BeautifulSoup(html, "lxml")
    out = []
    for div in soup.select("div.gs_ri"):
        title_el = div.select_one("h3.gs_rt a") or div.select_one("h3.gs_rt")
        byline_el = div.select_one("div.gs_a")
        byline = byline_el.get_text(" ", strip=True) if byline_el else ""
        cid, cites = cluster_from_result(div)
        out.append({
            "title": title_el.get_text(strip=True) if title_el else "?",
            "author": first_author(byline),
            "venue": parse_venue(byline),
            "year": parse_year(byline),
            "cites": cites or 0,
            "cluster": cid,
        })
    return out


def resolve_cluster(query: str) -> tuple[str, dict]:
    """Search the seed title; return (cluster_id, top_hit) or exit with a reason."""
    r, blocked = get({"q": query, "hl": "en"})
    if blocked:
        sys.exit("BLOCKED resolving seed — Scholar is CAPTCHA-ing this IP.")
    hits = parse_results(r.text)
    if not hits:
        sys.exit("No results parsed for seed — HTML structure may have changed.")
    top = hits[0]
    if not top["cluster"]:
        sys.exit("Could not extract a cluster id from the top hit.")
    return top["cluster"], top


def fetch_citers(cluster: str, as_ylo: int, want: int, max_pages: int) -> tuple[list[dict], bool]:
    """Page through the citing set (year-windowed), collecting >= want candidates.

    Returns (candidates, blocked). Stops early on a block signal or empty page.
    """
    collected: list[dict] = []
    blocked = False
    for page in range(max_pages):
        params = {
            "cites": cluster,
            "as_ylo": str(as_ylo),
            "hl": "en",
            "start": str(page * PER_PAGE),
        }
        r, blocked = get(params)
        if blocked:
            print(f"  ! blocked on page {page + 1}; ranking {len(collected)} so far",
                  file=sys.stderr)
            break
        rows = parse_results(r.text)
        if not rows:
            break
        collected.extend(rows)
        if len(collected) >= want:
            break
        if page < max_pages - 1:
            time.sleep(random.uniform(3.0, 6.0))  # be polite between pages
    return collected, blocked


def cpy(row: dict) -> float:
    """Citations per year since publication (>=1 year to avoid div-by-zero)."""
    if not row["year"]:
        return 0.0
    elapsed = max(1, CURRENT_YEAR - row["year"])
    return row["cites"] / elapsed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("query", nargs="?",
                    help="Scholar search for the seed paper — title, title plus "
                         "authors, a DOI, or Scholar operators; the first hit wins")
    ap.add_argument("--cluster", help="Scholar cluster id, to skip the title search")
    ap.add_argument("--since", type=int, default=None, metavar="YEAR",
                    help="earliest publication year to include, e.g. 2023 "
                         "(default: three years back)")
    ap.add_argument("--rank", choices=("cites", "cpy"), default="cites",
                    help="cites=total (default); cpy=citations per year")
    ap.add_argument("--top", type=int, default=25, help="how many to return (default 25)")
    ap.add_argument("--max-pages", type=int, default=5,
                    help="max Scholar pages to fetch (10 results each, default 5)")
    args = ap.parse_args()

    if not args.query and not args.cluster:
        ap.error("pass a seed title or --cluster")

    # --since used to be a window width; catch stale invocations like "--since 3"
    # rather than silently asking Scholar for everything published since year 3.
    if args.since is not None and args.since < 1900:
        ap.error(f"--since takes a calendar year, not a window width (got {args.since})")
    as_ylo = args.since if args.since is not None else CURRENT_YEAR - 3

    if args.cluster:
        cluster = args.cluster
        print(f"Seed: cluster {cluster} — citers since {as_ylo}", file=sys.stderr)
    else:
        cluster, seed = resolve_cluster(args.query)
        print(f"Seed: {seed['title']} — {seed['cites']} total cites — "
              f"cluster {cluster} — citers since {as_ylo}", file=sys.stderr)

    # Fetch a ranking pool larger than --top so cpy re-ranking has headroom.
    want = max(args.top, 30)
    citers, _ = fetch_citers(cluster, as_ylo, want, args.max_pages)
    if not citers:
        print("No citing papers found in window.", file=sys.stderr)
        return 1

    key = cpy if args.rank == "cpy" else (lambda r: r["cites"])
    citers.sort(key=key, reverse=True)
    citers = citers[: args.top]

    # Outline rather than a table: titles are long enough that a Title column
    # either wraps badly or gets truncated past the point of being useful.
    show_cpy = args.rank == "cpy"
    width = min(shutil.get_terminal_size((100, 24)).columns, 100)
    indent = " " * 5  # matches the "%3d. " label, so wrapped lines stay aligned
    body = max(30, width - len(indent))

    for i, row in enumerate(citers, 1):
        label = f"{i:>3}. "
        title = textwrap.wrap(row["title"], width=body) or ["?"]
        print(label + title[0])
        for line in title[1:]:
            print(indent + line)

        meta = [row["author"], str(row["year"] or "—"), row["venue"]]
        cites = f"{row['cites']} cites"
        if show_cpy:
            cites += f" ({cpy(row):.1f}/yr)"
        meta.append(cites)
        for line in textwrap.wrap(" · ".join(meta), width=body):
            print(indent + line)
        print()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Unreachable as e:
        sys.exit(f"UNREACHABLE: {e}")
