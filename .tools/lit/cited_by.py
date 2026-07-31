#!/usr/bin/env python3
"""Rank recent papers that cite a given paper, via Google Scholar.

Two steps, because Scholar cannot be trusted to put the paper you mean at the
top of its own results (it reshuffles between identical requests, and the record
you want is sometimes not on the page at all). So a bare query BROWSES — it
prints the search hits with a copy-pasteable --cluster id for each — and you
re-run with the id of the one you wanted to get the citers.

`query` is sent verbatim to Scholar's search box, so a title, a title plus
authors, a DOI, or operators like author:"chen" all work.

Usage:
  # step 1: browse the hits for the paper you mean
  python .tools/lit/cited_by.py "kahn landsburg"

  # step 2: rank its citers; default window is the past 3 years, by total cites
  python .tools/lit/cited_by.py --cluster 5179910145110411934 --since 1996

  # rank by citations per year to surface fast-rising work
  python .tools/lit/cited_by.py --cluster 18219577721106400043 --rank cpy --top 30

  # one shot, taking the top hit as the seed — only when the query is
  # distinctive enough to trust; check the Seed: line it echoes back
  python .tools/lit/cited_by.py "Replicating anomalies hou xue zhang" --first

--since is a calendar year (earliest publication year to include), default three
years back. See README.md for source choice, ranking, and blocking notes.
"""
import argparse
import email.utils
import http.cookiejar
import json
import os
import random
import re
import shutil
import sys
import tempfile
import textwrap
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/125.0 Safari/537.36"
)
HEADERS = {
    "User-Agent": UA,
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,"
        "image/avif,image/webp,image/apng,*/*;q=0.8"
    ),
    "Accept-Language": "en-US,en;q=0.9",
    "Sec-Ch-Ua": '"Not/A)Brand";v="8", "Chromium";v="125", '
                 '"Google Chrome";v="125"',
    "Sec-Ch-Ua-Mobile": "?0",
    "Sec-Ch-Ua-Platform": '"macOS"',
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-User": "?1",
    "Upgrade-Insecure-Requests": "1",
}
BASE = "https://scholar.google.com/scholar"
TIMEOUT = 25
PER_PAGE = 10  # Scholar's fixed page size
REQUEST_DELAY = (3.0, 6.0)
BLOCK_COOLDOWNS = (timedelta(hours=1), timedelta(hours=6), timedelta(hours=24))
CURRENT_YEAR = datetime.now(ZoneInfo("America/New_York")).year

# The seed search sends no corpus parameters. Citation-only records are included
# by default (Scholar's "include citations" checkbox comes back aria-checked;
# as_vis=1 is the opt-OUT, as_vis=0 the default), and an as_sdt value gets
# normalized away — Scholar rewrote 2000005 to 0,21 in every link it generated.


class Unreachable(Exception):
    """Network-layer failure reaching Scholar — almost always the firewall.

    scholar.l.google.com is Google anycast whose IPs rotate; if the current one
    isn't in the allowlisted CIDRs in init-firewall.sh the connection is dropped
    with 'No route to host'. Distinct from a Scholar-layer block (CAPTCHA/429),
    which returns a real HTTP response.
    """


class CoolingDown(Exception):
    """A recent Scholar block makes another request premature."""


