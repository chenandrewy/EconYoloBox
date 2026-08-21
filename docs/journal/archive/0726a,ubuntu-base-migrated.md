# Ubuntu base migration: done, and cheaper than budgeted

Date: 2026-07-26 (NY)

Status: **implemented and verified.** [0725g] planned this and deferred the
timing; this entry records the execution and what the plan got wrong.

## Outcome

`node:20` (Debian bookworm) → `ubuntu:24.04` (noble). The whole surface was
re-verified on the new base and everything passes.

The number that justified the migration:

```
cold fill, both stacks, fresh container:   1m13s
  R packages installed as binaries:        189
  R packages built from source:              2   (pryr, OpenSourceAP.DownloadR)
  arrow:                                   binary, libarrow included, snappy OK
```

Those two source builds are the two that are *designed* to be source — the
CRAN-archive pin and the GitHub pin, both pure R, neither touching a
third-party host. That is exactly the residual [0725g] predicted. Nothing else
compiled. The hour of arm64 compiles is simply gone.

Also measured, on arm64: **3.42GB image, ~9 minutes cold build.**

## What the plan got right

The four structural predictions all held.

- **arrow is structurally fixed.** P3M serves it prebuilt for noble-arm64
  (`rspm-sync.rstudio.com/bin/4.5-noble-arm64/...`, ~20MB with `arrow.so`
  inside), over the ordinary package path. A parquet file written by R reads
  back in pyarrow.
- **The five (six) arrow allowlist hosts became dead weight** and are removed:
  `www`/`dlcdn`/`archive`/`nightlies.apache.org`, `zlib.net`, `sourceware.org`.
- **`ubuntu` at uid 1000 is the fiddly one.** Deleted; `node` recreated at 1000.
  Worth recording that `userdel -r ubuntu` warns about the missing mail spool
  and still exits 0, so it needs no `|| true` guard.
- **Volumes are ABI-tied to the distro.** Both names carry a `noble` token now,
  which starts them fresh automatically.

Everything base-independent carried over untouched, as predicted: dnsmasq
resolve-time allowlisting, the persistent-volume architecture, the snapshot pin.
The firewall test passes in full, including the volatile-host path.

## What the plan got wrong

**It over-budgeted the cost.** "A few hours of mechanical rework… a careful
half-day" was the estimate. The actual mechanical delta is small, and the
expensive-sounding item — compiling LyX — costs about **one minute** of build
time on 24 cores (configure done at 24s, compiled and installed by 58s).

**It under-budgeted one specific risk: what the base image was silently
providing.** The plan anticipated "a couple of small renames," and the rename
sweep was indeed trivial (`libfreetype6-dev` → `libfreetype-dev`, the only
one). The real hazard was different in kind — packages `node:20` shipped that
`ubuntu:24.04` does not, which are not renames and do not show up by reading
the Dockerfile:

- `libssl-dev` — Git fails to compile. Loud, caught immediately.
- `libcurl4-openssl-dev` — **this is the dangerous one.** Git compiles fine
  without it and simply omits `git-remote-http`. The build goes green and the
  failure surfaces later as `git clone https://...` → "Unable to find remote
  helper for 'https'". A build-time success that is a runtime regression.

Both now sit above the Git build with a comment saying why. The verification
sweep grew a check for `git-remote-http` in `git --exec-path`, because "it
built" does not mean "it works" for anything compiled from source.

The generalizable lesson: when swapping a base image, the risk is not the
packages you name, it is the ones the old base named for you.

## The review pass, and why it matters more than it looks

A separate review of the migrated image found three more instances of *exactly
the same failure mode*, which is the real reason to record them:

- **`openssh-client`.** `node:20` shipped `ssh`/`scp`/`sftp`; a bare Ubuntu has
  none. Every `git@github.com:` remote would have failed. Sharper still:
  `init-firewall.sh` deliberately `ACCEPT`s outbound tcp/22, so the image was
  quietly contradicting the firewall's stated intent.
- **`rsync`.** Not from the base — the *old Dockerfile* installed it, in the
  same layer that installed LyX from backports. Rewriting that layer wholesale
  took the unrelated package with it. Replacing a layer silently drops whatever
  else was riding in it.
- **Yarn.** `node:20` bundled it; NodeSource's `nodejs` does not. Deliberately
  **not** restored: there is no `yarn.lock`, no `package-lock.json`, and no
  `yarn` reference anywhere in the repo, so putting it back would be restoring
  an accident of the base image. `corepack` is present if it is ever wanted.

