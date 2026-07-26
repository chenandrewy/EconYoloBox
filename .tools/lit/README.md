# .tools/dev

Experimental scripts. Each one's docstring (`--help`) is the usage reference;
this file holds the background that would otherwise bloat it.

## Citation lookup

Two scripts answer the same question — "what has cited this paper?" — from
different sources. A "follow-up" is any work citing the seed paper.

| | `cited_by.py` | `openalex_cited_by.py` |
|---|---|---|
| Source | Google Scholar (scraped) | OpenAlex API |
| Seed | search query or cluster id | DOI |
| Strength | freshness, canonical counts | stable, structured, no blocking |

### `cited_by.py` (Google Scholar)

Scholar earns its place two ways: it indexes SSRN/NBER/arXiv working papers —
and their citations — weeks-to-months before OpenAlex, and it produces the
canonical "Cited by N" count people quote in finance/econ.

It resolves the seed to Scholar's internal cluster id, pulls the citing set
windowed by `--since`, and ranks the top results.

**Choosing the seed.** `query` goes verbatim into Scholar's `?q=`, so it is not
restricted to a title: title plus author names, a DOI or arXiv id, and operators
such as `author:"chen"` or `source:"journal of finance"` all work. Quote the
whole thing so the shell keeps it as one argument. Only the first hit is used
and there is no confirmation prompt, so a vague query silently analyzes the
wrong paper — prefer a distinctive query, read back the `Seed:` line on stderr,
and once you know a paper pass `--cluster` to pin it exactly.

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

**Firewall.** An *instant* failure rather than a hang means the firewall, not
Scholar. `scholar.l.google.com` is Google anycast whose IPs rotate, and the
allowlisted CIDRs in `.devcontainer/init-firewall.sh` must cover the current
one. The script raises `UNREACHABLE:` with the fix in the message: `dig +short
scholar.google.com`, find the block it lands in, add that CIDR to the
Google/Scholar loop, and re-run the firewall script. That needs sudo — ask the
user rather than editing the firewall unprompted.

### `openalex_cited_by.py` (OpenAlex)

Takes a DOI (raw, `doi:` form, or `https://doi.org/...` URL) and sorts citers by
citation count. Reads `OPENALEX_API_KEY` from the env when present, anonymous
otherwise; OpenAlex authenticates via `?api_key=`, **not** a Bearer header —
sending `Authorization: Bearer` hard-fails with 401.

Preprints work the same way, each platform minting its own DOI. The preprint and
the published version are usually separate OpenAlex records with separate
citation counts. See the script's docstring for the per-platform DOI patterns
(SSRN, NBER, arXiv). Drafts without a DOI aren't reachable through the script —
search OpenAlex directly at `https://api.openalex.org/works?search=<title>`.

## `cited_by.py` vs `openalex_cited_by.py`

Reach for Scholar when the paper is recent or unpublished, or when you want the
citation count a referee would recognize. Reach for OpenAlex when you want
structured, reproducible output, when the seed has a DOI, or when Scholar is
CAPTCHA-ing.