class ScholarClient:
    """Stateful, paced Scholar client with persistent cookies and block memory."""

    def __init__(self, cache_dir: Path | None = None) -> None:
        if cache_dir is None:
            cache_root = Path(
                os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")
            )
            cache_dir = cache_root / "sandbox-lit"
        self.cache_dir = cache_dir
        self.cookie_path = cache_dir / "scholar-cookies.txt"
        self.block_path = cache_dir / "scholar-block.json"
        self.legacy_block_path = cache_dir / "scholar-blocked-at"
        self.session = requests.Session()
        self.session.headers.update(HEADERS)
        self.cookies = http.cookiejar.MozillaCookieJar(str(self.cookie_path))
        if self.cookie_path.exists():
            try:
                self.cookies.load(ignore_discard=True, ignore_expires=True)
            except (OSError, http.cookiejar.LoadError):
                # A truncated cache should cost continuity, not break the tool.
                pass
        self.session.cookies = self.cookies
        self.referer = "https://scholar.google.com/"

    def _ensure_cache_dir(self) -> None:
        self.cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.cache_dir, 0o700)

    def _save_cookies(self) -> None:
        """Atomically retain even session cookies for continuity across runs."""
        self._ensure_cache_dir()
        fd, tmp_name = tempfile.mkstemp(prefix="scholar-cookies-", dir=self.cache_dir)
        os.close(fd)
        tmp_path = Path(tmp_name)
        try:
            self.cookies.save(str(tmp_path), ignore_discard=True, ignore_expires=True)
            os.chmod(tmp_path, 0o600)
            tmp_path.replace(self.cookie_path)
        finally:
            tmp_path.unlink(missing_ok=True)

    def _read_block_state(self) -> dict | None:
        try:
            state = json.loads(self.block_path.read_text(encoding="utf-8"))
            datetime.fromisoformat(state["blocked_at"])
            datetime.fromisoformat(state["retry_at"])
            int(state["consecutive_blocks"])
            return state
        except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
            pass

        # Migrate the timestamp-only state written by the first implementation.
        try:
            blocked_at = datetime.fromisoformat(
                self.legacy_block_path.read_text(encoding="ascii").strip()
            ).astimezone(timezone.utc)
        except (OSError, ValueError):
            return None
        state = {
            "blocked_at": blocked_at.isoformat(),
            "retry_at": (blocked_at + BLOCK_COOLDOWNS[0]).isoformat(),
            "consecutive_blocks": 1,
            "request_kind": "unknown (legacy state)",
            "status_code": None,
            "signal": "unknown (legacy state)",
            "redirect": None,
            "retry_after": None,
        }
        self._write_block_state(state)
        self.legacy_block_path.unlink(missing_ok=True)
        return state

    def _write_block_state(self, state: dict) -> None:
        self._ensure_cache_dir()
        fd, tmp_name = tempfile.mkstemp(prefix="scholar-block-", dir=self.cache_dir)
        tmp_path = Path(tmp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(state, f, indent=2, sort_keys=True)
                f.write("\n")
            os.chmod(tmp_path, 0o600)
            tmp_path.replace(self.block_path)
        finally:
            tmp_path.unlink(missing_ok=True)

    @staticmethod
    def _as_utc(value: str) -> datetime:
        return datetime.fromisoformat(value).astimezone(timezone.utc)

    @staticmethod
    def _request_kind(params: dict) -> str:
        return next(
            (key for key in ("q", "cluster", "cites") if key in params),
            "unknown",
        )

    @staticmethod
    def _retry_after(response: requests.Response, now: datetime) -> datetime | None:
        value = response.headers.get("Retry-After")
        if not value:
            return None
        try:
            return now + timedelta(seconds=max(0, int(value)))
        except ValueError:
            try:
                parsed = email.utils.parsedate_to_datetime(value)
                return parsed.astimezone(timezone.utc)
            except (TypeError, ValueError, OverflowError):
                return None

    def _check_cooldown(self) -> None:
        state = self._read_block_state()
        if state is None:
            return
        retry_at = self._as_utc(state["retry_at"])
        remaining = retry_at - datetime.now(timezone.utc)
        if remaining <= timedelta(0):
            return
        minutes = max(1, int((remaining.total_seconds() + 59) // 60))
        local_retry = retry_at.astimezone(ZoneInfo("America/New_York"))
        raise CoolingDown(
            f"Scholar blocked a recent request; refusing to retry for {minutes} more "
            f"minute(s) (until {local_retry:%Y-%m-%d %H:%M:%S %Z})."
        )

    def _record_block(self, response: requests.Response, params: dict) -> None:
        prior = self._read_block_state()
        count = int(prior["consecutive_blocks"]) + 1 if prior else 1
        cooldown = BLOCK_COOLDOWNS[min(count - 1, len(BLOCK_COOLDOWNS) - 1)]
        now = datetime.now(timezone.utc)
        retry_after = self._retry_after(response, now)
        retry_at = max(now + cooldown, retry_after or now)
        signals = []
        if "gs_captcha" in response.text:
            signals.append("gs_captcha")
        if "/sorry/" in response.url:
            signals.append("/sorry/ redirect")
        if response.status_code == 429:
            signals.append("HTTP 429")
        parsed_url = urlparse(response.url)
        redirect = (
            f"{parsed_url.scheme}://{parsed_url.netloc}{parsed_url.path}"
            if response.history or "/sorry/" in response.url else None
        )
        state = {
            "blocked_at": now.isoformat(),
            "retry_at": retry_at.isoformat(),
            "consecutive_blocks": count,
            "request_kind": self._request_kind(params),
            "status_code": response.status_code,
            "signal": ", ".join(signals),
            "redirect": redirect,
            "retry_after": response.headers.get("Retry-After"),
        }
        self._write_block_state(state)

    def print_status(self) -> None:
        """Print local cookie and cooldown state without contacting Scholar."""
        state = self._read_block_state()
        cookie_names = sorted({cookie.name for cookie in self.cookies})
        print(f"Cache: {self.cache_dir}")
        print(f"Cookies: {len(cookie_names)}"
              + (f" ({', '.join(cookie_names)})" if cookie_names else ""))
        if state is None:
            print("Cooldown: none")
            return
        retry_at = self._as_utc(state["retry_at"])
        now = datetime.now(timezone.utc)
        active = retry_at > now
        print(f"Cooldown: {'active' if active else 'expired'}")
        local_retry = retry_at.astimezone(ZoneInfo("America/New_York"))
        print(f"Retry at: {local_retry:%Y-%m-%d %H:%M:%S %Z}")
        print(f"Consecutive blocks: {state['consecutive_blocks']}")
        print(f"Last request: {state['request_kind']} · HTTP "
              f"{state['status_code']} · {state['signal']}")
        if state.get("redirect"):
            print(f"Redirect: {state['redirect']}")
        if state.get("retry_after"):
            print(f"Retry-After: {state['retry_after']}")

    def get(self, params: dict) -> tuple[requests.Response, bool]:
        """One GET against Scholar. Returns (response, blocked).

        Raises Unreachable on a network-layer failure (firewall / DNS / timeout)
        so the caller can tell "the packets never arrived" apart from "Scholar
        refused us" — the two need different fixes.
        """
        self._check_cooldown()
        headers = {
            "Referer": self.referer,
            "Sec-Fetch-Site": (
                "same-origin"
                if urlparse(self.referer).hostname == "scholar.google.com"
                else "cross-site"
            ),
        }
        try:
            r = self.session.get(
                BASE, params=params, headers=headers, timeout=TIMEOUT
            )
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as e:
            raise Unreachable(
                "could not reach scholar.google.com — suspect the firewall, not Scholar.\n"
                "  Google rotated its anycast IP out of the allowlisted CIDRs.\n"
                "  Fix: dig +short scholar.google.com, find which block it lands in,\n"
                "  add that CIDR to the Google/Scholar loop in .devcontainer/init-firewall.sh,\n"
                "  then re-run the firewall script (needs sudo / container rebuild)."
            ) from e
        self._save_cookies()
        self.referer = r.url
        blocked = (
            ("gs_captcha" in r.text)
            or ("/sorry/" in r.url)
            or (r.status_code == 429)
        )
        if blocked:
            self._record_block(r, params)
        elif r.ok:
            # A successful response is the only evidence that the block streak
            # ended. Merely waiting out the timer does not reset escalation.
            self.block_path.unlink(missing_ok=True)
            self.legacy_block_path.unlink(missing_ok=True)
        return r, blocked


CLIENT = ScholarClient()


def get(params: dict) -> tuple[requests.Response, bool]:
    """Issue a request through the process-wide stateful Scholar client."""
    return CLIENT.get(params)


def cluster_from_result(div) -> tuple[str | None, int | None]:
    """Extract (cluster_id, cite_count) from a result's footer links.

    Prefers 'Cited by N', which carries the id and the count together. Falls
    back to the 'All N versions' link: its cluster= id is the same id space as
    cites=, so it is the only handle on a record Scholar shows no Cited-by link
    for (an uncited paper, or a PDF scan indexed separately from the article).
    """
    versions = None
    for a in div.select("div.gs_fl a"):
        href = a.get("href", "")
        text = a.get_text()
        m = re.search(r"cites=(\d+)", href)
        if m and "Cited by" in text:
            n = re.search(r"Cited by\s+([\d,]+)", text)
            return m.group(1), int(n.group(1).replace(",", "")) if n else None
        v = re.search(r"cluster=(\d+)", href)
        if v and versions is None:
            versions = v.group(1)
    return versions, None


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


def search(query: str) -> list[dict]:
    """Run the seed search and return its hits, or exit with a reason."""
    r, blocked = get({"q": query, "hl": "en"})
    if blocked:
        sys.exit("BLOCKED searching — Scholar is CAPTCHA-ing this IP.")
    hits = parse_results(r.text)
    if not hits:
        # A 200 with no results and no CAPTCHA marker is Scholar's soft-empty
        # response; it comes and goes for the same query, so retry before
        # concluding the markup changed.
        sys.exit(f"No results parsed (HTTP {r.status_code}, {len(r.text)} bytes). "
                 "Scholar sometimes serves an empty page for a query that works "
                 "on retry — try again before suspecting the HTML structure.")
    return hits


def describe_cluster(cluster: str) -> dict | None:
    """Fetch a cluster's own record, so a pinned --cluster can be echoed back.

    Costs one GET. Returns None if Scholar blocks or the id resolves to nothing,
    which is a warning rather than a failure: the citer fetch can still proceed.
    """
    r, blocked = get({"cluster": cluster, "hl": "en"})
    if blocked:
        return None
    hits = parse_results(r.text)
    return hits[0] if hits else None


def fetch_citers(cluster: str, as_ylo: int, want: int, max_pages: int) -> tuple[list[dict], bool]:
    """Page through the citing set (year-windowed), collecting >= want candidates.

    Returns (candidates, blocked). Stops early on a block signal or empty page.
    """
    collected: list[dict] = []
    blocked = False
    for page in range(max_pages):
        # Pace the first citer GET too: describe_cluster/search -> cites= was
        # previously back-to-back, while only later citer pages were delayed.
        time.sleep(random.uniform(*REQUEST_DELAY))
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
    return collected, blocked


def cpy(row: dict) -> float:
    """Citations per year since publication (>=1 year to avoid div-by-zero)."""
    if not row["year"]:
        return 0.0
    elapsed = max(1, CURRENT_YEAR - row["year"])
    return row["cites"] / elapsed


# Outline rather than a table: titles are long enough that a Title column either
# wraps badly or gets truncated past the point of being useful.
INDENT = " " * 5  # matches the "%3d. " label, so wrapped lines stay aligned


def body_width() -> int:
    width = min(shutil.get_terminal_size((100, 24)).columns, 100)
    return max(30, width - len(INDENT))


def print_entry(i: int, title: str, *meta_lines: str) -> None:
    """One numbered outline entry: wrapped title, then wrapped indented lines."""
    body = body_width()
    lines = textwrap.wrap(title, width=body) or ["?"]
    print(f"{i:>3}. " + lines[0])
    for line in lines[1:]:
        print(INDENT + line)
    for meta in meta_lines:
        for line in textwrap.wrap(meta, width=body):
            print(INDENT + line)


def meta_line(row: dict) -> str:
    """'AUTHOR · YEAR · VENUE · N cites' for a parsed result."""
    return " · ".join([row["author"], str(row["year"] or "—"), row["venue"],
                       f"{row['cites']} cites"])


def print_hits(query: str, hits: list[dict], as_ylo: int) -> None:
    """Browse view: the search hits, each with the argument that pins it.

    All of it on stdout — in browse mode the listing is the output, and splitting
    it across streams would let the header and footer reorder around the rows.
    """
    sys.stderr.flush()
    print(f"Search: {query} — {len(hits)} hits\n")
    for i, row in enumerate(hits, 1):
        pin = (f"--cluster {row['cluster']}" if row["cluster"]
               else "no cluster id — Scholar offers no Cited-by or versions link")
        print_entry(i, row["title"], meta_line(row), pin)
        print()
    print(f"Pick the paper you meant, then: cited_by.py --cluster <id> "
          f"--since {as_ylo}")
    print("Nothing here? Scholar reshuffles between identical requests — retry, "
          "or add authors, the year, or the venue to the query.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("query", nargs="?",
                    help="Scholar search for the seed paper — title, title plus "
                         "authors, a DOI, or operators; prints the hits to pick from")
    ap.add_argument("--cluster", help="Scholar cluster id, to rank that paper's citers")
    ap.add_argument("--first", action="store_true",
                    help="skip browsing and seed on the top hit (echoed back on stderr)")
    ap.add_argument("--no-confirm", action="store_true",
                    help="with --cluster, skip the GET that echoes the seed's title")
    ap.add_argument("--since", type=int, default=None, metavar="YEAR",
                    help="earliest publication year to include, e.g. 2023 "
                         "(default: three years back)")
    ap.add_argument("--rank", choices=("cites", "cpy"), default="cites",
                    help="cites=total (default); cpy=citations per year")
    ap.add_argument("--top", type=int, default=25, help="how many to return (default 25)")
    ap.add_argument("--max-pages", type=int, default=5,
                    help="max Scholar pages to fetch (10 results each, default 5)")
    ap.add_argument("--status", action="store_true",
                    help="show local cookie/cooldown state without contacting Scholar")
    args = ap.parse_args()

    if args.status:
        conflicting = any([
            args.query,
            args.cluster,
            args.first,
            args.no_confirm,
            args.since is not None,
            args.rank != "cites",
            args.top != 25,
            args.max_pages != 5,
        ])
        if conflicting:
            ap.error("--status must be used by itself")
        CLIENT.print_status()
        return 0
    if args.first and not args.query:
        ap.error("--first seeds on a query's top hit, so it needs a query")
    if args.cluster and args.query:
        ap.error("--cluster pins the seed; drop the query")
    if not args.query and not args.cluster:
        ap.error("pass a query to browse, or --cluster to rank citers")

    # --since used to be a window width; catch stale invocations like "--since 3"
    # rather than silently asking Scholar for everything published since year 3.
    if args.since is not None and args.since < 1900:
        ap.error(f"--since takes a calendar year, not a window width (got {args.since})")
    as_ylo = args.since if args.since is not None else CURRENT_YEAR - 3

    # Browsing: print the hits and stop. Ranking options have nothing to act on
    # yet, so say so rather than letting them look applied.
    if args.query and not args.first:
        ignored = [f for f, used in (("--since", args.since is not None),
                                     ("--rank", args.rank != "cites"),
                                     ("--top", args.top != 25),
                                     ("--max-pages", args.max_pages != 5)) if used]
        if ignored:
            print(f"  ! {', '.join(ignored)} ignored while browsing — pass them "
                  "with --cluster in step 2", file=sys.stderr)
        print_hits(args.query, search(args.query), as_ylo)
        return 0

    if args.cluster:
        cluster = args.cluster
        seed = None if args.no_confirm else describe_cluster(cluster)
    else:
        hits = search(args.query)
        seed = hits[0]
        cluster = seed["cluster"]
        if not cluster:
            # The top hit is unpinnable (citation-only stub, OCR'd scan). The
            # hits are already in hand, so show them instead of dead-ending.
            print("--first cannot seed on the top hit: no cluster id. Browse "
                  "instead:\n", file=sys.stderr)
            print_hits(args.query, hits, as_ylo)
            return 1

    if seed:
        print(f"Seed: {seed['title']}\n"
              f"      {meta_line(seed)} · cluster {cluster}", file=sys.stderr)
    else:
        why = "--no-confirm" if args.no_confirm else "blocked or empty on lookup"
        print(f"Seed: cluster {cluster} (title unconfirmed: {why})", file=sys.stderr)
    print(f"Citers since {as_ylo}, ranked by "
          f"{'citations per year' if args.rank == 'cpy' else 'total cites'}.",
          file=sys.stderr)
    sys.stderr.flush()  # keep the seed banner above the rows when 2>&1 is piped

    # Fetch a ranking pool larger than --top so cpy re-ranking has headroom.
    want = max(args.top, 30)
    citers, _ = fetch_citers(cluster, as_ylo, want, args.max_pages)
    if not citers:
        print("No citing papers found in window.", file=sys.stderr)
        return 1

    key = cpy if args.rank == "cpy" else (lambda r: r["cites"])
    citers.sort(key=key, reverse=True)
    citers = citers[: args.top]

    for i, row in enumerate(citers, 1):
        meta = meta_line(row)
        if args.rank == "cpy":
            meta += f" ({cpy(row):.1f}/yr)"
        print_entry(i, row["title"], meta)
        print()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Unreachable as e:
        sys.exit(f"UNREACHABLE: {e}")
    except CoolingDown as e:
        sys.exit(f"COOLDOWN: {e}")
