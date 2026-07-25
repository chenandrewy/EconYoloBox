# Firewall plan, settled: follow the reference repo and widen

Date: 2026-07-25 (NY)

Wraps up the thread [0724b] → [0724c] → [0724d] → [0724e]. Minor update: the
posture is now "follow `anthropics/claude-code`," which retires most of what the
earlier entries were designing.

## Where the thread landed

- [0724b] — IP allowlisting **cannot** separate Scholar from Docs/Drive (shared
  Google front-end fleet, routed by SNI). Google CIDRs reverted.
- [0724c] — `scholar-fetch`, a privileged open-fetch-close helper. **Retired,
  never built.**
- [0724d] — Settled: the data here is low-value (referee reports at worst), so
  just allow Google. Import `goog.json`; **never `cloud.json`** (GCP customer
  ranges = rent-a-C2).
- [0724e] — The git credential helper is the **VS Code default**, not a user or
  agent error. The reference forwards credentials on purpose so agents can push
  and open PRs. **Keep it.**

## What this session added

1. **Package installs aren't firewall-blocked in principle.** PyPI, P3M, and npm
   are already allowlisted, and both install paths are node-writable *by design*
   (Dockerfile: `chown -R node:node /opt/venv`, `chmod -R a+w` on the R library,
   commented "Allow non-root user to install R packages at runtime"). The blocker
   was the `CLAUDE.md` policy rule, which contradicts the image's own design.
2. **But R installs do break in practice.** P3M redirects the payload to
   **`rspm-sync.rstudio.com`**, which is not allowlisted — this is what killed a
   `tictoc` reinstall. Posit's docs name it as first-party infrastructure ("the
   Posit Package Service"), so it is bounded and safe to allow — the `goog.json`
   side of the boundary, not `cloud.json`.
3. **Build ≠ runtime.** `docker build` runs with the network **open**; the
   firewall only exists at runtime (`postStartCommand`). So "it's in the
   Dockerfile" is no evidence a command works in flight. This is why 30+ R
   packages installed at build time and a single one fails now.
4. **Build-time `dig`-pinning fails three ways:** IP rotation; **redirect chains
   to hosts that were never listed** (newly confirmed); partial A-record
   resolution. Mode 2 is undiscoverable by inspection, so the allowlist is
   permanently reactive.
5. Incidental: Posit docs are readable inside the firewall via the mirror at
   `packagemanager.posit.co/__docs__/` (`docs.posit.co` is blocked).

## The plan

**1. Posture — follow the reference repo.** Stop treating the sandbox as a
hardened boundary. Allow GitHub, Sentry, and whatever else we actually use; keep
the VS Code credential helper. Control damage by what we *put in* the container,
not by walling off the network — chiefly **don't mount seriously private info**.
The bar is severity: routine research material and referee reports are fine;
anything whose leak would be a real problem stays out.

**2. Widen the firewall** — one pass in `.devcontainer/init-firewall.sh`, live on
the next rebuild:
- the `goog.json` block (self-healing through anycast rotation; **not**
  `cloud.json`)
- `rspm-sync.rstudio.com` — P3M's payload host
- `cran.r-project.org` — needed once installs move to runtime (the `pryr`
  archive install)

**3. Move R/Python package installs out of the Dockerfile into an optional
script.** Gives future users a stack they can extend, without a rebuild.
- **System deps stay in the Dockerfile** (`gfortran`, `libcurl4-openssl-dev`,
  `libxml2-dev`, `libpq-dev`, `libsecret-1-dev`, freetype/harfbuzz/fribidi,
  `cmake`) — they need root regardless.
- **Keep the verification check** (current Dockerfile lines 177-190) inside the
  script so a partial install fails loudly.
- Installs go to the existing **shared** library — deliberately no user-level
  layering, to keep things simple. That's defensible precisely *because* of this
  change: the shared-library risk was "break it and you need a rebuild," and once
  the stack is a re-runnable script, recovery is just re-running it. The layering
  was only compensating for the stack being baked into the image.
- **Trade-off:** version reproducibility is preserved (the dated P3M snapshot
  pins them); *state* becomes opt-in and costs minutes per container instead of
  being a cached image layer.

## To do / open

- **Re-evaluate how GitHub tokens are used** here (the helper forwards the host's
  full credential; fine-grained PATs via `.credentials/` are the alternative).
  Deferred, but worth revisiting.
- **Loosen `CLAUDE.md`**: the GitHub "no credentials / prepare commits locally
  and hand off" language, and the package rule → additive installs fine, ask for
  new system `-dev` libraries.
- **Expect more redirect hosts** to surface on the install script's first full
  run; they can't be enumerated in advance.
- **`rspm-sync` IP stability** unmeasured — one `dig` says whether a build-time
  pin holds or we want an additive `ipset add` escape hatch.

[0724b]: 0724b,firewall-exfil-risk.md
[0724c]: 0724c,scholar-fetch-design.md
[0724d]: 0724d,google-firewall-open.md
[0724e]: 0724e,credential-helper-close.md
