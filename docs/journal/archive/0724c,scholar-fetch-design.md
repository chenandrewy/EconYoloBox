# Design: a single privileged `scholar-fetch` that widens, fetches, and closes

Date: 2026-07-24 (NY)

Third in the thread: [0724a] built the Scholar lit-review tool; [0724b] found the
**exfil problem** (Google's shared front-end fleet means any IP that reaches
Scholar also reaches Docs/Drive/Forms/GCS — IP allowlisting *cannot* separate
them). After that analysis we **reverted** the Google-anycast CIDR block from
`init-firewall.sh` to remove the exfil surface. This entry is the chosen way
forward.

**Decision:** add exactly **one** new privileged command — a root-owned,
node-unwritable `scholar-fetch` script that **opens a narrow egress window, does
the Scholar fetch itself, and closes the window**, all in one immutable action.
Not yet built; needs a rebuild to install (see below). The rest of this entry is
the spec plus the options we rejected and why.

---

## Why this shape (and not the obvious alternatives)

The whole design is driven by one adversary: a **rogue agent running as `node`**
(this is a box where an autonomous agent has code execution + read access to
`/workspace` and `LIBRARY`, so that's a real threat, not a hypothetical).

Key facts that forced the shape:

1. **IP layer can't express "Scholar not Docs."** Google routes by SNI/Host on a
   shared fleet; same IPs serve everything ([0724b]). So no `ipset`/`iptables`
   rule can allow Scholar while denying the exfil sinks.
2. **Same uid = same principal.** `cited_by.py` and a rogue agent both run as
   `node`. You cannot authenticate "the real script" to a privileged helper —
   every check (parent pid, path/hash, shared secret) is forgeable by a same-uid
   caller, and worse, `cited_by.py` lives in the **node-writable** bind mount, so
   "only through cited_by.py" = "through whatever node rewrote it to be."
3. **A bare `fw-open` primitive re-creates the hole.** If node can call
   "open the window" and *then* separately decide what runs during it, a rogue
   agent just opens + exfils. The privileged action must not hand node an open
   window it controls.

Therefore: **fuse** open+fetch+close into one immutable script. Node can
*trigger* a Scholar fetch but never *holds* an open window — during the entire
open interval, the only code running is the trusted script's own fetch. This is
the same trust model as the existing `init-firewall.sh`: root-owned, fixed
behavior, triggerable but not editable. Adding a *second* object of that kind is
not a new class of risk — the risk is entirely in what it does, and fusing is
what keeps it safe.

### The pleasant surprise: this dodges ECH

The proxy options (below) have a shelf life because **Encrypted Client Hello**
is hiding SNI on Google properties, which defeats an on-path SNI filter. But
`scholar-fetch` **is the client** — it enforces "Scholar only" by checking the
URLs *it constructs*, not by sniffing anyone's ClientHello. Client-side
enforcement doesn't care whether SNI is encrypted. So this design **sidesteps
ECH entirely**, which is the main reason it beats the proxy for our case.

---

## Hardening requirements (all mandatory)

1. **Immutable + root-owned** — script(s) at `/usr/local/bin/`, `root:root`,
   not writable by node (like `init-firewall.sh`). Node cannot edit behavior.
2. **Fixed invocation, arg is pure data** — node passes only a query/paper id;
   the script validates it (charset allowlist) and never interpolates it into a
   shell or URL path unencoded. No `-c`, no attacker-influenced `PYTHONPATH`.
3. **No programmability escape** — the fetch is a frozen script, not a hook into
   arbitrary code.
4. **Fuse open+fetch+close** — node never controls an open window.
5. **Owner-scope the window** — open egress only for the fetch's dedicated uid
   (`scholarbot`), so a *concurrent* rogue `node` process can't ride a window
   opened for the legit fetch.
6. **Window must self-close** — `trap` on exit + a hard `timeout` on the fetch +
   a **detached root watchdog** that removes the rule after N seconds regardless
   (covers `SIGKILL`, which skips the trap). A window that fails to close
   silently degrades to "Google open forever" — the worst case.
7. **In-code hostname allowlist** — the fetch refuses any host but
   `scholar.google.com` and does **not** follow cross-host redirects. This is the
   only thing pointing the (all-Google) window at Scholar — see residual risk.

---

## The one honest residual

The firewall window opens **all** of Google (owner-scoped to `scholarbot`, but
still IP-level all-Google, because shared fleet). The *only* thing keeping it on
Scholar is requirement (7), the script's own in-code host check. So **destination
safety rests on the frozen fetcher being SSRF/redirect-free.** A real proxy would
backstop this at the network; here there is no network backstop.

Mitigation: the fetcher is tiny, frozen, and auditable — hard-code "only ever GET
`scholar.google.com`," disable cross-host redirects, treat the id as data. Get it
right once; immutability locks it. For a single-user research box, trusting an
audited ~50-line frozen script is proportionate. **This is the thing to get
right.**

---

## Concrete sketch (spec, not yet installed)

### `/usr/local/bin/scholar-fetch` (root:root, 0755)
```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

QUERY="${1:?usage: scholar-fetch <query-id>}"
# (2) validate arg as pure data — reject anything but the expected charset
[[ "$QUERY" =~ ^[A-Za-z0-9:._ -]{1,200}$ ]] || { echo "bad query" >&2; exit 2; }

FETCH_UID="scholarbot"
# (5) narrow, hardcoded Google ranges Scholar rotates through (the set we removed
#     from init-firewall.sh); broad enough to survive rotation, destination is
#     policed in-code by (7), not by narrowing these.
RANGES=(142.250.0.0/15 172.217.0.0/16 173.194.0.0/16 216.58.192.0/19)

open_window()  { for r in "${RANGES[@]}"; do
    iptables -I OUTPUT -m owner --uid-owner "$FETCH_UID" \
             -d "$r" -p tcp --dport 443 -j ACCEPT; done; }
close_window() { for r in "${RANGES[@]}"; do
    iptables -D OUTPUT -m owner --uid-owner "$FETCH_UID" \
             -d "$r" -p tcp --dport 443 -j ACCEPT 2>/dev/null || true; done; }

# (6) belt: trap close on any exit; suspenders: detached root watchdog for SIGKILL
trap close_window EXIT
( sleep 180; for r in "${RANGES[@]}"; do
    iptables -D OUTPUT -m owner --uid-owner "$FETCH_UID" \
             -d "$r" -p tcp --dport 443 -j ACCEPT 2>/dev/null; done ) &
disown

open_window
# (4)(5) fetch runs as the unprivileged scoped uid; (6) hard time bound
timeout 120 runuser -u "$FETCH_UID" -- \
    python3 /usr/local/bin/scholar_fetch.py "$QUERY"
# EXIT trap closes the window here
```

### `/usr/local/bin/scholar_fetch.py` (root:root, 0755) — enforces (7)
- Only ever builds URLs against `scholar.google.com`.
- `allow_redirects=False` (or verify every hop's host is `scholar.google.com`).
- Query id used only as an encoded parameter, never as a path/host.
- Writes results to stdout / a file under `/workspace` (node-readable).

### `/etc/sudoers.d/scholar-fetch` (0440)
```
node ALL=(root) NOPASSWD: /usr/local/bin/scholar-fetch
```
No arg wildcards needed — arg validation lives in the script (requirement 2),
which is the right place for it.

### Dockerfile (the rebuild)
```dockerfile
RUN useradd --system --no-create-home --shell /usr/sbin/nologin scholarbot
COPY scholar-fetch scholar_fetch.py /usr/local/bin/
RUN chmod 0755 /usr/local/bin/scholar-fetch /usr/local/bin/scholar_fetch.py
COPY scholar-fetch.sudoers /etc/sudoers.d/scholar-fetch
RUN chmod 0440 /etc/sudoers.d/scholar-fetch
```
`init-firewall.sh` itself is **unchanged** (stays free of Google ranges); the
window is opened transiently by `scholar-fetch` and removed on close.

### Install reality
Placing a root-owned script + sudoers drop-in requires root → **rebuild** (or
host-side root). Cannot be self-granted from inside as node — same gate as every
privileged change here. After it's baked in, each fetch is in-flight.

### Rogue-agent check on the finished design
- Node invokes `scholar-fetch <id>` → triggers a fetch, gets Scholar data. ✓
- Node **can't ride the window** — owner-scoped to `scholarbot` (5).
- Node **can't inject into the window** — the immutable fetcher is the only thing
  running while it's open (4).
- Node **can't edit the fetcher** — root-owned (1).
- Window **can't leak open** — trap + timeout + watchdog (6).
- Remaining hole: an SSRF/redirect bug in the frozen fetcher (7). Audit once.

---

## Options considered (for the record)

Axes we varied: *where the fetch runs* · *what enforces "Scholar not Docs"* ·
*prevent vs detect* · *always-on vs just-in-time*.

- **1. Open all Google IPs.** Simplest, permanent. Reopens the full exfil surface
  we just removed. No caller/destination boundary at all. Rejected.
- **2. Lightweight SNI proxy.** On-path process reads plaintext SNI, allows only
  `scholar.google.com`, pipes the rest without decrypting. Real destination
  boundary, contains a rogue caller. **Temporary** — ECH is hiding SNI on Google.
- **4. MITM proxy.** Terminates TLS with a container-trusted cert, reads the real
  host after decrypting, re-encrypts onward. ECH-proof sibling of (2), but now
  decrypting *all* Google traffic in-box — heavy, its own trust surface.
- **3. Host-side tool + human monitoring.** Move the fetch out of the container
  entirely (host has open web), user watches, results land on the mounted disk.
  Sidesteps the firewall; precedent exists (`.host/`). Human-gated, higher
  friction, no in-container Google egress at all.
- **5. Non-Google citation source, narrowly allowed.** Single-purpose host (not a
  shared fleet) → safe to IP-allowlist, no proxy, no ECH clock. But OpenAlex
  quality was already rejected, and for **asset pricing/finance** the decisive
  gap is **grey-literature/working-paper** coverage (SSRN/NBER) that Scholar has
  and Semantic Scholar/Crossref cover weakly — so a source swap likely doesn't
  substitute. This is *why* we keep fighting for Scholar.
- **6. Detect, don't prevent.** Open Google but log every destination (a
  logging-only local proxy needs no root; or Claude/Codex hooks record
  open/close + what was fetched to the journal). Doesn't stop a rogue agent,
  makes leaks **auditable**. Cheap; pairs with anything.
- **7. Just-in-time window.** Widen only during a supervised fetch, then tear
  down. Shrinks exposure in *time*. But a bare open/close primitive fails the
  rogue-agent test (node opens + exfils). **The chosen design is the hardened
  fusion of (7)**: (7)'s time-boxing + owner-scoping (from the proxy work) +
  an in-code host allowlist (client-side, so ECH-immune) + immutability.

### Honest caveat that limits *every* option
The box already carries other egress channels — **Sentry** (arbitrary payloads),
the **LLM APIs**, all **GitHub ranges** — so no single firewall change seals it
against a determined insider ([0724b]: "never sealed against a determined
exfiltrator"). What these options buy down is **opportunistic** phone-home and
**accidental** exposure; the realistic posture for this box is
*prevent-the-easy-path + detect + don't overexpose the crown jewels*, not a hard
network seal. The chosen design is the strongest *prevention* we can get on the
Google path specifically without a proxy daemon or the ECH liability.

---

## Status / next

- **Proposal only.** Nothing touches root yet.
- To land: write the two scripts + sudoers + Dockerfile lines, then a **rebuild**.
- Open question before building: is the fetcher's Scholar-only discipline (7)
  something we're confident we can freeze and audit? That's where the residual
  risk concentrates.
- Consider pairing with **(6)** logging regardless — cheap audit trail, and it's
  the thing that covers the residual we can't fully prevent.

[0724a]: 0724a,scholar-lit-review.md
[0724b]: 0724b,firewall-exfil-risk.md
