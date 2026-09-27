# 0926f — plan: bake the base into the image; Docker seeds the volumes

2026-09-26, branch `feature/package-install-modes`. Follows
[0926e](0926e,container-only-setup-plan.md). Implemented and checked; see [log](#log). Step 6 skipped.

## why

First setup asks a new user for a normie round trip: edit SANDBOX.toml, `bbox
--rebuild`, `install-base.sh`, edit back, `bbox --rebuild`, plus
`install-base.sh cli`. The first build could do all of it instead.

Docker seeds an empty named volume from the image's contents at the mount
point, the first time it is mounted. So if the image build runs
`install-base.sh` into `/opt/venv`, the R site library and
`/usr/local/texlive`, the first container start fills the volumes, in YOLO
mode, with no network needed at runtime.

Checked on the host 2026-09-26: a fresh volume mounted `readonly` over
`/etc/apt` of `ubuntu:24.04` came out holding `/etc/apt`'s contents. Seeding
happens for read-only mounts too.

The image is still the builder, as 0926e requires: R packages link against
the image's libraries and install from its P3M snapshot.

## what it does not change

- Seeding happens once, into an empty volume. After that the volume hides the
  image's copy. Base changes (a new package, a version bump) still go through
  normie mode or a new volume name, as today. This plan is for first setup.
- Existing volumes are not empty (they hold at least the skeleton), so they
  are never seeded. A user whose volumes are unbuilt skeletons can
  `docker volume rm` them, and the next `bbox --rebuild` seeds them.
- The optional set stays a normie-mode install.
- The AI CLIs stay out of the image (a baked `@latest` layer freezes; see the
  Dockerfile note). They get installed at startup instead (step 4).

## costs accepted

- First build: roughly 10–20 min longer. A CTAN or PyPI failure fails the
  image build; rerunning the build is the retry.
- Image: roughly 1–2 GB larger per checkout, hidden at runtime (measure in
  check 7).
- Any change to the install layer's inputs (the installer, anything above it
  in the Dockerfile) reruns the install on the next rebuild. The layer's inputs
  must stay few.
- pip and tlnet are unpinned, so builds on different days differ. Same as a
  normie install today; the build cache just hides when it happened.

## decisions

1. **Build context.** `install-base.sh` is in `.setup/`, outside the build
   context (`.devcontainer/`). Recommend: set `build.context` to `..` in
   devcontainer.json, prefix the Dockerfile's `COPY` sources with
   `.devcontainer/`, and add `.devcontainer/Dockerfile.dockerignore`
   (BuildKit reads it in place of `.dockerignore`) that excludes everything
   but `.devcontainer/` and `.setup/install-base.sh`. Otherwise the build
   would send `workspace/`, `cellar/` and `done/` to the daemon.
   Alternative: move `install-base.sh` into `.devcontainer/`. That fits
   0926d's rule ("tools baked into the image") but splits it from
   `install-optional.sh` and puts it back where 0926d moved it from.
2. **Build mode.** A new `--image-build` flag. It skips the normie checks,
   which cannot pass in a build (no mounts, no firewall marker), and instead
   requires the opposite: node, and no target directory a mount point. So it
   refuses in any running container, where the targets are mounts. It also
   skips the `/.dockerenv` check, which a BuildKit `RUN` does not have, and
   `tex-refresh` (post-start runs it). `cli` is not accepted with it.
3. **Layer placement.** After everything the installer needs (R, LyX,
   poppler-utils, the TeX symlink, pandoc if the smoke test needs it) and
   before the frequently edited policy `COPY`s at the end. The
   `COPY .setup/install-base.sh` goes right before its `RUN`, so edits to
   the policy files or the firewall don't rerun the install.

## steps

- [x] 1. `install-base.sh --image-build` (decision 2). Header, usage and
  `.setup/README.md` describe it; the refusal messages say it is for the
  Dockerfile only.
- [x] 2. Build context (decision 1): devcontainer.json `build.context`,
  `COPY` prefixes, `Dockerfile.dockerignore`. Check `bbox`/`dc-resolve.py`
  don't assume the context.
- [x] 3. Dockerfile: move the TeX symlink and anything else the smoke tests
  need above the install layer; add `COPY` + `RUN install-base.sh
  --image-build python r tex` as node (decision 3). Rewrite the "stacks are
  NOT baked" comment and the skeleton comments.
- [x] 4. `post-start.sh`: if `claude` or `codex` is missing, run
  `install-base.sh cli` (npm is on the allowlist, and the volume is writable
  in every mode). A failure warns and moves on. shellrc.sh's reminder stays for
  the failure case.
- [x] 5. Docs: README minimal setup (step 4 waits longer; step 6 goes away or
  becomes "update the CLIs"), `.setup/README.md` first setup (normie round
  trip only for base changes and version bumps, plus the `docker volume rm`
  note for skeleton volumes), devcontainer.json mount comments, features.md,
  agent guidance where it says the base is installed by hand.
- [ ] 6. (optional) Divergence note: the build writes the base lists'
  checksum to `/usr/local/share/sandbox-base`; `install-base.sh` writes the
  same into each volume; post-start warns when an image's lists are newer
  than a volume's. Skip if it grows beyond a few lines.

## checks

- [x] 7. Fresh volumes from empty, in YOLO mode (replaces 0926e check 6):
  temporary volume names in devcontainer.json, `bbox --rebuild`. The volumes
  come up filled and node-owned; `test-packages.sh` passes; the CLIs are
  installed by post-start. Record build time and image size. Revert the names,
  remove the temporary volumes.
- [x] 8. Existing volumes: `bbox --rebuild` with today's names changes
  nothing in them; `test-packages.sh`, `test-optional.sh` pass.
