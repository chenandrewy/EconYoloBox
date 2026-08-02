# Host browser is clean while the tool is blocked; plan to add a container browser

Date: 2026-07-31 23:33 EDT

Follows [0731a,scholar-block-hardening.md](0731a,scholar-block-hardening.md).
One new test, a revised interpretation, some request accounting, and a decision
to build a browser into the devcontainer.

## The new test

The user opened Google Scholar in the **host browser** and got no CAPTCHA, at a
point when `cited_by.py` had been blocked on a plain `q=` search hours earlier
(23:00 EDT, recorded in 0731a).

The container shares the host's public IP. Docker NATs container egress through
the host network stack, so Scholar sees one address for both clients. Barring a
VPN or proxy on only one side — there is none here — the two requests came from
the same place.

## Interpretation

The July 31 entry's leading reading was that "the current IP/session is under a
broader Scholar restriction." **That is now largely falsified.** If the flag
were attached to the address, the host browser would be expected to see at
least some friction, and it saw none.

What the evidence supports instead is narrower: Scholar is refusing *this
client*, not this address. The two clients differ in ways that are visible to
Scholar and are not fixable by the header work already done in `63c4340`:

- **Transport fingerprint.** `requests` presents an OpenSSL cipher ordering, no
  HTTP/2, and no Chrome ALPN/JA3 profile. Coherent `Sec-Fetch-*` and
  `User-Agent` headers do not reach that layer.
- **Account state.** The host browser almost certainly carries a signed-in
  Google `SID`/`HSID`. The tool persists only anonymous `NID` and `GSP`.

Both of these are inference. Scholar publishes no decision rule, and nothing
here was measured directly — the test establishes the *asymmetry* between the
two clients, not its mechanism.

### The "it worked before" window was four days, not longer

Git dates narrow the baseline considerably:

| Commit | Date | Relevance |
|---|---|---|
| `96c01e1` | 07-26 | converted `cited_by.py` to Scholar; everything earlier was OpenAlex |
| `b799d3d` | 07-30 | "Browse and pick the seed instead of guessing" — adds a `q=` GET ahead of the cluster/cites work |
| first block | 07-30 | ~17:55 EDT |

So there was never a long healthy Scholar baseline that suddenly broke. There
were roughly four days of light use. And `b799d3d` raised requests-per-lookup
on the same day the first block appeared. That is a dated coincidence plus a
plausible mechanism — **not** established causation. There is no request log
for 07-26 through 07-29 to compare against.

This also undercuts 0730a's "it was not volume, four requests is nothing"
reasoning, which counted a single session under the new, heavier pattern.

### Request accounting

Read from `.tools/lit/cited_by.py` as it stands. `--max-pages` defaults to 5;
paging stops early once `want = max(--top, 30)` rows are collected (~3 pages at
10/page) or a page comes back empty. Each citer page sleeps 3–6s first.

| Invocation | GETs |
|---|---|
| `cited_by.py "query"` (browse) | 1 (`q=`) |
| `--cluster N` | up to 6 (1 confirm + 5 citer pages) |
| `--cluster N --no-confirm` | up to 5 |
| `--first "query"` | up to 7 |

Absolute volume is low. The *shape* is the conspicuous part: `cites=<id>&start=0,10,20,…`
walked in ~20 seconds is a recognizable automated pattern regardless of count.

Unimplemented and undecided: lowering the `--top` / `--max-pages` defaults would
roughly halve a typical lookup's footprint. Noted, not done.

## What this entry deliberately does not conclude

The user's requirement for the tool is unchanged and modest: slow, unburdensome,
convenient Scholar access without clicking and copy-pasting. OpenAlex is not a
substitute for that purpose and was not treated as one.

No claim is made here about whether or when access returns, or about what would
restore it. The prohibitions from 0731a still stand — no user-agent rotation, no
proxy cycling, no automated CAPTCHA solving, no deleting block cookies.

One operational note that is not a solution claim: every refused probe is itself
a data point Scholar counts, and it deepens the tool's own backoff. Frequent
checking is worse than infrequent checking.

## Decision: build a browser into the devcontainer

Agreed next step, scoped deliberately to **one thing** — build the browser. It
serves two purposes, and the second stands on its own.

**As investigation.** A real browser engine removes the transport-level
difference described above, which makes it an instrument for testing the
client-vs-address interpretation rather than an assumed fix. It also gives a
human a way to answer a challenge if one is presented — a person solving a
CAPTCHA shown to them is the intended use of a CAPTCHA, and is categorically
different from solving one programmatically.

**As container investment.** Headless Chromium plus screenshots lets an agent
see rendered UI instead of inferring it from code and DOM assertions. That
applies to ChatRender's webview and to any local dev server; `localhost` is
unaffected by the firewall. This value does not depend on Scholar at all.

### Build plan

1. **Dockerfile:** `npx playwright install --with-deps chromium`, at *build*
   time. Two traps this avoids: Ubuntu 24.04's `chromium` apt package is a snap
   stub that does not work in a container, and `cdn.playwright.dev` is not
   allowlisted — `init-firewall.sh` runs at container start, so the download
   must happen while the build still has open network.
2. **`install-packages.sh`:** `pip install playwright`. PyPI is allowlisted, so
   runtime is fine.
3. **`desktop-lite` feature:** Xvfb + noVNC on `localhost:6080`, so a human can
   see and click. Needed only for the human-in-the-loop case; headless testing
   does not require it.
4. **Named volume for the browser profile,** following the existing volume
   pattern, so profile state survives container recreation.

Open questions at the time of writing: whether to include step 3 now or start
headless-only, and whether `--with-deps` pulling several dozen apt libraries is
acceptable. This is a rebuild plus new system packages, so it needs explicit
authorization before implementation.

If the browser path is taken further later, the design that avoids cookie
transplanting is to let the browser *be* the client for Scholar requests, rather
than moving cookies from it into `cited_by.py`. Recorded as a design constraint,
not as a plan.
