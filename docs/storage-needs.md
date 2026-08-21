# Devcontainer storage needs

What the sandbox costs on disk: the image, the BuildKit build cache, and the
persistent volumes. The shared workspace devcontainer is built locally from
`.devcontainer/Dockerfile`, starting from the official `ubuntu:24.04` image.

Rough current total per checkout: a **3.42GB** image plus about **3.2GB** of
volumes, with the build cache on top of that.

## Image size

A measurement on 2026-07-26, after the Ubuntu base migration, found a **3.42GB
image built cold in about 9 minutes** on arm64. That is down from roughly 24GB
before. Two changes account for the drop, and only one of them is the base
swap:

- the analysis stacks moved out of the image to runtime installs, which
  removed the R and Python package layers entirely;
- the base migration itself, which mostly moved cost around rather than down —
  it added a Qt5 toolchain for the LyX source build (about a minute of compile)
  and TeX Live 2023 at 3.2GB is still the single largest component.

## BuildKit garbage-collection budget

Docker's `20GB` default is adequate at the current image size. Raising it is
headroom, not a fix for an active problem — the diagnostic at the end of this
file is the way to tell whether eviction is actually happening to you.

To raise the cache budget to `35GB`, open Docker Desktop's **Settings → Docker
Engine** and set the `builder.gc` section of `daemon.json` to:

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

Apply the change and restart Docker Desktop. The **Settings → Resources →
Advanced → Disk usage limit** control is different: it sizes the Docker VM disk
rather than the BuildKit cache budget.

The first rebuild after raising the budget may still be slow because previously
evicted layers must be rebuilt once. The benefit appears on subsequent
rebuilds.

## Persistent volumes

Six Docker volumes survive container rebuilds. They are separate from both the
image and the build cache, and none of the figures above include them. Measured
inside the container on 2026-08-20:

| Volume | Mount | Size |
|---|---|---|
| `<folder>-venv-noble-py3.12-<id>` | `/opt/venv` | 1.2GB |
| `<folder>-r-site-library-noble-4.5.3-<id>` | `/opt/R/4.5.3/lib/R/site-library` | 789MB |
| `<folder>-codex-config-<id>` | `/home/node/.codex` | 613MB |
| `<folder>-npm-global-noble-node24-<id>` | `/usr/local/share/npm-global` | 584MB |
| `<folder>-claude-config-<id>` | `/home/node/.claude` | 24MB |
| `claude-code-bashhistory-<id>` | `/commandhistory` | 36KB |

`<id>` is `${devcontainerId}`, a ~52-character string identifying the dev
container.

About **3.2GB** in total, or roughly 95% of the image again.

The three package volumes hold what used to be image layers — 103 Python
packages, 245 R packages, and the two AI CLIs. This is the other half of the
trade described below: those bytes did not disappear when the stacks left the
image, they moved to volumes, where they survive container recreation without
being rebuilt.

Budget for more than one set. Every volume is keyed by `${devcontainerId}`, so
each dev container gets its own set — two checkouts cannot collide even when
their folders share a name, which is what stops them from sharing Claude and
Codex auth tokens (and, via `npm-global`, the executables they run). The folder
name is kept as a readable prefix only, so `docker volume ls` stays scannable.
The trade is that the id is derived from the host path: moving or renaming the
project folder orphans its volumes, costing a re-login and an
`install-packages.sh` re-run. Orphans are then hard to identify by name — find
them with `docker volume ls -f dangling=true`. The version tokens (`noble`,
`4.5.3`, `py3.12`, `node24`) mean an R, Python, node, or distro upgrade starts a
*fresh* volume rather than reusing the old one — deliberate, since packages
compiled against different shared libraries must not be mixed, and the CLIs ship
native per-platform binaries. The superseded volume stays on disk until you
remove it with `docker volume rm`.

Session data is not here. `ai-sesh` symlinks `~/.claude/projects` and
`~/.claude/todos` into `/workspace`, so Claude and Codex history consumes
Dropbox-synced host disk rather than volume space.

## Why the image is large

The ~3.4GB figure was measured before the AI CLIs left the image, so expect
roughly 550MB less on the next cold build. The main contributors are:

- the system-package layer containing `texlive-full` — TeX Live 2023 at about
  3.2GB, by far the largest single component;
- LyX, compiled from source, which keeps its Qt5 `-dev` packages in the image
  (they carry the Qt runtime it links against);
- Pandoc and Git, built from source;
- the R interpreter itself; and
- recursive ownership and permission changes, which create filesystem-layer
  metadata.

Note what is *not* here any more. The R and Python **packages** left the image
and now install at runtime via `install-packages.sh`; the Dockerfile creates
only an empty venv at `/opt/venv` and the bare R library directory. The **AI
CLIs** left the same way, into the npm-global volume above — that move was about
update persistence rather than size, but it takes their weight out of the image
too.

## Diagnosing cache eviction

Docker commands can report different sizes because they measure different
things. `docker image inspect`, `docker system df -v`, `docker history`, and
`docker buildx du --verbose` are therefore not directly interchangeable.
BuildKit's disk-usage view is the relevant one when comparing the working set
with `defaultKeepStorage`.

If an unexpectedly slow rebuild follows a small edit, inspect the image with
`docker history <image>`. An age discontinuity in an otherwise unchanged
Dockerfile indicates eviction: older layers below the discontinuity remained
cached, while a newer band of unchanged layers had to be rebuilt.
