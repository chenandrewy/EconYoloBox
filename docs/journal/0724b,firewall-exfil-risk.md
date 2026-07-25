# Firewall, Google anycast, and the exfil-risk question

Date: 2026-07-24 (NY)

Follow-on to [0724a] (Scholar lit-review tool). That entry fixed *reachability*;
this one is about the **security tradeoff** the fix exposes, and why I'm now wary
of the obvious "just widen to all of Google" move.

## The core problem, restated

The firewall is `iptables` + an `ipset` (`hash:net`, so it takes CIDRs). It's
**deny-by-default egress**: default policy DROP, one ACCEPT rule matching the
`allowed-domains` set, then an explicit REJECT (so blocked calls fail *instantly*
with `errno 113`, not hang).

Domains in the config are resolved to IPs **once, at container build**
(`dig` loop). That's fine for stable hosts (arXiv, SSRN, WRDS) but breaks for
Google Scholar, because `scholar.google.com` → CNAME `scholar.l.google.com` →
**anycast**: one name, a large rotating pool of IPs across several Google blocks.
The build-time pin goes stale on the next rotation → `No route to host`.

Observed rotations in a single afternoon:
`142.251.163.x` → `142.251.41.x` → `173.194.45.x` → `142.251.211.x`.

## Two ways to fix reachability

1. **Narrow CIDRs (current).** Pin the blocks Scholar rotates through:
   `142.250.0.0/15`, `172.217.0.0/16`, `216.58.192.0/19`, and I added
   `173.194.0.0/16` this session. Robust *within* a listed block; breaks when
   Scholar hops into an unlisted one → reactive whack-a-mole. (Two rotations
   needed patching in one afternoon.)
2. **Import `goog.json`.** `https://www.gstatic.com/ipranges/goog.json` — Google's
   published range list, 99 IPv4 CIDRs, self-updating, mirrors exactly how the
   script already handles GitHub (`api.github.com/meta`). Fetchable during the
   build's open window. Covers Scholar and self-heals every rotation. This is the
   clean, no-whack-a-mole answer.

**Key distinction:** `goog.json` = Google's *first-party services*. Google also
publishes `cloud.json` = GCP *customer* ranges (arbitrary rented VMs). We would
import `goog.json` only, **never** `cloud.json` — the latter would open a
rent-a-C2-endpoint surface. That boundary is what keeps `goog.json` sane.

## The exfil concern (why I stopped and flagged this)

`goog.json` doesn't just add YouTube/Scholar. It opens the **programmable**
Google first-party services that double as easy exfiltration sinks:
- `docs.google.com` — and Google **Forms** live here; an unauthenticated
  `POST` to someone else's Form is the classic exfil channel.
- `drive.google.com`, `storage.googleapis.com` (GCS), `script.google.com`
  (Apps Script), Firebase — all programmable relays into an attacker's account.

YouTube/Search/Maps themselves are ~harmless (consumption endpoints, uploads
need auth). The risk is entirely the programmable set above.

### The finding that reframes the whole decision

I checked whether we could allow Scholar but keep the exfil services out. **We
can't — and the reason is architectural, verified live:**

- Google serves nearly everything from **one shared front-end fleet, routed by
  the hostname (TLS SNI / Host header), not by IP.** The same IP serves Scholar
  or Drive depending only on which host you asked for.
- Confirmed by resolution: at one point `142.251.211.0/24` was **simultaneously
  serving `scholar.google.com`, `drive.google.com`, and `storage.googleapis.com`**
  (Scholar `.196`, Drive `.142`, GCS `.123/.155/...`). Earlier, Scholar and GCS
  were both in `173.194.45.x`.
- The exfil services **rotate too** (GCS returned 16 IPs across many /24s), and
  through the *same* blocks as Scholar.

Consequences:
1. **IP-level allowlisting fundamentally cannot separate Scholar from
   Docs/Drive/Forms/GCS.** They are the same IPs. Not a tuning problem — a
   layer problem.
2. **The narrow CIDRs already in the script ALREADY whitelist those exfil
   services** (Docs is in `172.253/16`, Drive/GCS in `142.250/15` + `173.194/16`,
   etc.). We took on the exfil surface the moment we added `142.250.0.0/15` —
   not something we'd newly incur by importing `goog.json`.
3. Therefore **narrow-CIDRs vs `goog.json` is ~zero marginal exfil difference.**
   The "keep it narrow to stay safe" instinct is largely illusory here: narrow
   doesn't keep Forms/Drive out. `goog.json` just also self-heals rotation.

So my exfil worry is real, but it is **not** addressed by choosing narrow over
`goog.json`. The honest framing:
- The container already carries comparable general channels: **all of GitHub's
  ranges**, **Sentry** (arbitrary event payloads), the **LLM APIs**. It was
  never sealed against a determined exfiltrator.
