# Setup

`.devcontainer/setup/` is provisioning run inside the container: the package volumes and
the AI CLIs. The first build and first start run `install-base.sh` for you
(docs/journal/0926f); you run it by hand to change the base. `.devcontainer/host/` is the launcher (`ybox`), and
`.devcontainer/` is the container itself: its definition, its startup, and the
tools baked into it (docs/journal/0926d).

| Script | What it installs | Where it runs |
|---|---|---|
| `install-base.sh` | the base: Python, R, TeX Live and the AI CLIs | in the container, normie mode; `cli` and `--verify` in any mode; `--image-build` in the Dockerfile |
| `install-optional.sh` | the optional set | in the container, normie mode; `--verify` in any mode |
| `install-vscode-extensions.sh` | the 12 workspace VS Code extensions | in a VS Code terminal in normie mode; `--verify` in either mode |

## VS Code extensions

On a fresh checkout or extension volume, open `ybcode --normie` on the host.
In its VS Code integrated terminal, run:

```sh
bash .devcontainer/setup/install-vscode-extensions.sh
```

The script calls VS Code's `code --install-extension` CLI sequentially inside
normie. It checks the shared volume's extension registry and directories and
fails if one is missing. Then open `ybcode` for YOLO mode. YOLO mounts the same
volume read-only and has no automatic extension installation. To check it
without writing, run `bash .devcontainer/setup/install-vscode-extensions.sh
--verify` in either mode. Both configs disable automatic extension updates;
run the install command again in normie when updating.

`tomoki1207.pdf` is a UI-only extension (`extensionKind: ["ui"]`). It runs in
the host VS Code, not the container, and is already installed on this host.
On a new host, install it once in local VS Code. It does not belong in the
shared container volume or this script's registry check.

Packages change only in normie mode, from inside (docs/journal/0926e). Run
both as `ubuntu`; `install-base.sh` refuses on the host.

## Package volumes: R, Python and TeX Live

The volumes hold a lean **base** and an **optional set** (docs/journal/0926a,
0926b). The base is what the yolobox's own tools and tests need plus a small
core, and the AI CLIs; the optional set is everything else we use.

### First setup: automatic

The image carries the base. Its build runs `install-base.sh --image-build`,
which installs python, r and tex into the image's own `/opt/venv`, R site
library and `/usr/local/texlive`. The first time Docker mounts an empty named
volume, it copies the image's contents at the mount point into it (read-only
mounts included; checked 2026-09-26), so a new checkout's first build comes up
with the base, in YOLO mode. The first start then installs the AI CLIs:
`post-start.sh` runs `install-base.sh cli` while either is missing. After the
first build, `bash .devcontainer/setup/tests/test-packages.sh` checks the result.

Seeding happens once. A volume that holds anything, even the bare skeleton an
older image left, is never touched again, and the volume hides the image's
copy. So:

- Volumes created before 0926f that were never filled stay empty skeletons.
  Remove them on the host (`docker volume rm <volume>`, after stopping every
  container that mounts them), then `ybox --rebuild` to seed them.
- A change to the base lists reaches the image at the next rebuild, but not
  existing volumes. Those change as below, or get a new name.

The install layer reruns whenever `install-base.sh` or anything above it in
the Dockerfile changes, and a CTAN or PyPI failure fails the build; rebuilding
is the retry.

### Installing into existing volumes: normie mode

Installing the optional set, adding to the base in volumes that already exist,
or repairing one, happens from inside, in normie mode:

1. Open the normie container: on the host, `ybcode --normie` (or
   `ybe --normie`).
2. In the container: `bash .devcontainer/setup/install-base.sh` (for a base change or a
   repair; it skips what is present).
3. Optionally, in the container: `bash .devcontainer/setup/install-optional.sh`.
4. Back to YOLO mode: on the host, `ybcode` (or `ybe`) opens the YOLO
   container, which already sees the new packages; `ybox --stop --normie`
   stops the normie one.
5. In the YOLO container: `bash .devcontainer/setup/tests/test-packages.sh`.

Skipping step 3 is fine; the base passes its tests alone, and a project can
install just what it needs in normie mode instead.

From anywhere in the repository, in the container:

```sh
bash .devcontainer/setup/install-base.sh            # python r tex cli (the default)
bash .devcontainer/setup/install-base.sh tex        # minimal TeX Live only
bash .devcontainer/setup/install-base.sh r          # R only
bash .devcontainer/setup/install-base.sh r --force  # reinstall present R packages
bash .devcontainer/setup/install-base.sh cli        # AI CLIs only; any mode
bash .devcontainer/setup/install-base.sh --verify   # check the base; writes nothing; any mode
```

