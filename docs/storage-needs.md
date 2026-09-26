# Devcontainer storage needs

What the sandbox costs on disk: the image, the BuildKit build cache, and the
persistent volumes. The shared workspace devcontainer is built locally from
`.devcontainer/Dockerfile`, starting from the official `ubuntu:24.04` image.

Rough current total: the image (not yet re-measured; see below), about
**4.7GB** of shared package volumes once per Docker daemon, and about
**1.0GB** of volumes per sandbox checkout. The build cache comes on top of
that.

## Image size

The image has not been measured since TeX Live left it. On the host,
`docker image ls` gives the current figure.

The last measurement, on 2026-07-26 after the Ubuntu base migration, found a
**3.42GB image built cold in about 9 minutes** on arm64, down from roughly
24GB before. Since then, three large components have left the image:

- TeX Live (`texlive-full`, about 3.2GB) moved to a shared read-only volume
  on 2026-09-10, now the minimal `texlive-2026-small-noble`;
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
the image or build-cache figures above. Measured with `du -sh` inside the
rebuilt devcontainer on 2026-09-26
([0925b](journal/0925b,BUMP-package-volumes-implementation.md)).

**Shared package volumes**, one set per Docker daemon. They are built on the
host by `.setup/packages.sh` and mounted read-only:

| Volume | Mount | Size |
|---|---|---|
| `texlive-2026-small-noble` | `/usr/local/texlive` | 3.0GB |
| `venv-noble-py3.12` | `/opt/venv` | 1.2GB |
| `r-site-library-noble-4.5.3-2026-07-15` | `/opt/R/4.5.3/lib/R/site-library` | 536MB |

About **4.7GB** in total. Every project in the workspace uses these through
the one devcontainer. A second sandbox checkout on the same daemon would
mount the same three volumes instead of building its own.

The names carry version tokens (`noble`, `4.5.3`, the P3M date, `py3.12`,
`2026`). A distro, R, snapshot, Python or TeX Live bump therefore builds a
*fresh* volume under a new name rather than altering the old one, because
packages compiled against different shared libraries must not be mixed. The
superseded volume stays on disk until you remove it with `docker volume rm`.

**Per-devcontainer volumes**, one set per sandbox checkout:

| Volume | Mount | Size |
|---|---|---|
| `<folder>-npm-global-noble-node24-<id>` | `/usr/local/share/npm-global` | 560MB |
| `<folder>-codex-config-<id>` | `/home/node/.codex` | 396MB |
| `<folder>-claude-config-<id>` | `/home/node/.claude` | 26MB |
| `claude-code-bashhistory-<id>` | `/commandhistory` | 48KB |

About **1.0GB** in total. `<id>` is `${devcontainerId}`, a ~52-character
string identifying the devcontainer. Keying by it gives each checkout its own
set, so two checkouts never share Claude and Codex auth tokens or, through
`npm-global`, the executables they run. This holds even when their folders
share a name. The folder name is only a readable prefix that keeps
`docker volume ls` scannable. The id is derived from the host path, so moving
or renaming the sandbox folder orphans these volumes. That costs a re-login
and an `install-packages.sh cli` re-run. Orphans are hard to identify by name,
so find them with `docker volume ls -f dangling=true`.

**Superseded volumes** from before 0925b stay on disk until pruned: the full
TeX tree `texlive-2026-noble` (11GB) and each checkout's old
`<folder>-venv-noble-py3.12-<id>` (1.2GB) and
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