- [x] 9. `install-base.sh --image-build` refuses in a running container (YOLO
  and normie). `test-bbox.zsh`, `test-setup.py`, `test-agent-policy.sh`,
  shellcheck.
- [x] 10. Rebuild after editing a policy file: the install layer stays cached.

## log

- Decision 1 as recommended: `build.context` `..`, `COPY .devcontainer/...`,
  `.devcontainer/Dockerfile.dockerignore` (`*`, `!.devcontainer/`,
  `!.setup/install-base.sh`). Checked on a scratch build that BuildKit honors
  the Dockerfile-named ignore file with a parent context: `workspace/` and
  `install-optional.sh` stayed out.
- The script is bind-mounted (`RUN --mount=type=bind`), not copied; the
  Dockerfile already needed BuildKit for its heredoc. The layer sits after
  the TeX symlink and `tex-refresh` COPY, before the firewall and policy
  files. The TeX symlink needed no move.
- `--image-build`: node check first (so the host gets a plain refusal, not a
  missing-Rscript error), then every target must exist, be writable and NOT be
  a mount. Rejects `cli`, `--verify`, `--force`; no targets means python r
  tex. Skips `tex-refresh`. Checked: refuses on the host (not node) and in
  the running YOLO container (`/opt/venv is a mounted volume`); `cli`
  rejected. shellcheck clean (in the container); `test-bbox.zsh`,
  `test-setup.py` pass.
- post-start installs the CLIs before `test-agent-policy.sh`, so the policy
  check sees them on a first start.
- Docs: README drops the "install the AI CLIs" step (7 becomes 6) and the
  "build the package stacks" section becomes "update the AI CLIs" and "add
  to the package stacks". `.setup/README.md` gets "First setup: automatic"
  and "Installing into existing volumes: normie mode". shellrc.sh and
  tex-refresh messages left as they are: normie mode is still the repair.
- Step 6 skipped for now.
- Check 7, first half (host, no rebuild of the real container): standalone
  `docker build` of the image as `sandbox-0926f-test`, repository root as
  context. Install layer 313s (Python 76s, R 40s, TeX 195s incl. smoke tests
  and LyX export); the whole build 5:47 with the layers above cached. Image
  3.53GB -> 5.8GB on disk (content 841MB -> 1.44GB). Then three fresh
  volumes mounted `readonly` over the targets: all came up seeded, node-owned,
  `ro`; `install-base.sh --verify python r tex` OK; `import pyfixest`,
  `library(fixest)`, `pdflatex` on PATH. Seeded sizes 482M / 767M / 201M,
  the same as storage-needs.md's lean-base figures. Test volumes and tag
  removed; build cache kept.
- Still open: check 7 second half (a real `bbox --rebuild` with temporary
  volume names: post-start CLI install, `test-packages.sh`), checks 8-10.
- VS Code was attached, so bbox refused the rebuild; the user was away and said
  to kill it. `quit app` hung (a dialog, presumably), so it was killed with
  SIGKILL. This session ran in Ghostty, so it was unaffected.
- Check 7, second half: devcontainer.json temporarily pointed the three
  package volumes and npm-global at fresh names (`t0926f-*`), then
  `bbox --rebuild`, in the user's current posture (normie: open, writable,
  unconfined). Read-only seeding was shown by the standalone test above. The
  rebuild took 30s (image cached). post-start: "installing the AI CLIs", npm
  "added 4 packages in 9s", "AI CLIs OK", then test-agent-policy PASS with
  both CLIs present; no "not built" warning. `test-packages.sh` PASS (135 R
  packages load, fixest, pdflatex/biber/latexindent/latexmk, LyX); volumes
  node-owned.
- Check 10: a blank line appended to SANDBOX-codex-config.toml, standalone
  build: the install-base.sh layer CACHED. Reverted.
- Check 8: real names restored, `bbox --rebuild`: no CLI install (already
  present), no "not built" warning, `test-packages.sh` PASS. The real volumes
  are the same size as before (201M / 767M / 482M, TeX marker from 03:00, before
  this work). `test-optional.sh` FAILs, but only because the optional set was
  never installed in these volumes (`install-optional.sh --verify` lists
  everything missing). That predates this change.
- Check 9 covered by the earlier refusal checks, shellcheck and host tests.
  Temporary `t0926f-*` volumes removed.
- Uncached build (standalone `docker build --no-cache`, ubuntu:24.04 already
  pulled): 8:53 in all, the install-base.sh layer 4:10 of it (Python 37s, R
  18s, TeX and smoke tests the rest). Test tag removed.
- Fresh-checkout test in YOLO mode. Deleting the real package volumes and the
  running container was refused by the permission check, so instead: a local
  clone of the branch at ~/EconYoloBox-freshtest (new devcontainerId, so fresh
  claude/codex config, npm-global and bash-history volumes), its
  devcontainer.json pointing the package volumes at `t0926f-fresh-*`, committed
  SANDBOX.toml (YOLO), plain `devcontainer up` with no SANDBOX_* env, as
  VS Code would. 5:19. post-start installed the CLIs (9s), "YOLO mode:
  internet=firewalled packages=readonly seccomp=builtin", no "not built"
  warning. `test-packages.sh` PASS ("readonly R/Python/TeX volumes ...
  installs refused"). Mounts `ro`, node-owned. A new zsh prints no notes.
- Curiosity: in the clone every layer was CACHED except the install layer,
  which reran (250s). Its only extra input is the bind-mounted script, identical
  in content, so the key must include file metadata that differs between the
  Dropbox checkout and ~ (xattrs?). Not chased; a new user's first build is
  uncached anyway.
- Clone, its container, image and all seven of its volumes removed. The user's
  container and volumes were untouched throughout.