`python`, `r` and `tex` check for normie mode before installing anything, the
same way `install-optional.sh` does: running as `ubuntu`, their mounts writable
and `ubuntu`-owned, and the firewall open (`post-start.sh`'s marker). They check
the container itself, not a file. In YOLO mode they refuse and say how to switch.

The devcontainer's own image is the builder, which is the point: R packages
link against the image's libraries and install from its pinned P3M snapshot.
After a `CRAN_SNAPSHOT`, `R_VERSION` or base image change, the order is: edit
the Dockerfile, give the volume a new name in `devcontainer.json`, then
`ybox --rebuild`, which builds the base into the image and seeds the new
volume. The optional set then goes in with the steps above.

The AI CLIs live in the per-checkout npm-global volume, which is writable in
every mode, so `bash .devcontainer/setup/install-base.sh cli` updates them in YOLO mode too.

Volume names are written once, in `.devcontainer/devcontainer.json`. To try a
new volume, rename it there and `ybox --rebuild`; Docker seeds it from the
image, which already carries the base. Rename back to abandon it, and remove
the unused volume with `docker volume rm`.

After a rebuild, `bash .devcontainer/setup/tests/test-packages.sh` (as `ubuntu`, in the
container) is the acceptance check for the base in either mode;
`bash .devcontainer/setup/tests/test-optional.sh` checks the optional set.

Stop R, Python and TeX work in every other container that mounts the volumes
before an install. An unpinned pip addition can replace existing dependencies,
not only add. Once it finishes, restart R and Python sessions. After a TeX
change, run `tex-refresh` as `ubuntu` and reopen LyX (`install-base.sh tex` runs
`tex-refresh` in the container it installs from).

### Volume ownership

The volumes are `ubuntu`-owned. Docker seeds a new volume from the image
directory it is mounted over, ownership included, and the Dockerfile creates
`/opt/venv`, the R site library and `/usr/local/texlive` owned by `ubuntu`.
Ownership is not the protection: in YOLO mode the mount is read-only, which
the kernel enforces whatever the owner, and `ubuntu` cannot remount
(docs/journal/0926e).

A volume that is not `ubuntu`-owned was created by an older image, before 0926e.
`ubuntu` cannot fix that from inside. Either give the volume a new name and fill
it again, or, on the host, chown it once:

```sh
docker run --rm --mount type=volume,source=<volume>,target=/v ubuntu:24.04 chown -R 1000:1000 /v
```

### Adding a package

Usually in normie mode: `install.packages("x")`, `pip install x` or
`tlmgr install x` in the container, as `ubuntu`. If the package is generally
useful, also add it to a list in `.devcontainer/setup/install-optional.sh` so the
next rebuild of the volume brings it back; an ad hoc install that is not added
is lost then. `install-optional.sh` prints each command it runs, so it doubles
as the reference for pryr (CRAN archive) and Bioconductor installs.

The base changes only when the yolobox itself needs something:

1. Edit the list in `.devcontainer/setup/install-base.sh`: `PY_PKGS`,
   `cran_pkgs`, or `TEX_PKGS` (TeX package or collection names). Commit it;
   the list is the environment's declaration.
2. In normie mode, in the container: `bash .devcontainer/setup/install-base.sh r` (or
   `python`, `tex`). It re-runs the idempotent installer into the existing
   volume, so only the new package downloads.
3. Switch back to YOLO mode. Restart sessions in other running containers;
   the mount sees the new files immediately. No `devcontainer.json` change is
   needed.

Rerunning the same command is the repair after a partial failure.

A snapshot or interpreter bump is the other path. Change the version in the
Dockerfile, then give the volume a new name in `devcontainer.json`. The next
`ybox --rebuild` builds the base into the new image and seeds the new volume
from it; prune the old volume later.

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

The installer decides by the `.yolobox-installed` marker in the volume (a
volume built before the rename has `.sandbox-installed`, which an install
renames):

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
devcontainers (writable in normie mode), one architecture per volume. The image
build downloads TeX, and the first mount of an empty volume copies it in;
opening a project never downloads TeX. Startup warns when TeX is missing.

To read the TeX log without changing anything:

```sh
docker run --rm --mount type=volume,source=texlive-2026-base-noble,target=/texlive,readonly \
  ubuntu:24.04 cat /texlive/install.log
```

Installation reference: [upstream installer manual](https://tug.org/texlive/doc/install-tl.html).
