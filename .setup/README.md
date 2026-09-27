# Setup

`.setup/` is provisioning you run by hand, on the host or in the container:
the package volumes and the AI CLIs. Each script's header says where it runs.
`.host/` is the launcher (`bbox`), and `.devcontainer/` is the container
itself: its definition, its startup, and the tools baked into it
(docs/journal/0926d).

| Script | What it installs | Where it runs |
|---|---|---|
| `install-base.sh` | the base: Python, R, TeX Live and the AI CLIs | host (builds in a throwaway container); `cli` also inside the devcontainer |
| `install-optional.sh` | the optional set | inside the devcontainer, normie mode |

## Package volumes: R, Python and TeX Live

The volumes hold a lean **base**, built here on the host, and an **optional
set**, which the user installs from inside the container in normie mode
(docs/journal/0926a, 0926b). The base is what the sandbox's own tools and tests
need plus a small core, and the AI CLIs; the optional set is everything else we
use. First setup, and again after a version bump:

1. On the host: `bash .setup/install-base.sh`.
2. Switch to normie mode: `internet = "open"`, `packages = "writable"` and
   `seccomp = "unconfined"` in `SANDBOX.toml`, then `bbox --rebuild`.
3. In the container: `bash .setup/install-optional.sh`.
4. Switch back to YOLO mode: `internet = "firewalled"`, `packages =
   "readonly"` and `seccomp = "builtin"`, then `bbox --rebuild`.

Skipping steps 2–4 is fine; the base passes its tests alone, and a project can
install just what it needs in normie mode instead.

From anywhere in the repository, on the host with Docker running:

```sh
bash .setup/install-base.sh            # python r tex cli (the default)
bash .setup/install-base.sh tex        # minimal TeX Live only
bash .setup/install-base.sh r          # R only
bash .setup/install-base.sh r --force  # reinstall present R packages
bash .setup/install-base.sh --verify   # check the base; writes nothing
```

On the host, the script runs itself as root in a throwaway container of
**this workspace's devcontainer image**, with the volumes mounted read-write
(read-only for `--verify`) and `.setup/` at `/setup`, then runs
`chown -R node:node` over them so that normie mode works as `node` without
sudo. It never installs anything on the host itself. It finds that image by looking up the container
labelled with this folder (`devcontainer.local_folder`). If there is no such
container, or more than one, it refuses: run `bbox --rebuild` first. It never
falls back to another image, because R packages link against the image's
libraries and install from its pinned P3M snapshot. After a `CRAN_SNAPSHOT`,
`R_VERSION` or base image change, the order is: edit the Dockerfile,
`bbox --rebuild`, then build the volume.

The builder uses Docker's default network, so the devcontainer firewall does
not apply. P3M, PyPI, Bioconductor, CTAN and npm are reached from here.

The AI CLIs live in the per-checkout npm-global volume, whose name the script
reads from the devcontainer's own mount. That volume is always writable in the
container, so `bash .setup/install-base.sh cli` also updates them from inside,
in either mode.

Volume names are written once, in `.devcontainer/devcontainer.json`, and read by
`.host/dc-resolve.py package-volumes`. The python, r and tex mounts are found by
their targets. A comment line of the form `// install-base.sh: <mount>` stages a
volume: it overrides the live mount with the same target, so a new volume can be
built and checked before any container mounts it. The builder refuses
per-devcontainer (`${devcontainerId}`) names.

Inside the container these volumes are read-only by default:
`install-base.sh python|r|tex` refuses and points here, and `--verify`
checks without writing. In normie mode they are writable (see
`.devcontainer/README.md`, "Working modes"). After a rebuild,
`bash .devcontainer/tests/test-packages.sh` (as `node`, in the container) is
the acceptance check for the base in either mode;
`bash .devcontainer/tests/test-optional.sh` checks the optional set.

Stop R, Python and TeX work in every consuming container before a build. An
unpinned pip addition can replace existing dependencies, not only add. Once the
build finishes, restart R and Python sessions. After a TeX change, run
`tex-refresh` as `node` and reopen LyX.

### Adding a package

Usually in normie mode: `install.packages("x")`, `pip install x` or
`tlmgr install x` in the container, as `node`. If the package is generally
useful, also add it to a list in `.setup/install-optional.sh` so the
next rebuild of the volume brings it back; an ad hoc install that is not added
is lost then. `install-optional.sh` prints each command it runs, so it doubles
as the reference for pryr (CRAN archive) and Bioconductor installs.

The base changes only when the sandbox itself needs something:

1. Edit the list in `.setup/install-base.sh`: `PY_PKGS`,
   `cran_pkgs`, or `TEX_PKGS` (TeX package or collection names). Commit it;
   the list is the environment's declaration.
2. On the host: `bash .setup/install-base.sh r` (or `python`, `tex`). It re-runs the
   idempotent installer into the existing volume, so only the new package
   downloads.
3. Restart sessions in running containers; the mount sees the new files
   immediately. No rebuild or `devcontainer.json` change is needed.

Rerunning the same command is the repair after a partial failure.

A snapshot or interpreter bump is the other path. Change the version in the
Dockerfile, then give the volume a new name in `devcontainer.json`. Build it
fresh after `bbox --rebuild`, and prune the old volume later.

### TeX Live

TeX is minimal and pdfLaTeX-only. The base is `scheme-small` without
`collection-xetex`, plus `bibtexextra` (biblatex, biber) and `TEX_PKGS`
(`latexindent`, `latexmk`, and `cm-super`, which a default LyX export needs for
its T1 fonts). The optional set adds `latexextra`, `fontsrecommended`,
`pictures` (TikZ), `mathscience` and `fontsextra` with `tlmgr install`, which
leaves the base marker alone. No documentation or source files are installed.
LuaTeX remains because it is part of `collection-basic`. The year and platform
come from the image's `/usr/local/texlive-bin` symlink (Dockerfile
`TEXLIVE_YEAR`), and the repository must still serve that year.

The installer decides by the `.sandbox-installed` marker in the volume:

- **Empty volume:** picks one CTAN mirror through `mirror.ctan.org`, retrying
  past any that fails (some serve a certificate wget rejects), and installs
  from it with `install-tl`. It then adds `TEX_PKGS` and runs
  `fmtutil-sys` and `updmap-sys`. Then it smoke-tests pdflatex + biber,
  latexindent, latexmk and a LyX PDF export, and only then writes the marker.
- **Marked volume:** runs `tlmgr install` for any listed collection or package
  the tree lacks, re-runs the smoke tests, and rewrites the marker. If tlmgr
  first has to update itself (tlnet is rolling), it runs `tlmgr update --self`
  once. It never runs `tlmgr update --all`: existing packages keep their
  install-time versions until the volume is deliberately rebuilt.
- **Nonempty, unmarked volume:** an earlier install failed. It refuses. Read the
  log and decide explicitly whether to recreate the volume.

The volume is shared across projects on that daemon and mounted read-only in
devcontainers (writable in normie mode), one architecture per volume. Opening
a project never downloads TeX; startup warns when TeX is missing.

To read the TeX log without changing anything:

```sh
docker run --rm --mount type=volume,source=texlive-2026-base-noble,target=/texlive,readonly \
  ubuntu:24.04 cat /texlive/install.log
```

Installation reference: [upstream installer manual](https://tug.org/texlive/doc/install-tl.html).
