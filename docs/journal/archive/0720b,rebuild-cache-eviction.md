# 0720b — Container rebuilds are slow because BuildKit GC evicts the R layers

2026-07-20 (NY)

Context: added `ms-python.python` / `ms-python.vscode-pylance` and two Python
settings to `devcontainer.json` — a 6-line diff touching only
`customizations.vscode`. The container then rebuilt for ~20 minutes. Question
was why an extensions-only edit costs that much.

Two independent things, and only the second is the actual problem.

## 1. Why a rebuild triggers at all (expected)

VS Code fingerprints the *whole* `devcontainer.json`, not just the build-relevant
keys. `customizations.vscode.extensions` and `.settings` are applied at
container-create time — there is no hot-apply path — so changing either
genuinely requires a recreate. Nothing to fix here; a recreate should be cheap.

## 2. Why the rebuild is slow: cache cap < working set

`~/.docker/daemon.json`:

```json
"gc": { "defaultKeepStorage": "20GB", "enabled": true }
```

Against:

- image `vsc-1-sandbox-…` — **24.2GB**
- `docker buildx du` total — **25.05GB**

The GC ceiling is below what the build needs to stay cached, so BuildKit evicts
layers between builds and the expensive ones re-execute.

`docker history` pins the break exactly. The Dockerfile has not been edited
since **Jul 19 14:28**, yet:

| Layer | Age |
|---|---|
| `ARG R_VERSION` / `ARG CRAN_SNAPSHOT` (`Dockerfile:58-59`) and below | 5 days |
| R toolchain apt install (`Dockerfile:63`) — **8.07GB** | 4 hours |
| R package installs (`Dockerfile:152-177`) — 1.3GB, 1.28GB, 794MB, 671MB… | 4 hours |
| `COPY init-firewall.sh` (`Dockerfile:289`) and up | 3 hours |

Cache holds through the base image, git, LyX and pandoc, then breaks at
`Dockerfile:63` — the first heavy layer, and the point where cumulative size
crosses the 20GB cap. Everything above it re-ran despite no source change, and
will re-run again on the next rebuild. This is eviction, not invalidation.

## Fix

Keep the existing key, raise the number:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "35GB"
    }
  }
}
```

**Sizing.** `defaultKeepStorage` is the cache budget — GC prunes what exceeds
it. Working set is 25.05GB, so 35GB is that plus modest headroom; 30GB would
leave only ~5GB of slack. No need to go higher — an earlier 60GB figure in this
entry was an arbitrary guess, not derived. Host has 115Gi free, so 35GB is
comfortable.

**Two ways to change it**, both editing the same `daemon.json`:

1. Docker Desktop GUI — Settings → Docker Engine, then *Apply & Restart*.
   Not Settings → Resources → Advanced → "Disk usage limit": that sizes the
   whole VM disk and does not affect the cache budget.
2. Directly — `~/.docker/daemon.json`, then restart Docker Desktop.

**Key name — corrected.** An earlier draft of this entry claimed
`defaultKeepStorage` was deprecated in favor of `reservedSpace`/`maxUsedSpace`.
That was wrong. Per Docker's docs, `daemon.json` uses `defaultKeepStorage`;
`reservedSpace`, `maxUsedSpace` and `minFreeSpace` are **`buildkitd.toml`** keys
for custom builders, not daemon.json. Our existing key was right all along.

The error came from misreading `docker buildx inspect --bootstrap`:

```
GC Policy rule#1:  Keep Duration: 1440h   Reserved Space: 20GiB
GC Policy rule#3:  All: true              Reserved Space: 20GiB
```

"Reserved Space" here is BuildKit's *internal* vocabulary for the policy Docker
derives from `defaultKeepStorage` — a display label downstream of the config,
not the name of the knob. Lesson: a human-readable label in tool output is not
evidence for a config key spelling; check the vendor's reference.

The output does still prove the eviction rather than leaving it inferred:
20GiB budget against a 25.05GB working set, and the R layers are the overflow.

Expect the *next* rebuild to still be slow — the R layers are already evicted
and must repopulate once. The payoff shows up on the rebuild after that.

Not yet applied — pending confirmation.

Refs: <https://docs.docker.com/build/cache/garbage-collection/>,
<https://github.com/moby/moby/issues/46864> (daemon.json gc config quirks).

## Noted, not worth acting on

- `COPY init-firewall.sh` at `Dockerfile:289` means firewall edits bust the last
  two layers. They are 25kB and 37kB — irrelevant next to the R layers, and the
  COPY is already placed as late as it can go.
- `CLAUDE_CODE_VERSION=latest` / `CODEX_CLI_VERSION=latest` (`Dockerfile:7-8`)
  are literal ARG strings, so they do *not* bust cache on their own — the npm
  layer only re-runs when something below it does. Worth remembering: that means
  a rebuild does not reliably pick up new agent CLI versions.
- Docker has 3 images / 22.62GB reclaimable, including an 8.11GB
  `vsc-ralph-wiggum-asset-pricing` from 13 days ago and two stopped containers
  (2.8GB). Pruning those frees disk but does **not** help here — the constraint
  is the BuildKit cache cap, not host disk (118Gi free).

## Sanity check for next time

If a rebuild feels too slow, `docker history <image>` and look for an age
discontinuity in the middle of the file. Layers older than the edit = cache
working. A "4 hours ago" band under an untouched Dockerfile = eviction, and the
answer is the GC cap, not the Dockerfile.

## Spun off: the READMEs need a reorg

Went looking for where to document the GC cap and found the docs are misfiled.

`README.md:17-44` ("Devcontainer Image Size Notes") is stale in four ways:
image tagged `vsc-sandbox-<hash>` (actually `vsc-1-sandbox-<hash>`); size
~21.6GB (now 24.2GB image / 25.05GB `buildx du`); `chmod -R a+w
/usr/local/lib/R/site-library` (now `/opt/R/${R_VERSION}/lib/R/library`,
`Dockerfile:193`, drifted in `fb9b883`); and it says "`docker history`
underreported some large steps" — but `docker history` is exactly what
localized this break to `Dockerfile:63`. The remaining per-layer figures
(13.09GB texlive, 852MB npm) are unverified and suspect by association.

Structurally the split is close to inverted: 28 of root's 47 lines are BuildKit
layer forensics (deep implementation), while `.devcontainer/README.md` opens by
documenting `.credentials/` — a different top-level folder.

Proposed principle: **general documentation at root, implementation details in
folder READMEs.** Under it, the fix here splits cleanly — the GC cap is a *host
prerequisite* (root, alongside `TZ` and the once-per-machine
`.credentials/setup.py`, all things the repo cannot enforce), while the
mechanism and the `docker history` diagnostic are devcontainer implementation
(folder, next to the existing "Dockerfile ordering" section, whose advice is
load-bearing only while the cap holds).

Not done — scoping it was the open question when this got deferred.
