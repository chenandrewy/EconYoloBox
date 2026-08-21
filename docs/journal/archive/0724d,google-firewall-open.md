# Settled: just allow Google in the firewall (accept the exfil surface)

Date: 2026-07-24 (NY)

Closes the Scholar thread [0724a] → [0724b] → [0724c]. After all the proxy /
`scholar-fetch` design work, the decision is the simple one: **add Google to the
firewall allowlist and accept the exfil surface.** The elaborate machinery was
solving a problem this box doesn't have.

## The decision that settles it: match control cost to data value

The whole anti-exfil apparatus assumed the container holds something worth
stealing. It doesn't, much. Users here are doing **academic research**; the most
sensitive artifacts are **referee reports**, whose leak is a minor professional
annoyance, not a real harm. Once you price the asset honestly, the cost of the
protection ([0724c]'s root-owned, owner-scoped, watchdog'd, rebuild-to-patch
`scholar-fetch`) dwarfs the value it defends. So: don't build it.

This also matches how the box already behaves. It already carries comparable
general egress channels — **Sentry**, the **LLM APIs**, **all of GitHub's
ranges** — so it was never sealed against a determined exfiltrator anyway
([0724b]). Adding Google changes the surface by a little, not a lot, and the
realistic threat the firewall actually buys down — *opportunistic* phone-home
from a bad dependency — stays blocked (random C2 ≠ Google).

## Precedent check (and its one caveat)

Pulled the reference `anthropics/claude-code` `.devcontainer/init-firewall.sh`:
it allowlists **`sentry.io`, `statsig.*`, and GitHub's published ranges**
(`.web + .api + .git` via `api.github.com/meta`), plus npm + VS Code hosts. So
Sentry + GitHub are blessed by upstream. **Google is NOT in the upstream list** —
it's our own addition, justified by the research use-case, not by precedent.
Fine, just don't claim upstream cover for the Google part.

## How to open Google: `goog.json`, not hand-patched CIDRs

Use the clean answer [0724b] already identified: import Google's published
first-party range list, mirroring how the script handles GitHub meta today.

- **`https://www.gstatic.com/ipranges/goog.json`** — ~99 IPv4 CIDRs, self-updating.
  Covers Scholar and **self-heals every anycast rotation** → no more whack-a-mole
  (recall [0724b]: two rotations needed hand-patching in one afternoon).
- **`goog.json` only — never `cloud.json`.** The latter is GCP *customer* ranges
  (arbitrary rented VMs = a rent-a-C2 endpoint surface). That boundary is the
  whole reason `goog.json` stays sane.
- Wire it exactly like the existing GitHub block: fetch during the build's open
  window, validate each CIDR against the regex, `ipset add`. Same fail-closed
  trap applies.

## What this retires

`scholar-fetch` ([0724c]) is **dead** — no root helper, no `scholarbot` uid, no
sudoers drop-in, no fused open/fetch/close, no self-closing watchdog, no
rebuild-to-patch fragility, no frozen-fetcher SSRF residual to audit. All of it
was in service of "allow Scholar but not Docs/Drive," a distinction we've now
decided we don't need to make. The ECH-dodging insight was neat but moot.

## The residual we're knowingly accepting

Allowing Google opens the **programmable first-party sinks** — `docs.google.com`
/ Forms, `drive.google.com`, `storage.googleapis.com`, Apps Script — which are
textbook exfil relays ([0724b]). We accept this because: (a) the data isn't worth
exfiltrating, (b) comparable channels are already open, (c) it can't be separated
at the IP layer anyway (shared Google fleet, routed by SNI). If the data
sensitivity ever changes, revisit — the only real separator is an SNI/MITM proxy,
with the ECH clock ticking.

## Status / next

- **Decision made; not yet implemented.** Source `init-firewall.sh` still lacks a
  Google block (the narrow CIDRs were reverted in [0724b]).
- To land: add a `goog.json` fetch/validate/add block to the source script (with
  the `cloud.json` exclusion noted inline), then **rebuild** (installed copy is
  root-owned; source edits are inert until re-`COPY`'d — same gate as always).
- Keep Sentry + GitHub as-is (both upstream-blessed). Credential-helper concern
  spun out to [0724e] — that one is a *distinct* problem and we're closing it.

[0724a]: 0724a,scholar-lit-review.md
[0724b]: 0724b,firewall-exfil-risk.md
[0724c]: 0724c,scholar-fetch-design.md
[0724e]: 0724e,credential-helper-close.md
