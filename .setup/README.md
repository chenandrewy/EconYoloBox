# Host setup

`.setup/` is host machine setup and maintenance, `.host/` is session navigation,
and `.devcontainer/` defines the container.

## Package volumes: R, Python and TeX Live

From anywhere in the repository, on the host with Docker running:

```sh
bash .setup/packages.sh            # python r (the default)
bash .setup/packages.sh tex        # minimal TeX Live, opt-in
bash .setup/packages.sh all        # python r tex
bash .setup/packages.sh r --force  # reinstall present R packages
```

The script runs `.devcontainer/install-packages.sh` as root in a throwaway
container of **this workspace's devcontainer image**, with the shared volumes
mounted read-write. It finds that image by looking up the container labelled
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

Stop R, Python and TeX work in every consuming container before a build. An
unpinned pip addition can replace existing dependencies, not only add. Once the
build finishes, restart R and Python sessions. After a TeX change, run
`tex-refresh` as `node` and reopen LyX.

### Adding a package

1. Edit the list in `.devcontainer/install-packages.sh`: `PY_PKGS`,
   `cran_pkgs`, `archive_pkgs`, `bioc_pkgs`, or `TEX_PKGS` (TeX package or
   collection names). Commit it; the list is the environment's declaration.
2. On the host: `bash .setup/packages.sh r` (or `python`, `tex`). It re-runs the
   idempotent installer into the existing volume, so only the new package
   downloads.
3. Restart sessions in running containers; the mount sees the new files
   immediately. No rebuild or `devcontainer.json` change is needed.

Rerunning the same command is the repair after a partial failure. Bioconductor
packages install with `update = FALSE`, so they never move snapshot-pinned CRAN
packages.

A snapshot or interpreter bump is the other path. Change the version in the
Dockerfile, then give the volume a new name in `devcontainer.json`. Build it
fresh after `bbox --rebuild`, and prune the old volume later.

### TeX Live

TeX is minimal and pdfLaTeX-only: `scheme-small` without `collection-xetex`,
plus `latexextra`, `fontsrecommended`, `bibtexextra` (biblatex, biber),
`pictures` (TikZ), `mathscience` and `fontsextra`, plus `TEX_PKGS`
(`latexindent`, `latexmk`). No documentation or source files are installed.
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
devcontainers, one architecture per volume. Opening a project never downloads
TeX; startup warns when TeX is missing.

To read the TeX log without changing anything:

```sh
docker run --rm --mount type=volume,source=texlive-2026-small-noble,target=/texlive,readonly \
  ubuntu:24.04 cat /texlive/install.log
```

Installation reference: [upstream installer manual](https://tug.org/texlive/doc/install-tl.html).
