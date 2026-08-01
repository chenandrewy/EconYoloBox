# .tools/lit

Literature tools. Each one's docstring (`--help`) is the usage reference; this
file holds the background that would otherwise bloat it.

## Citation lookup

`cited_by.py` answers "what has cited this paper?" from OpenAlex. A "follow-up"
is any work citing the seed paper.

> **Google Scholar does not work from inside this sandbox.** Scholar CAPTCHA-blocks
> the container's IP, and no amount of client-side politeness has cleared it —
> see [Scholar is blocked](#google-scholar-is-blocked-parked-tool) below. The
> Scholar tool is parked in `dev/gscholar_cited_by.py` (gitignored, not on
> `PATH`). Do not reach for it as a fallback; it is the thing that is broken.
> Use `cited_by.py` for citation lookup.

### `cited_by.py` (OpenAlex)

Takes a DOI (raw, `doi:` form, or `https://doi.org/...` URL) and sorts citers by
citation count. Reads `OPENALEX_API_KEY` through the shared credential resolver
when present, anonymous otherwise; OpenAlex authenticates via `?api_key=`,
**not** a Bearer header — sending `Authorization: Bearer` hard-fails with 401.

```
cited_by.py "the positive economics of methodology"   # browse
cited_by.py 10.1006/jeth.1996.0004                    # rank its citers
```

Preprints work the same way, each platform minting its own DOI. The preprint and
the published version are usually separate OpenAlex records with separate
citation counts. See the script's docstring for the per-platform DOI patterns
(SSRN, NBER, arXiv).

**No DOI in hand?** Pass a title and it browses: the hit list carries the DOI or
OpenAlex W-id that pins each record, and you re-run with that. Browsing is the
default rather than an auto-pick because the top hit is regularly the wrong
paper. A title query for the Kahn-Landsburg-Stockman JET paper returns Friedman's
*The Methodology of Positive Economics* and two of its reprints above it, purely
on citation weight.

The W-id seed also covers records that carry no DOI at all — older articles,
book chapters, some working papers.

**What you give up without Scholar.** OpenAlex trails Scholar on working papers:
Scholar indexes SSRN/NBER/arXiv drafts and their citations weeks-to-months
earlier, and it produces the canonical "Cited by N" count people quote in
finance/econ. For a recent or unpublished paper, treat an OpenAlex count as a
floor, and check the paper's own SSRN/NBER page or ask the user to run a Scholar
search on the host.

## Google Scholar is blocked (parked tool)

Scholar has no API, so `dev/gscholar_cited_by.py` scrapes the `cites=` URL
pattern. As of 2026-07-31 the sandbox IP is CAPTCHA-blocked and the tool cannot
complete a run. Two rounds of hardening did not fix it, which is the useful
result: **the block is site-side and IP-scoped, not a matter of request
shaping.** The same queries succeed from a browser on the host.

What the hardened client already does — persistent `requests.Session` with
Scholar cookies in `$XDG_CACHE_HOME/sandbox-lit/`, a coherent Chrome navigation
header set, same-origin referrer, 3–6s waits before every citer page, immediate
stop on a block signal (`gs_captcha`, a `/sorry/` redirect, or HTTP 429), and a
1h→6h→24h cooldown escalation that refuses to contact Scholar while active. Run
`gscholar_cited_by.py --status` to inspect cookies and block state without
making a request.

None of that clears a CAPTCHA or lifts a site-wide restriction on an IP. Adding
more of it is not the fix.

**Before reviving it**, note two things that are easy to misread as bugs:

- Scholar has a *soft* refusal: HTTP 200, no CAPTCHA marker, no results in the
  body. It comes and goes for the same query, so `No results parsed` means retry
  before suspecting the HTML structure.
- An *instant* failure rather than a hang is the firewall, not Scholar.
  `scholar.l.google.com` is Google anycast whose IPs rotate, and the allowlisted
  CIDRs in `.devcontainer/init-firewall.sh` must cover the current one. The
  script raises `UNREACHABLE:` with the fix in the message. Editing the firewall
  needs sudo — ask the user rather than doing it unprompted.

The tool sits in `dev/` because `dev/` is gitignored: it is out of the repo but
still on disk. The last version that was under version control is in the
`Harden Scholar citation requests and backoff` commit, if it needs recovering.
