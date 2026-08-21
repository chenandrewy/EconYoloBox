# 0720c — Python extensions never installed; stale-IP allowlist is the cause

2026-07-20 (NY)

Symptom: Python files show "No symbols found" in the outline pane, even after
adding `ms-python.python` and `ms-python.vscode-pylance` to `devcontainer.json`
and `ms-python.gallerycdn.vsassets.io` to `init-firewall.sh`, and rebuilding.

This is the limit recorded in [0719a](0719a,firewall-holes.md) ("Known limits,
accepted for now": IP-based allowlist against shared CDNs, one-shot `dig` goes
stale) coming due. It is no longer theoretical.

## What actually happened

The extensions were never installed. Container `~/.vscode-server/extensions/`
holds 9 extensions; neither `ms-python` entry is among them. Python document
symbols come from Pylance, so with Pylance absent the outline is empty —
the symptom is a missing extension, not a misconfigured one.

From `~/.vscode-server/data/logs/20260720T181001/remoteagent.log`:

```
[error] Failed Installing Extensions: ms-python.vscode-pylance, reditorsupport.r,
  tomoki1207.pdf, donjayamanne.githistory, ms-python.python, mhutchie.git-graph,
  ikuyadeu.r-pack, github.copilot, anthropic.claude-code, esbenp.prettier-vscode,
  dbaeumer.vscode-eslint, james-yu.latex-workshop
```

*Every* extension download from inside the container timed out — including
publishers allowlisted for months. VS Code then fell back to
`Relaying the following extensions to install later` (host downloads them and
pushes them in, `downloadExtensionsLocally: true`), which rescued 10 of the 13.
That relay round never reached the two `ms-python` entries; the log ends at 178
lines with no `Installing extension: ms-python.*` line. They are the only
casualties, which is why *only* Python tooling looks broken while everything
else works.

So the host-relay fallback has been silently masking a fully broken
container-side download path — possibly for a long time.

## Root cause

`init-firewall.sh:130` resolves each domain **once at boot** with
`dig +short A` and pins that snapshot into a static ipset. Nothing refreshes it.

Live from inside the container:

```
ms-python.gallerycdn.vsassets.io  -> 23.219.161.135   (BLOCKED/TIMEOUT)
esbenp.gallerycdn.vsassets.io     -> 23.219.161.135   (BLOCKED/TIMEOUT)  same IP
marketplace.visualstudio.com      -> 200 OK
```

Two findings:

1. **The per-publisher entries are no-ops.** All `*.gallerycdn.vsassets.io`
   publishers are CNAMEs onto one shared Akamai edge
   (`gallerycdn.vsassets.io.edgesuite.net` → `a125.dscr.akamai.net`). Adding
   `ms-python.gallerycdn.vsassets.io` at `init-firewall.sh:93` added no new IP.
   The comment at `init-firewall.sh:76-79` — "Adding an extension from a new
   publisher requires a new entry here, or its install will silently fail" —
   encodes a model that is simply wrong. **Correct this comment.**
2. **Akamai rotates that edge IP.** The boot snapshot goes stale, and every
   gallerycdn host is blocked thereafter. `esbenp` is unreachable right now
   despite being allowlisted since forever.

There is a second, subtler defect: `dig +short` returns whatever slice of the
edge pool that one query happened to get — for gallerycdn, a *single* IP out of
Akamai's pool. Even at boot this allowlists one door of a building with
thousands.

This is not a vsassets problem. Every CDN-backed name in the list at
`init-firewall.sh:80-128` carries the same latent failure:
`files.pythonhosted.org` (Fastly), `registry.npmjs.org` (Cloudflare),
`openrouter.ai`, `api.openai.com`.

## Options

### A. DNS-driven auto-updating ipset (dnsmasq) — recommended

Run dnsmasq as the container's resolver and let it populate the ipset as a side
effect of resolution:

```
ipset=/gallerycdn.vsassets.io/vsassets.io/allowed-domains
```

Any successful A lookup under those suffixes auto-adds the answer to
`allowed-domains`. The allowlist becomes **by name, wildcard-capable, and
self-healing** — rotation stops mattering, and all 11 per-publisher lines
collapse into one suffix. A new publisher needs no edit at all.

- Cost: dnsmasq in the image; point `/etc/resolv.conf` at it while forwarding
  to Docker's embedded DNS at `127.0.0.11` (whose NAT rules the script already
  preserves at `init-firewall.sh:27-34`).
- Security: an IP enters the set only because something resolved an allowlisted
  name. Weaker than L7 — a name we trust could resolve anywhere — but these
  names are already trusted.
- Kills the whole bug class, not just this instance.

### B. Egress proxy with hostname allowlist (squid/tinyproxy)

Filter at L7: drop all egress except to the proxy; proxy enforces a domain
allowlist with real wildcards. Most correct — IP identity stops being the
security boundary, which is the actual conceptual error in the current design.
Also yields **logs of denied requests**, which would have made this a
30-second diagnosis instead of log archaeology.

- Cost: highest. `HTTP_PROXY`/`HTTPS_PROXY` everywhere; VS Code server, npm,
  pip, curl honor it, but anything proxy-unaware breaks with confusing errors.
- This is the "filtering proxy — bigger project" already named in 0719a.

### C. Minimal patch: re-resolve on a timer + collapse to the apex

Keep the architecture. Resolve `gallerycdn.vsassets.io` once instead of 11
publisher aliases, and re-run the resolve loop every few minutes so the set
converges as IPs rotate.

- Cheapest, no new dependencies. Still racy: extension install fires at
  container start, before the timer converges — exactly the window that failed
  here. Mitigates, does not fix.

### D. Allowlist Akamai's published ranges — rejected

Akamai publishes no usable consolidated list and the effective footprint is a
large fraction of the CDN-hosted internet. Trades a broken firewall for a
decorative one.

## Do regardless of which option

The failure was **silent** — the whole point of the misleading comment was to
prevent exactly this, and it didn't, because nothing verifies the outcome. Add
a post-start check that diffs `~/.vscode-server/extensions/` against the
`extensions` array in `devcontainer.json` and warns loudly on any missing
entry. ~10 lines, pays for itself independent of A–D, and would have caught
this at the rebuild instead of via the outline pane days later.

## Decision

Sketch only; nothing implemented yet. Leaning **A plus the verification
check** — B is more rigorous, but a bigger blast radius than a single-user
sandbox warrants, and A eliminates the same bug class.

Sideloading the two VSIXs was considered and rejected: it fixes the symptom
while moving the fragility somewhere less visible.
