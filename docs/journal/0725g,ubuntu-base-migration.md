# Migrating to an Ubuntu base image: the structural fix for the arm64 tax

Date: 2026-07-25 (NY)

Status: **direction decided, timing deferred.** This is where we ultimately
go; it does not happen until the current arrow fix ([0725e] postscript 2)
lands and the stack is verifiably whole. Migration is its own project with
its own verification tail, not something to fold into today's chain of fixes.

## Why

The day's root cause, one level below everything we fixed: **P3M publishes no
arm64 binaries for Debian.** This container is `node:20` (Debian bookworm) on
Apple Silicon, so every R package compiles from source. Everything downstream
followed from that one fact — the hour-long first fills, the arrow C++ bundled
build, and the five allowlist hosts reverse-engineered from arrow's
`versions.txt` (www/dlcdn/archive.apache.org, zlib.net, sourceware.org).

P3M *does* publish arm64 binaries for **Ubuntu** (22.04/24.04). On an Ubuntu
base this machine class gets prebuilt binaries for the entire stack — arrow
arriving with libarrow baked in, one download from `rspm-sync` through the
dnsmasq path like any other package.

Who this is for: the adoption audience is mostly **Apple Silicon MacBooks**,
so the arm tax is the *default* first-touch experience, not an edge case.
(An earlier claim in discussion that "the adoption story is mostly an x86
story" was wrong.)

## What it buys

- **arrow structurally fixed.** No source build, no third-party fetches. The
  five arrow allowlist hosts become dead weight and should be **removed** at
  migration (tighter list, same capability).
- **Host-chasing ends.** The chase exists only for source builds. Residual
  source builds remain possible (archive pins like `pryr` — pure R, no hosts;
  a snapshot date briefly predating a fresh binary) and keep dnsmasq plus the
  `versions.txt` enumeration trick as the documented exception path.
- **First fill drops from ~an hour of compiles to minutes of downloads**, for
  the whole ~100-package closure. Biggest compile wins besides arrow:
  `stringi` (bundled ICU), the `lme4`/`car` chain (`nloptr`, `quantreg`,
  `pbkrtest`), `fixest`, `ccaPP` (RcppArmadillo), `fst`. Adding a package to
  the list becomes a seconds-long operation on ARM too, which keeps the
  runtime-install design pleasant for exactly the users [0725f] cares about.

No other package is *broken* like arrow — everything else builds
self-contained (`stringi` fetches ICU data from GitHub mirrors, already
allowlisted). Arrow is the correctness argument; the rest is speed.

## What it costs

Mechanical rework (a few hours):

- **Node becomes ours to manage.** Base switches from `node:20` to
  `ubuntu:24.04` (or the devcontainers Ubuntu image); install Node via a
  pinned NodeSource apt repo. We take over the version pinning the base image
  used to provide.
- **R `.deb` URL** → `cdn.posit.co/r/ubuntu-2404/...`; **P3M repo URL** in
  `Rprofile.site` → `.../__linux__/noble/<snapshot>`.
- **LyX pin re-derived.** Current pin is justified against Debian 12
  backports; needs an Ubuntu-archive equivalent and a fresh rationale.
- **Python 3.11 → 3.12** (noble's default) → bump the venv volume name;
  package compatibility is a non-issue for our stack.
- Most apt package names are identical; expect a couple of small renames.

The fiddly one:

- **`ubuntu:24.04` ships a default `ubuntu` user at uid 1000**, colliding
  with our `node` user. Delete the default user and keep the `node` name —
  `/home/node/...` is hardcoded in devcontainer.json, the ai-sesh tooling,
  and agent config paths. Forgetting this produces confusing permission
  errors.

The subtle one:

- **Volumes are ABI-tied to the distro.** Packages built against bookworm's
  shared libraries must not be mounted into a noble container. The volume
  naming convention grows a distro token (e.g.
  `...-r-site-library-noble-4.5.3`), which automatically starts fresh volumes
  at migration. The refill is cheap *because* of the migration: binaries.

The real cost:

- One full uncached rebuild (the 20+ minute build, once), then re-verifying
  the whole surface on the new base: firewall + dnsmasq behavior, R stack
  installing as binaries (check the P3M binary user agent still triggers),
  LaTeX/LyX builds, WRDS, the CLIs. A careful half-day, plus a tail of small
  latent surprises over the following week (different library versions,
  slightly different tool behavior). This tail is why it's scheduled, not
  slipped in.

## What carries over unchanged

Everything designed today is base-image-independent: dnsmasq resolve-time
allowlisting, the persistent-volume architecture, the snapshot pin, the
fast-build/runtime-install philosophy ([0725f]). The migration swaps the
payload under the same machinery.

## Decision variable for timing

If the arm compile tax keeps generating incidents — new arrow versions
re-opening the host chase, collaborators on M-series hitting hour-long first
fills — migrate promptly. If today's fix holds and first fills stay rare and
volume-cached, this can wait for a quiet week.

Cheaper alternative kept on the table: **drop `arrow` from the stack** if
parquet I/O turns out not to earn its place — that deletes the correctness
argument for migrating and most of this entry's urgency, though not the
first-fill speed argument.

## Migration checklist (draft)

1. Branch; new Dockerfile base + Node install; delete default `ubuntu` user.
2. Repoint R `.deb` and P3M URLs; re-derive LyX pin; sweep apt names.
3. Add distro token to both volume names in devcontainer.json.
4. Remove the five arrow hosts from `init-firewall.sh`; leave dnsmasq and
   `VOLATILE_DOMAINS` untouched.
5. Uncached build; verify: `test-firewall.sh`, full `install-packages.sh`
   (confirm binaries, not compiles — watch for the absence of gcc output),
   LaTeX/LyX build, WRDS query, CLI smoke tests.
6. Journal the outcome; delete bookworm volumes once stable.

[0725e]: 0725e,rspm-cdn-rotation.md
[0725f]: 0725f,persistent-package-volumes.md
