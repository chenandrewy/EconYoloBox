# cited_by.py CAPTCHA block — evidence, guesses, and the OpenAlex fallback fix

Date: 2026-07-30 17:55 EDT

Snapshot from a lit lookup that got blocked mid-task. Half of this is inference;
marked as such where it is.

## What happened

Task: find papers citing Kahn, Landsburg & Stockman, "The Positive Economics of
Methodology," JET 1996.

The browse step worked fine:

```
cited_by.py "kahn landsburg stockman"
  → hit 1, --cluster 5179910145110411934, 1996, JET, 16 cites
```

Both attempts at the citing set died:

```
cited_by.py --cluster 5179910145110411934 --since 1996
  ! blocked on page 1; ranking 0 so far
cited_by.py --cluster ... --since 1996 --no-confirm    # ~20s later
  ! blocked on page 1; ranking 0 so far
```

Tool behaved correctly throughout — detected the block on the documented signals
(`cited_by.py:87`), stopped instead of hammering, ranked what it had (nothing).
No code defect. Nothing to fix in the block handling.

## The evidence worth keeping

~4 GETs total across the whole session. `/scholar?q=` **succeeded**; both
`cites=` fetches **blocked**.

So it was not volume. Four requests is nothing. It was the **endpoint**.

> Stated too firmly, and the request tally above is incomplete — see the
> 07-31 addendum at the bottom before relying on this.

Reading of that (inference — Scholar publishes no rules): paging a citing set is
*the* scraper signature. A human reads a search page. A bot walks
`cites=<id>&start=0,10,20…`. That's the pattern worth rate-limiting and it's the
one we present. Expect `cites=` to stay touchier than search indefinitely; budget
accordingly.

## Why our client looks automated (all inference, ranked by hunch)

- **No cookies.** Every request is a bare `requests.get` (`cited_by.py:78`) — no
  `Session`, no jar, nothing persisted between runs. Scholar sets `NID`/`GSP` on
  first contact and expects them back. We are a brand-new stranger on every
  single request, which no real browser ever is. Biggest lever, I think.
- **No `Referer`.** We land on `cites=` from nowhere. In a browser that URL is
  only reachable by clicking a "Cited by" link on a page you were already on.
- **Self-contradicting fingerprint.** `HEADERS` is UA + `Accept-Language` only
  (`cited_by.py:48`). The UA claims Chrome 125; Chrome also sends `Accept`,
  `Sec-Fetch-*`, `Sec-Ch-Ua`. Claiming Chrome while sending none of Chrome's
  other headers is arguably *more* anomalous than an honest UA would be.
- **Back-to-back GETs.** The 3–6s sleep only fires *between* citer pages
  (`cited_by.py:212`). `describe_cluster` → citer page 1 goes out with zero gap.
- **Egress IP reputation.** Container exits via the host IP. If that address or
  its range carries scraper history, the budget is small before any of the above
  matters. Not fixable in code, and not observable from in here.

## Mitigations, not yet implemented

Rough payoff order:

1. `requests.Session` + a cookie jar persisted to disk across runs.
2. Send `Referer`; reach `cites=` after a search rather than cold.
3. Extend the delay to cover the *first* citer GET, not just page-to-page.
4. Fill out headers to match the claimed UA.
5. Block-state file: record a block timestamp, refuse to retry for 30–60 min.

`--no-confirm` already drops one GET and exists.

**Own goal:** I retried 20s after the first block. That's inside any plausible
cooldown — probably deepened it rather than testing it. Item 5 exists to stop
exactly that reflex.

**Rejected:** UA rotation (varying UA while cookies + TLS fingerprint stay
constant is *more* incoherent, not less). Also rejected: CAPTCHA-solving
services and proxy rotation — that's circumventing an access control, a
different thing from being a better-behaved client.

## What actually got fixed instead

Fell back to OpenAlex and hit a second problem: `openalex_cited_by.py` took a
**DOI only**. Had a title and authors, no DOI. Its own docstring conceded the
gap ("search OpenAlex directly at ..."), so I hand-wrote that curl. Documented
manual step in the fallback path, hit on first real use.

