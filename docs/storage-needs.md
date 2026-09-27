# Devcontainer storage needs

What the sandbox costs on disk: the image, the BuildKit build cache, and the
persistent volumes. The shared workspace devcontainer is built locally from
`.devcontainer/Dockerfile`, starting from the official `ubuntu:24.04` image.

For the intended setup of **one sandbox checkout and one devcontainer**, the
persistent volumes use about **2.8GB**: about **1.5GB** for the lean R,
Python, and TeX base, plus about **1.3GB** for the AI CLIs and agent
configuration, nearly all of it CLI binaries. Installing the optional set
raises the package volumes to about **4.7GB** (6.0GB in all). The current image and BuildKit cache use additional
space; the image has not been re-measured. Old volumes also occupy space until
removed.

## Image size

The image has not been measured since TeX Live left it. On the host,
`docker image ls` gives the current figure.

The last measurement, on 2026-07-26 after the Ubuntu base migration, found a
**3.42GB image built cold in about 9 minutes** on arm64, down from roughly
24GB before. Since then, three large components have left the image:

- TeX Live (`texlive-full`, about 3.2GB) moved to a shared volume
  on 2026-09-10, now `texlive-2026-base-noble`;
- the AI CLIs (about 550MB) moved to the per-checkout npm-global volume;
- the R and Python packages had already moved to volumes before July, and
  since 0925b they are shared, host-built volumes.

So expect the image to be much smaller than 3.42GB.

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

Two kinds of Docker volume survive container rebuilds. Neither is included in
the image or build-cache figures above. All figures were measured with `du -sh`
on 2026-09-26.

**Package volumes** account for about **1.5GB** of the one-checkout total
with the lean base, or about **4.7GB** with the optional set.
There is one set on the Docker daemon. They are filled in normie mode by
`.setup/install-base.sh` and mounted read-only in YOLO mode:

| Volume | Mount | Lean base | With optional set |
|---|---|---|---|
| `texlive-2026-base-noble` | `/usr/local/texlive` | 482MB | 3.0GB |
| `venv-noble-py3.12-base` | `/opt/venv` | 767MB | 1.2GB |
| `r-site-library-noble-4.5.3-2026-07-15-base` | `/opt/R/4.5.3/lib/R/site-library` | 201MB | 536MB |

About **1.5GB** in total for the lean base and **4.7GB** with the optional
set, both measured with `du -sh` inside the YOLO container on 2026-09-26: the
lean base on freshly built volumes, the optional set after installing it in
normie mode. Every project in the workspace uses these through
the one devcontainer.

The names carry version tokens (`noble`, `4.5.3`, the P3M date, `py3.12`,
`2026`). A distro, R, snapshot, Python or TeX Live bump therefore builds a
*fresh* volume under a new name rather than altering the old one, because
packages compiled against different shared libraries must not be mixed. The
superseded volume stays on disk until you remove it with `docker volume rm`.

**Devcontainer-specific volumes** account for about **1.3GB** of the
one-checkout total. About 1.2GB of that is CLI binaries; configuration and
state are about 115MB:

| Volume | Mount | Size | Binaries | Config and state |
|---|---|---|---|---|
| `<folder>-npm-global-noble-node24-<id>` | `/usr/local/share/npm-global` | 559MB | 559MB | — |
| `<folder>-codex-config-<id>` | `/home/node/.codex` | 746MB | 658MB | 88MB |
| `<folder>-claude-config-<id>` | `/home/node/.claude` | 25MB | — | 25MB |
| `claude-code-bashhistory-<id>` | `/commandhistory` | 48KB | — | 48KB |

The npm-global volume holds the CLIs themselves: Codex (329MB) and Claude
Code (230MB), both bundling native binaries. The codex-config volume is
mostly binaries too: Codex downloads its own app-server releases into
`packages/app-server-daemon/releases/`, about 330MB each, and older releases
stay behind (two, 0.157.0 and 0.157.1, on 2026-09-26). Expect this volume to
grow with Codex updates. The rest of it is mainly `logs_2.sqlite` (52MB) and
`thread_history_1.sqlite` (20MB). Claude's volume is mostly plugins (15MB).
Transcripts are not in these volumes (see below).

`<id>` is `${devcontainerId}`, a ~52-character string identifying this
devcontainer. The folder name is a readable prefix for `docker volume ls`.
These volumes hold the AI CLIs and agent configuration for the one intended
checkout. If another checkout were created on the same Docker daemon, it
would share the package volumes but get its own devcontainer-specific volumes.
Moving or renaming the sandbox folder also changes the id and leaves the old
volumes behind. Find unused ones with `docker volume ls -f dangling=true`.

**Superseded volumes** from before 0926b include
`texlive-2026-small-noble`, `venv-noble-py3.12`, and
`r-site-library-noble-4.5.3-2026-07-15`. Older volumes from before 0925b
may also remain: the full TeX tree `texlive-2026-noble` (11GB), plus an old
checkout's `<folder>-venv-noble-py3.12-<id>` (1.2GB) and
`<folder>-r-site-library-noble-4.5.3-<id>` (about 800MB).

Session data is not here. `ai-sesh` symlinks `~/.claude/projects` and
`~/.claude/todos` into `/sandbox`, so Claude and Codex history consumes
Dropbox-synced host disk rather than volume space.

## What is in the image

The main contributors are:

- LyX, compiled from source, which keeps its Qt5 `-dev` packages in the image
  (they carry the Qt runtime it links against);
- Git, built from source, and the upstream Pandoc and pandoc-crossref
  binaries;
- the R interpreter itself;
- the system `-dev` libraries that R packages link against; and
- recursive ownership changes, which create filesystem-layer metadata.

Note what is *not* here any more. TeX Live, the R and Python **packages**,
and the **AI CLIs** all live in volumes (see above). The Dockerfile creates
only an empty venv at `/opt/venv`, the bare R site-library directory, and the
`/usr/local/texlive-bin` symlink into the TeX volume. The CLIs moved for
update persistence rather than size, but the move takes their weight out of
the image too.

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