- For a single-user *research* box, opportunistic phone-home from a bad
  dependency stays blocked (random C2 ≠ Google), which is the realistic threat
  the firewall actually buys down.

### The only real mitigation

If "Scholar yes, Docs/Forms no" genuinely matters, the sole tool that can do it
is **layer-7 SNI filtering** — an egress proxy that allows/denies on the
hostname in the TLS ClientHello, since both go to the same IP. `iptables` is
IP-only and structurally can't. Caveat: **Encrypted Client Hello (ECH)** is
starting to hide SNI for Google, which would eventually defeat even an SNI proxy
and force a full MITM proxy with a trusted cert. That's a separate, heavier
project — out of scope for the lit-review tool.

## Access model (who can change what) — verified this session

Two copies of the script, and this is the crux of "can we self-heal at runtime":
- `/workspace/.devcontainer/init-firewall.sh` — **editable source**,
  bind-mounted, node-writable, but **inert** (nothing runs it directly).
- `/usr/local/bin/init-firewall.sh` — the **root-owned build-time COPY** that
  actually runs. `Dockerfile`: `COPY init-firewall.sh /usr/local/bin/`, plus a
  sudoers drop-in `node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh`.

So `node` (us, and the interactive shell):
- has passwordless sudo for **exactly that one path** — general `sudo` (e.g.
  `sudo ipset ...`, `sudo bash`) is blocked (needs a password nobody has);
- **cannot write** the installed copy (root-owned) → can *enforce* the firewall
  but not *rewrite* it. This is deliberate: whitelisting a node-writable path
  for NOPASSWD-root would be a trivial root escape.

Implications:
- Editing the **source** does nothing until a **rebuild** re-`COPY`s it (or
  host-side root overwrites the installed copy). `postStartCommand` re-runs the
  installed copy on every start, but that's the frozen version.
- So getting the `173.194` edit / `goog.json` into effect = **rebuild** (or host
  root). Not doable from inside as node.

## Rejected: auto-rerun the firewall from `cited_by.py`

Idea was: on `Unreachable`, have the tool shell out to
`sudo /usr/local/bin/init-firewall.sh` and retry. Technically runnable (NOPASSWD).
Rejected because:
1. **Doesn't fix rotation** — re-running only re-`dig`s today's single IP
   snapshot (racy against anycast); re-introduces the exact per-IP fragility the
   CIDRs replaced.
2. **Heavyweight + fail-closed risk** — the script `iptables -F`s, destroys the
   ipset, and rebuilds from scratch incl. re-fetching GitHub meta over the
   network. A hiccup mid-run trips the DROP trap → whole firewall down to fix one
   lookup.
3. **Can't add new CIDRs** — the installed copy is frozen; it can't introduce
   `173.194` or `goog.json`. Only the racy dig-pin.
4. **Scope** — a lit-review scraper triggering privileged firewall reconfig is
   exactly the scope creep to avoid ([prefers-lighter-tools]).

Cleaner if we ever want auto-heal: a *tiny separate* whitelisted script that only
does `ipset add allowed-domains <cidr>` (additive, no flush, no refetch). More
privilege surface for marginal gain — not reaching for it now.

## Where this leaves the decision (open)

- Reachability is currently OK (Scholar rotated back into an already-covered
  block); the `173.194` source edit + any `goog.json` change still need a rebuild
  to take effect.
- The exfil concern is **not** resolved by narrow-vs-`goog.json` — both expose
  the same programmable Google services. Real options:
  1. **Accept it** (research box; comparable channels already open; blocks the
     realistic opportunistic threat) → then `goog.json` is strictly better
     (self-healing) than hand-patched CIDRs.
  2. **Actually wall off the exfil sinks** → needs an SNI egress proxy, separate
     project, with the ECH caveat looming.
- Leaning toward documenting the tradeoff and deferring; not importing `goog.json`
  reflexively while the exfil question is unsettled — but noting that staying
  narrow buys *no* exfil safety, only more maintenance.

## Tool state (from 0724a, for continuity)

- `.tools/dev/cited_by.py` — new Scholar-based tool, built + validated; now has
  typed `Unreachable` handling that says "suspect the firewall, not Scholar."
- `.tools/dev/openalex_cited_by.py` — the old OpenAlex tool, renamed (`git mv`).
- `.devcontainer/init-firewall.sh` (source) — `173.194.0.0/16` added; **not yet
  live** (needs rebuild).

[0724a]: 0724a,scholar-lit-review.md
[prefers-lighter-tools]: keep .tools/ utilities small
