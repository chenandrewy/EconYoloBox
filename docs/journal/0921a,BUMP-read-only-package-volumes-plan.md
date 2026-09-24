# 0921a — plan: R, Python and TeX as host-built, read-only volumes, one builder

Discussion snapshot, 2026-09-21, branch `yolo-default-posture`. Decided; not
yet implemented. BUMP: needs a rebuild and a host-side volume build, so it
waits until the current posture changes have settled and there is a quiet
moment to test.

## the idea

Treat the R site-library and the Python venv the way TeX Live is treated
since [0910a](0910a,texlive-volume-implemented.md): built by the human on the
host into a named Docker volume, mounted read-only in every consuming
container. Then fold TeX into the same machinery so all three are symmetric:
one in-container installer with a target per stack, one host wrapper that runs
it in the sandbox image with the volumes mounted read-write. The principle is
a clean boundary: **agents inside the container only execute; the human
maintains the environment.**

Today ([install-packages.sh](../../.devcontainer/install-packages.sh)) both
stacks are installed *at runtime, as `node`*, into per-devcontainer writable
volumes (`devcontainer.json` mounts keyed by `${devcontainerId}`), and the
user-level CLAUDE.md tells agents that package installs from allowlisted
sources need no permission. That is convenient and, under the egress-only
threat model, not a security hole. But it means the environment is partly
agent-maintained, the base R library is world-writable
(`Dockerfile` `chmod -R a+w`), and every new project pays a multi-minute stack
rebuild.

## why this is not quite TeX

| | TeX Live | R / Python packages |
|---|---|---|
| Builder image | bare `ubuntu:24.04`; TeX is self-contained | **must be the sandbox image itself**: R packages link against the image's shared libraries (`devcontainer.json` already warns a bookworm-built volume must never mount into noble). pip wheels are manylinux, so Python is less coupled, but use the same builder for uniformity. |
| Change rate | once a year | packages get added; the volume must be cheap to update |
| Sharing | one volume per daemon | same, once read-only: the `${devcontainerId}` keying only existed to keep *writable* volumes from leaking between projects |

## implementation scope