So the tally for this migration is five packages lost, all of them invisible
by reading the Dockerfile, and only one (`libssl-dev`) loud enough to fail the
build. The verification sweep now asserts on all of them by name.

A methodological note worth keeping: the first attempt to check these findings
compared the new image against `vsc-1-sandbox-ubuntu-<hash>`, which had already
been rebuilt — so it was the new image compared against itself, and it made all
three findings look wrong. The valid comparison is against upstream `node:20`
and the still-bookworm image from the sibling workspace. When a base image is
the variable, a tag is not a stable reference point.

## Node: bumped, and not for migration reasons

The migrated image initially pinned Node 20 to stay faithful to what `node:20`
provided. But Node 20 reached end of life on **2026-04-30**, so the old image
was already running an unsupported runtime — the migration did not cause that,
it just moved the pin somewhere we control, which is what made it fixable.

Now on **24.18.0** (LTS through 2028-04-30), verified with npm 11.16.0 and both
AI CLIs running under it. `NODE_MAJOR` selects the apt repo and `NODE_VERSION`
pins the build; they must move together.

## LyX: pin re-derived

[0725g] asked for "an Ubuntu-archive equivalent and a fresh rationale" for the
LyX pin. There is no equivalent. Noble ships **`2.4.0~RC3`** — a release
candidate — and Ubuntu has no backports pocket offering a stable 2.4, so the
Debian-12-backports pin (`2.4.3-1~bpo12+1`) has no counterpart to move to.

Built **2.4.5** from upstream source instead, against Qt5 to match what the
Debian build linked. Two notes:

- `ftp.lyx.org` is a CNAME to `ftp.lip6.fr`, whose certificate covers only the
  latter — fetching by the `lyx.org` name fails TLS verification. Fetch by the
  mirror's own name and let a **sha256 pin**, not the hostname, be the
  integrity anchor.
- Converter detection runs once at build time, system-wide, after TeX Live and
  pandoc are both present. Otherwise LyX does it per-user on first export,
  into a `~/.lyx` that a recreated home volume discards.

This is a net improvement over what it replaces: the version is now an explicit
knob rather than a property of whichever suite we happen to track.

## One layer-ordering trap worth remembering

`chown -R node:node /usr/local/share` exists so npm's global prefix is
writable. Compiling LyX puts ~40MB of data files under that same path, so with
the chown *after* the LyX build, a recursive ownership change rewrites every
one of those inodes into a fresh layer for no benefit. Moved above it.

Related, and the reason LyX sits before the R block: `CRAN_SNAPSHOT` is bumped
far more often than `LYX_VERSION`, and every layer below the snapshot rebuilds
when it changes. LyX below it would make each snapshot bump pay for a LyX
recompile.

## Verified

`test-firewall.sh` (all four probes, including both volatile hosts) · full
`install-packages.sh` with binary/source accounting · `arrow` load +
`codec_is_available("snappy")` · parquet round-trip R → pyarrow ·
`sync-lyx.sh` tex → lyx → pdf on a document with real math · `git-remote-http`
present · `ssh`/`scp`/`sftp`/`ssh-keygen`/`rsync` present · claude / codex / gh
/ rg / Rscript · node 24.18.0 + npm 11.16.0 · python 3.12 · LyX 2.4.5 ·
uid 1000 is `node`, no `ubuntu` user.

**Not verified: a live WRDS query.** The drivers load (`DBI` + `RPostgres`,
`wrds` + `psycopg2`) and `wrds-pgdata.wharton.upenn.edu:9737` is reachable
through the armed firewall, but the test container has no credentials, so
authentication and an actual query remain unexercised. That is the one item
from [0725g]'s checklist still open.

## Follow-ups

- Run a real WRDS query from a credentialed container to close the last check.
- Delete the bookworm volumes once this has been lived in for a few days.
  Deliberately not done yet — the `noble` token means the old volumes are
  inert, not in the way, so there is no cost to keeping the rollback.
- Watch for [0725g]'s predicted "tail of small latent surprises." All five
  found so far (`libssl-dev`, `libcurl4-openssl-dev`, `openssh-client`,
  `rsync`, yarn) are one type: things the previous image supplied without the
  Dockerfile asking. Expect the remaining tail to be more of the same, and
  reach for `docker run --rm node:20` as the oracle when something is missing.
- npm is now the only supported Node package manager. Yarn is gone with the
  base image and was not restored; `corepack enable yarn` if that changes.

[0725f]: 0725f,persistent-package-volumes.md
[0725g]: 0725g,ubuntu-base-migration.md
