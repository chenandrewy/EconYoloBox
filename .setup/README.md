# Host setup

`.setup/` is host machine setup and maintenance, `.host/` is session navigation,
and `.devcontainer/` defines the container.

## Package volumes: R, Python and TeX Live

The volumes hold a lean **base**, built here on the host, and an **optional
set**, which the user installs from inside the container in install mode
(docs/journal/0926a). The base is what the sandbox's own tools and tests need
plus a small core; the optional set is everything else we use. First setup, and
again after a version bump:

1. On the host: `bash .setup/packages.sh all`.
2. Switch to install mode: `packages = "writable"` and `firewall = false` in
   `SANDBOX.toml`, then `bbox --rebuild`.
3. In the container: `bash .devcontainer/install-optional.sh`.
4. Switch back: `packages = "readonly"`, `firewall = true`, `bbox --rebuild`.

Skipping steps 2–4 is fine; the base passes its tests alone, and a project can
install just what it needs in install mode instead.

From anywhere in the repository, on the host with Docker running:

```sh
bash .setup/packages.sh            # python r (the default)
bash .setup/packages.sh tex        # minimal TeX Live, opt-in
bash .setup/packages.sh all        # python r tex
bash .setup/packages.sh r --force  # reinstall present R packages
```

The script runs `.devcontainer/install-packages.sh` as root in a throwaway
container of **this workspace's devcontainer image**, with the shared volumes
mounted read-write, then runs `chown -R node:node` over them so that install
mode works as `node` without sudo. It finds that image by looking up the container labelled
with this folder (`devcontainer.local_folder`). If there is no such container,
or more than one, it refuses: run `bbox --rebuild` first. It never falls back to
another image, because R packages link against the image's libraries and
install from its pinned P3M snapshot. After a `CRAN_SNAPSHOT`, `R_VERSION` or
base image change, the order is: edit the Dockerfile, `bbox --rebuild`, then
build the volume.

The builder uses Docker's default network, so the devcontainer firewall does
not apply. P3M, PyPI, Bioconductor and CTAN are reached from here. The AI CLIs
are not built here: they live in a per-container volume, and
`.devcontainer/install-packages.sh cli` updates them from inside.

Volume names are written once, in `.devcontainer/devcontainer.json`, and read by
`.host/dc-resolve.py package-volumes`. The python, r and tex mounts are found by
their targets. A comment line of the form `// packages.sh: <mount>` stages a
volume: it overrides the live mount with the same target, so a new volume can be
built and checked before any container mounts it. The builder refuses
per-devcontainer (`${devcontainerId}`) names.

Inside the container these volumes are read-only by default:
`install-packages.sh python|r|tex` refuses and points here, and `--verify`
checks without writing. In install mode they are writable (see
`.devcontainer/README.md`, "Working modes"). After a rebuild,
`bash .devcontainer/tests/test-packages.sh` (as `node`, in the container) is
the acceptance check for the base in either mode;
`bash .devcontainer/tests/test-optional.sh` checks the optional set.

Stop R, Python and TeX work in every consuming container before a build. An
unpinned pip addition can replace existing dependencies, not only add. Once the
build finishes, restart R and Python sessions. After a TeX change, run
`tex-refresh` as `node` and reopen LyX.

### Adding a package

Usually in install mode: `install.packages("x")`, `pip install x` or
`tlmgr install x` in the container, as `node`. If the package is generally
useful, also add it to a list in `.devcontainer/install-optional.sh` so the
next rebuild of the volume brings it back; an ad hoc install that is not added
is lost then. `install-optional.sh` prints each command it runs, so it doubles
as the reference for pryr (CRAN archive) and Bioconductor installs.

The base changes only when the sandbox itself needs something:

1. Edit the list in `.devcontainer/install-packages.sh`: `PY_PKGS`,
   `cran_pkgs`, or `TEX_PKGS` (TeX package or collection names). Commit it;
   the list is the environment's declaration.
2. On the host: `bash .setup/packages.sh r` (or `python`, `tex`). It re-runs the
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

- **Empty volume:** installs with `install-tl`, adds `TEX_PKGS`, and runs
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
devcontainers (writable in install mode), one architecture per volume. Opening a project never downloads
TeX; startup warns when TeX is missing.

To read the TeX log without changing anything:

```sh
docker run --rm --mount type=volume,source=texlive-2026-base-noble,target=/texlive,readonly \
  ubuntu:24.04 cat /texlive/install.log
```

Installation reference: [upstream installer manual](https://tug.org/texlive/doc/install-tl.html).