Fixed — the seed arg now accepts a **title query** or an **OpenAlex W-id**
alongside a DOI. Title browses and prints each hit's pinning id; re-run with it.
`--first` opts into auto-pick, `--hits N` sets list length. W-id also unlocks the
many OpenAlex records carrying no DOI (older articles, chapters, some WPs),
previously unreachable here.

Two findings from testing:

- **Browse-by-default earned its keep immediately.** For "the positive economics
  of methodology", hit 1 is *Friedman's* "The Methodology of Positive Economics"
  — word order flipped. `--first` confidently returns the wrong paper's citers.
  KLS is hit 4. Same failure mode `cited_by.py` already documents for Scholar.
- **I had the sort backwards.** Wrote it sorting hits by cites, with a comment
  justifying that. It buried KLS (11 cites) at hit **11**, under Friedman's 1573
  and two reprints — off the default page entirely. OpenAlex's default relevance
  sort honors word order, puts KLS at hit **4**. Switched; the counterexample is
  now in the code comment so nobody "tidies" it back.

Also **rejected**: auto-falling-back Scholar → OpenAlex on block. Tempting, but
same seed gave 16 cites (Scholar) vs 11 (OpenAlex), and the corpora differ where
it matters — Scholar indexes SSRN/NBER WPs, OpenAlex largely doesn't. A tool that
silently switches source yields a list you can't attribute, and the ~5 missing
items would be the newest/least-published, i.e. where you'd notice the absence
least and care most. Keep the two commands separate; provenance stays legible.

README table row + the go-hand-query-the-API paragraph updated.

## Open

- Scholar hardening (items 1–5) not done — separate call.
- KLS citing set still OpenAlex-only, 11 of Scholar's 16. Retry Scholar later for
  the ~5 working papers; block may have aged out by then.

---

## Addendum — 2026-07-31 09:59 EDT

Walking back through the session turned up a better piece of evidence than the
one recorded above, and a reason to hold the conclusion more loosely. Body left
as written; this is what we know a day later.

### The tally above was missing a request

Step "2" was two GETs, not one. `describe_cluster` (`cited_by.py:174`) runs
before the citer fetch, and **it succeeded** — the run echoed the record back
("JA Kahn et al. · 1996 · Elsevier · 16 cites"), which can only come from a
fetched page. Note it parsed the venue as "Elsevier" where the search said
"Journal of Economic Theory": a different page, so a genuinely separate round
trip. Full sequence:

| # | Parameter | Result |
|---|---|---|
| 1 | `q=kahn landsburg stockman` | OK |
| 2 | `cluster=5179910145110411934` | OK |
| 3 | `cites=5179910145110411934&as_ylo=1996&start=0` | blocked |
| 4 | `cites=5179910145110411934&as_ylo=1996&start=0` | blocked |

Requests 2 and 3 carry **the same id** — `cluster=` and `cites=` share one id
space. Same number, same session, seconds apart, one allowed and one refused.
That's a sharper argument for "the parameter is what matters" than the
search-vs-cites contrast in the body, because it holds the id fixed.

### But it's confounded, and the body doesn't say so

The two blocked requests were also the two *latest* in the sequence. A plain
cooldown that began after request 2 produces byte-identical output. So the
evidence is consistent with both:

- **H1** — `cites=` is guarded harder than `cluster=` (the body's claim).
- **H2** — we crossed a session/IP threshold after request 2, and the parameter
  is irrelevant.

**The test that separates them:** issue a `cluster=` fetch *while blocked*. If it
returns a record, H1. If it's refused too, H2. Cheap — one GET — but it spends a
request against an already-annoyed endpoint, so pair it with the next real
lookup rather than probing for its own sake.

Worth resolving before building any of mitigations 1–5, since H2 would make the
per-endpoint reasoning moot and push everything toward pacing and backoff.

