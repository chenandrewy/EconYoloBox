# Scholar lit-review tool — design + firewall fix

Date: 2026-07-24 (NY)

## Goal

A lit-review helper that, given an "original paper" (`op`), finds the papers
that **cite it** and surfaces the most important ones **within a recent-year
window** — using **Google Scholar** as the source. Benchmark seed: McLean &
Pontiff 2016, JF, "Does Academic Research Destroy Stock Return Predictability?"

Complements the existing `.tools/dev/cited_by.py`, which already does
"most-cited papers that cite `op`" against the **OpenAlex** JSON API. Scholar
earns its place only where it differs from OpenAlex:

- **Freshness / grey literature** — Scholar indexes SSRN/NBER/arXiv working
  papers and their citations weeks-to-months before OpenAlex.
- **The canonical count** — in finance/econ the "Cited by N" people quote is
  the Scholar number; matching it matters for credibility.

## Tool design — `scholar_cited_by.py`

Mirror `cited_by.py`'s output contract (author / year / venue / title / cites)
but source from Scholar and tune for a recency window.

Mechanism (Scholar has no API; scrape the stable `cites=` URL pattern):

1. **Resolve `op` → cluster id.** Search the title; the top hit's footer has a
   `Cited by N` link whose href is `/scholar?cites=<CLUSTER_ID>&...`. The
   cluster id is Scholar's internal id merging a paper's versions. (For the
   benchmark, verify/hardcode it once so tests don't re-search each run.)
2. **Query the citing set, windowed by year:**
   ```
   https://scholar.google.com/scholar?cites=<CLUSTER_ID>&as_ylo=<year>&hl=en&start=<0,10,20,…>
   ```
   - `cites=`   → the citing-papers cluster
   - `as_ylo=YYYY` → lower year bound = our "past N years" (`as_yhi` optional)
   - `start=`   → pagination, 10/page; Scholar caps reachable results at ~1000
3. **Parse each result** (`div.gs_ri`): title + link (`h3.gs_rt a`), byline
   `div.gs_a` (authors · venue · year), snippet `div.gs_rs`, footer `div.gs_fl`
   → the `Cited by N` link gives both the citer's own cite count **and** its
   cluster id (so recursion / snowballing is free).
4. **Rank and cap.** Re-sort by cite count desc, take top ~25–50.

### Ranking flag `--rank {cites,cpy}`

"Most cited in the past N years" is biased: a 2018 paper had 6 years to
accumulate cites, a 2024 paper hasn't. Compute both:

- `cites` (default) — total `Cited by N`; the established follow-up literature.
- `cpy` — cites per year since publication; surfaces fast-rising recent work.

This knob is what keeps a recency window from just returning 2017 papers.

### Blocking discipline

- `requests` + `bs4` (both preinstalled). `scholarly` would be cleaner but is
  **not** installed → needs an explicit install OK; avoid for now.
- One page at a time, randomized delays, realistic UA.
- Stop immediately on block signals: `gs_captcha` in body, redirect to
  `/sorry/`, or HTTP 429. A **hang** = CAPTCHA; an **instant** failure = firewall
  (see below).
- Lean on Scholar's relevance sort + year filter for the top ~50 (can't page
  past ~1000 anyway).

### Open question — Scholar-only vs hybrid

OpenAlex **is** reachable and already does citation-sorted "who cites X." Option:
**hybrid** — OpenAlex for the ranked backbone, Scholar only to catch fresh
working papers OpenAlex hasn't indexed yet. More robust to the flakiness below.
Decision deferred; leaning hybrid for robustness.

## Firewall finding (the blocker) — and fix

The probe (`dev/scholar-probe/probe.py`) failed **instantly** with
`errno 113 No route to host`, not a hang → the **firewall** rejected the IP, not
a Scholar CAPTCHA. Root cause:

- `init-firewall.sh` resolves each host **once at container start**
  (`dig +short A`, ~line 130) and pins *those specific IPs* into the
  `allowed-domains` ipset; default policy is DROP.
- Scholar is served by `scholar.l.google.com`, **anycast that rotates IPs**.
  Now DNS returns `142.251.163.0/24`, which is **not** in the build-time pinned
  set → every connection dies with `No route to host`.
- arXiv/SSRN/OpenAlex don't hit this because their IPs are stable.

`scholar.google.com` is listed at `init-firewall.sh:119`, so it's "allowlisted"
in name only. Re-running the resolver just re-pins today's IPs and breaks again
on the next rotation — **not** a durable fix.

### Durable fix — widen to Google's serving CIDRs (decided)

The ipset is `hash:net` (line 50), so it takes CIDRs (GitHub ranges already are).
Add Google's Scholar-serving block **after** the domain-resolution loop (after
line 140, before the `HOST_IP` section). Observed `142.251.163.x` is covered by
`142.250.0.0/15` (spans 142.250.0.0–142.251.255.255):

```bash
# Google anycast blocks that serve scholar.google.com (scholar.l.google.com).
# The per-host dig above pins only the build-time IP; Google rotates the
# anycast address, so pin the ranges instead. Deliberately narrow — this is
# NOT "all of Google", just the blocks Scholar resolves into.
for gcidr in \
    "142.250.0.0/15" \
    "172.217.0.0/16" \
    "216.58.192.0/19"; do
    echo "Adding Google/Scholar range $gcidr"
    ipset add allowed-domains "$gcidr"
done
```

Tradeoff: these blocks also carry other Google services, so this loosens the
"rest of Google is blocked" intent slightly. Kept as narrow as possible
(three known Scholar-serving ranges, not Google's full AS). If we want to keep
it tightest, `142.250.0.0/15` alone covers today's resolution.

Requires rebuilding/re-running the firewall (container rebuild or re-run
`init-firewall.sh`) to take effect. Do NOT hand-edit the running ipset from the
tool — firewall changes go through this script.

## Validation harness

`dev/scholar-probe/probe.py` — ≤2 careful GETs: search seed title → extract
cluster id → fetch page 1 of recent citers (`as_ylo=2023`), printing the
McLean-Pontiff cluster id and the first page of citing papers. The moment the
firewall opens this validates every parsing assumption, and its parser becomes
the tool's core.

## Next steps

1. Apply the `init-firewall.sh` widen edit above; rebuild/re-run firewall.
2. Re-run `probe.py` → confirm reachable, capture McLean-Pontiff cluster id.
3. Build `scholar_cited_by.py` from the validated parser (output contract =
   `cited_by.py`; add `--rank {cites,cpy}`, `--since N`, `--top`).
4. Decide Scholar-only vs hybrid once we see Scholar's real reliability.
5. Once stable, promote from `dev/` to `.tools/dev/` (or `.tools/lit/`).