1. **One in-container installer.** `install-packages.sh [python|r|tex|cli]`
   gains a `tex` target holding what `texlive.sh` does today: `install-tl`
   with the noninteractive full-scheme profile into `/usr/local/texlive` when
   the volume is empty, then `fmtutil-sys`, `updmap-sys`, smoke compiles.
   The sandbox image already has every prerequisite the one-off Ubuntu
   builder had to `apt-get` (`perl`, `wget`, `xz`, `ca-certificates`,
   `libfontconfig1` via LyX's Qt), so the throwaway builder image goes away.
   Semantics per target:
   - `python`, `r`: idempotent as now; present packages skipped, `--force`
     redoes. Re-running into an existing volume is how packages get added.
   - `tex`: install if empty, no-op if present, `--force` refused. Full
     scheme has every package, so there is no "add"; updates stay separate
     manual work. "Present" means a marker the installer writes after the
     smoke compiles pass, not "nonempty": the one failure so far came after
     every package had downloaded ([0910a](0910a,texlive-volume-implemented.md)).
     Anything else nonempty is a failed install; refuse and point at
     `install.log`.
   - `cli`: unchanged, always `@latest` into the writable `npm-global`.
     In-container only: the npm volume is per-devcontainer, so a host
     builder would install it into its own disposable layer.
   - host default is `python r`; `tex` is explicit opt-in (the container
     already tolerates a missing TeX, so a user who never wants LaTeX never
     downloads it); `all` = `python r tex`.
   - the builder runs as root: the image ends in `USER node` and the plan
     drops node ownership of the trees. Read-only consumers do not care.

2. **One host script `.setup/packages.sh [targets]`**, replacing
   `texlive.sh`. Resolves the sandbox image, then runs the installer in it
   with the volumes read-write and the repo's `.devcontainer/` bind-mounted:

   ```sh
   docker run --rm \
     --mount type=volume,source=r-site-library-noble-4.5.3-2026-07-15,target=/opt/R/4.5.3/lib/R/site-library \
     --mount type=volume,source=venv-noble-py3.12,target=/opt/venv \
     --mount type=volume,source=texlive-2026-noble,target=/usr/local/texlive \
     --mount type=bind,source=$PWD/.devcontainer,target=/setup,readonly \
     sandbox-image bash /setup/install-packages.sh "$@"
   ```

   Docker's default network, no devcontainer firewall, like `texlive.sh`
   today. Two details:
   - *Which image.* The volume must be built with the image that will
     consume it: after a `CRAN_SNAPSHOT` or `R_VERSION` edit the old image
     still carries the old `Rprofile.site`. So a bump is: edit Dockerfile,
     `bbox --rebuild`, then build the volume. Resolving the devcontainer's
     image is new code (`dc-resolve.py` resolves containers, not images); a
     plain `docker build .devcontainer` works if it passes the same
     `--build-arg`s (`TZ`) or it recompiles LyX.
   - *Volume names in one place.* `texlive-2026-noble` is currently literal
     in both `devcontainer.json` and `texlive.sh` with a "keep in step"
     comment. With three volumes, have the host script read the names out of
     `devcontainer.json` instead of duplicating them.

3. **Mounts** in `devcontainer.json`: drop the `${devcontainerId}` key, add
   `readonly`, name by base + interpreter version + snapshot date:

   ```
   source=r-site-library-noble-4.5.3-2026-07-15,target=/opt/R/4.5.3/lib/R/site-library,type=volume,readonly
   source=venv-noble-py3.12,target=/opt/venv,type=volume,readonly
   source=texlive-2026-noble,target=/usr/local/texlive,type=volume,readonly   (unchanged)
   ```

   One architecture per daemon, as with TeX. `npm-global` stays writable: it
   holds the agent CLIs and `install-packages.sh cli` is how they get updated
   from inside.

4. **Dockerfile**: remove `chmod -R a+w .../lib/R/library`, the `chown node`
   on site-library and `/opt/venv` (read-only, ownership is moot). Keep the R
   binary, the venv skeleton and LyX in the image; R itself is a pinned
   immutable `.deb` whose apt dependencies have to be in the image
   regardless, so volume-ing `/opt/R` wholesale buys nothing.

5. **In-container guards**: `install-packages.sh python|r|tex` refuses when
   the target is read-only and prints "on the host run
   `bash .setup/packages.sh <target>`", mirroring `tex-refresh`.
   `post-start.sh` warns when a stack is missing, tested by a sentinel
   (`import pyfixest`, `requireNamespace("fixest")`, the TeX marker), not by
   emptiness: Docker seeds a fresh volume from the image directory even
   under a read-only mount, so the venv skeleton is always there.

6. **Docs and agent guidance**: the line "installing packages from
   allowlisted sources is fine" becomes "ask the user to add it" in both
   `SANDBOX-CLAUDE.md` and `SANDBOX-AGENTS.md`; the rest is a checklist
   below.

7. **Test** `.devcontainer/tests/test-packages.sh` absorbing
   `test-texlive.sh`: read-only mounts, `library()` every package in the R
   list and import every Python distribution, a `fixest` regression, an
   `arrow`/`pyarrow` parquet round-trip, the existing TeX/LyX checks, and
   confirm `install.packages()` / `pip install` of a package not already
   present fail rather than silently landing elsewhere. Building TeX in the
   sandbox image also lets the builder smoke-test a LyX export, which the
   bare-Ubuntu builder could not.

Rough size: a day. The risky bit is proving that nothing in either stack
writes into its own install directory at runtime (nothing in the current
lists should; the test is what proves it).

## R behaviour with a read-only library

Nothing to configure. R adds a library to `.libPaths()` when the directory
exists and never writes into it on load; a read-only system library is the
standard multi-user setup. Non-interactive `install.packages()` fails with
`'lib' is not writable` / `unable to install packages`. Interactively R offers
to create `~/R/<platform>-library/4.5`, which lives in the container's
ephemeral layer and dies at recreate. pip fails with a permission error on
the venv; `--user` is refused inside a venv ("user site-packages are not
visible in this virtualenv"), so the pip scratch path is `--target` or a
project venv, not `~/.local`.

## how a user adds a package

1. Edit the list: `cran_pkgs` / `archive_pkgs` or `PY_PKGS` in
   `.devcontainer/install-packages.sh`. Commit it; the list is the
   environment's declaration.
2. On the host: `bash .setup/packages.sh` (or `packages.sh r` /
   `packages.sh python`). It re-runs the idempotent installer into the
   *existing* volume, so only the new package downloads: a minute or two for a
   P3M binary.
3. Restart R / Python sessions in running containers. The read-only mount
   sees the new files immediately; no rebuild, no `devcontainer.json` change.
   Stop R and Python work in every consumer first, the rule
   [0909c](0909c,texlive-volume-simple-plan.md) set for TeX; an unpinned pip
   addition can replace existing dependencies, not just add. Re-running the
   installer is the repair after a partial failure.

A snapshot or interpreter bump is the other path: bump `CRAN_SNAPSHOT` /
`R_VERSION` in the Dockerfile, change the volume name in `devcontainer.json`,
build the new volume from scratch, `bbox --rebuild`, prune the old volume
later.

**Agents** ask. That is already the rule for blocked hosts ("ASK THE USER TO
ADD IT"); package additions join it. Whether to leave the ephemeral personal
library as a scratch path for prototyping is open: it is harmless (not
persistent, not shared) but muddies the story, since an analysis then depends
on a package the environment does not declare. Default: keep it possible, do
not document it, and rely on the script-header rule (inputs/outputs at the top
of every script) to surface any undeclared dependency.

## why not

Considered and rejected in the discussion leading here:

- *Leave it writable, it is not an egress path.* True, and it was the
  argument for the current design. The gain here is conceptual, not a
  security fix: the same maintenance model for every piece of key software.
  The precise claim is "agents cannot modify the three mounted package
  trees", not "agents cannot drift the environment": scratch libraries,
  PATH shadowing, and editing the installer list for the human to execute at
  the next build all remain, and the last is closed only by reading the
  diff before building.
- *Read-only shared base plus a writable per-project `R_LIBS_USER` layer.*
  Keeps agent installs but reintroduces the version shadowing the Dockerfile
  comment rejected ("deliberately no user-level layering").
- *Put `/opt/R` itself in the volume.* See scope item 4.
- *Keep the bare-Ubuntu TeX builder.* It exists only because TeX was done
  first; the sandbox image has all its prerequisites and is the environment
  the result will actually run in.

## implementation checklist

Small things a Codex review (`gpt-6-astra`, 2026-09-21) caught; not plan
decisions.

- `install-packages.sh` parses one target, last wins (`:42`); accept several.
- Its R verification runs in the same process that already loaded namespaces
  via `requireNamespace()` (`:163`), so a failed `--force` passes; verify in a
  fresh `Rscript`.
- The read-only install test must use a package not already present, or it
  passes vacuously. Test both creation orders (consumer first, builder first).
- Files with live package-install wording besides the agent guidance:
  `shellrc.sh:26,166`, `tex-refresh.sh:12`, `features.md:137`,
  `.setup/README.md`, `.devcontainer/README.md`.
