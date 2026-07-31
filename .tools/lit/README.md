# .tools/lit

Literature tools. Each one's docstring (`--help`) is the usage reference; this
file holds the background that would otherwise bloat it.

## Citation lookup

Two scripts answer the same question — "what has cited this paper?" — from
different sources. A "follow-up" is any work citing the seed paper.

| | `cited_by.py` | `openalex_cited_by.py` |
|---|---|---|
| Source | Google Scholar (scraped) | OpenAlex API |
| Seed | search query or cluster id | search query, DOI, or W-id |
| Strength | freshness, canonical counts | stable, structured, no blocking |

### `cited_by.py` (Google Scholar)

Scholar earns its place two ways: it indexes SSRN/NBER/arXiv working papers —
and their citations — weeks-to-months before OpenAlex, and it produces the
canonical "Cited by N" count people quote in finance/econ.

**Two steps: browse, then pick.** A bare query prints the search hits, each with
the `--cluster <id>` argument that pins it; you re-run with the id of the paper
you meant, and that run pulls the citing set windowed by `--since` and ranks it.

```
cited_by.py "kahn landsburg"                              # browse
cited_by.py --cluster 5179910145110411934 --since 1996    # rank its citers
```

The split exists because Scholar cannot be trusted to rank the paper you mean
first. It reshuffles between *identical* requests — the same author query put the
target at hit #1 on one run and off the first page on the next — and for some
papers the record is absent from the results while its citers and OCR'd
working-paper scans are present. No first-hit rule or title-similarity heuristic
survives that; an eye on ten rows does. Browsing costs the one search GET the
tool would spend anyway, and it never burns `cites=` pages on a paper you didn't
want, which matters because CAPTCHA risk scales with request count.

`--first` keeps the old one-shot behavior for a query distinctive enough to
trust. `--cluster` echoes the pinned paper's title, year, venue, and cite count
back on stderr (one extra GET, skippable with `--no-confirm`) so a wrong id is
visible in the first line of output instead of silently poisoning the ranking.

**Choosing the seed.** `query` goes verbatim into Scholar's `?q=`, so it is not
restricted to a title: title plus author names, a DOI or arXiv id, and operators
such as `author:"chen"` or `source:"journal of finance"` all work. Quote the
whole thing so the shell keeps it as one argument. Note that an exact-phrase
title query is often *worse* than author names, because the phrase matches the
full text of the paper's citers.

The search sends no corpus parameters, deliberately. Citation-only records are
already included — Scholar's "include citations" checkbox comes back checked on a
bare query, and `as_vis=1` is the opt-*out* (`as_vis=0` is the default, so sending
it does nothing). An `as_sdt` value is normalized away: pass `2000005` and every
link Scholar generates on the returned page still says `as_sdt=0,21`.

**Cluster ids.** `cites=<id>` and `cluster=<id>` share one id space, so the
"All N versions" link is a second source of the seed id — that is the only handle
on a record Scholar shows no "Cited by" link for (an uncited paper, or a PDF scan
indexed apart from the article). A row listed with no cluster id offers neither
link and cannot be used as a seed.

**Ranking.** A recency window is biased toward older papers: a 2020 paper has
had more years to accumulate cites than a 2025 one. `--rank cpy` re-scores by
citations-per-year to surface fast-rising fresh work; `--rank cites` (the
default) gives the established follow-ups.

**Output** is an outline — title first, then author / year / venue / cites
indented beneath — because titles are too long to sit in a table column. It
wraps to the terminal width, capped at 100 columns.

**Blocking.** Scholar has no API; this scrapes the stable `cites=` URL pattern
with a realistic UA, one page at a time with randomized delays. It stops
immediately on a block signal (`gs_captcha` in the body, a `/sorry/` redirect,
or HTTP 429) and ranks whatever it collected so far, so a blocked run still
prints partial results. Keep `--max-pages` modest to stay under the radar.

Scholar also has a softer refusal: HTTP 200, no CAPTCHA marker, no results in the
body. It comes and goes for the same query, so `No results parsed` means retry
first — suspect the HTML structure only if a retry fails too.

**Firewall.** An *instant* failure rather than a hang means the firewall, not
Scholar. `scholar.l.google.com` is Google anycast whose IPs rotate, and the
allowlisted CIDRs in `.devcontainer/init-firewall.sh` must cover the current
one. The script raises `UNREACHABLE:` with the fix in the message: `dig +short
scholar.google.com`, find the block it lands in, add that CIDR to the
Google/Scholar loop, and re-run the firewall script. That needs sudo — ask the
user rather than editing the firewall unprompted.

### `openalex_cited_by.py` (OpenAlex)

Takes a DOI (raw, `doi:` form, or `https://doi.org/...` URL) and sorts citers by
citation count. Reads `OPENALEX_API_KEY` through the shared credential resolver
when present, anonymous
otherwise; OpenAlex authenticates via `?api_key=`, **not** a Bearer header —
sending `Authorization: Bearer` hard-fails with 401.

Preprints work the same way, each platform minting its own DOI. The preprint and
the published version are usually separate OpenAlex records with separate
citation counts. See the script's docstring for the per-platform DOI patterns
(SSRN, NBER, arXiv).

**No DOI in hand?** Pass a title and it browses, same two-step as `cited_by.py`:
the hit list carries the DOI or OpenAlex W-id that pins each record, and you
re-run with that. The browse step is the default rather than an auto-pick for
the same reason it is in `cited_by.py` — the top hit is regularly the wrong
paper. A title query for the Kahn-Landsburg-Stockman JET paper returns Friedman's
*The Methodology of Positive Economics* and two of its reprints above it, purely
on citation weight.

The W-id seed also covers records that carry no DOI at all — older articles,
book chapters, some working papers — which were previously unreachable here.

## `cited_by.py` vs `openalex_cited_by.py`

Reach for Scholar when the paper is recent or unpublished, or when you want the
citation count a referee would recognize. Reach for OpenAlex when you want
structured, reproducible output, when the seed has a DOI, or when Scholar is
CAPTCHA-ing.
