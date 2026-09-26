# 0926b — implementation: three working modes, lean base, optional set

Working checklist, 2026-09-26, branch `feature/package-install-modes`.
Implements [0926a](0926a,package-install-modes-plan.md); read it first.
Container-side work is done. What is left runs on the host (**HOST**): the
container has no Docker socket, so nothing here has been built or rebuilt yet.

## done in the container

- [x] 1. `SANDBOX.toml` gets `packages = "readonly"`. The strict reader behind
  `seccomp-setting.sh` became `strict-setting.sh KEY "SAFE OTHER..." [FILE]`;
  `seccomp-setting.sh` and the new `packages-setting.sh` are thin wrappers.
  Invalid or missing `packages` falls back to `readonly`.
  `bbox` exports `SANDBOX_PKG_READONLY` and checks the created container's
  mounts through `dc-resolve.py package-access`, with seccomp's rule: a
  mismatch on a created container is an error, on a reused one a warning.
- [x] 2. The three package mounts end in
  `readonly=${localEnv:SANDBOX_PKG_READONLY:true}`, under new names:
  `venv-noble-py3.12-base`, `r-site-library-noble-4.5.3-2026-07-15-base`,
  `texlive-2026-base-noble`. `packages.sh` runs `chown -R node:node` over the
  volumes it built, even after a failed install, returning the install's status.
- [x] 3. Lean lists in `install-packages.sh`; archive and Bioconductor code
  removed. The startup sentinels (`pyfixest`, `fixest`, the TeX marker) were
  already base packages, so they are unchanged.
- [x] 4. `install-optional.sh`: refuses unless the target mounts are writable
  and writable by node, and the firewall marker says open; prints each ordinary
  command it runs; skips what is present; rechecks at the end.
  `--verify` works in any mode.
- [x] 5. `post-start.sh` prints the mode, from the live mounts, and warns when
  they differ from `SANDBOX.toml`. New `package-mode.sh` reads the mounts.
  Beyond the plan: shells print "Warning: Package Volumes Writable", like the
  open-firewall warning. Agent guidance (`SANDBOX-CLAUDE.md`, the same file as
  `SANDBOX-AGENTS.md`) describes the modes and says never change `packages`.
- [x] 6. Tests. `test-packages.sh` checks the mounts match `packages` and, when
  writable, that node owns and can write them; the parquet round trip is gone.
  New `tests/test-optional.sh`. `test-seccomp.sh` covers the packages reader
  and the devcontainer.json fallback; `test-bbox.zsh` covers export and the
  mount check.
- [x] 7. Docs: `.setup/README.md`, `.devcontainer/README.md` (new "Working
  modes" section), `docs/features.md`, root README, and a note in
  `docs/storage-needs.md` that its sizes predate the rename.

Verified here, against the current full volumes, read-only: `test-seccomp.sh`
(34), `test-bbox.zsh` (25), `.host/tests/test-setup.py`, `test-packages.sh`
PASS, `test-optional.sh` PASS, `install-optional.sh r` refuses with both
reasons, and shellcheck is clean.

## decisions

- **TeX base.** scheme-small's collections plus `collection-bibtexextra`, and
  `latexindent`, `latexmk`, `cm-super`. To find "whatever a default LyX export
  needs", a LyX document with LyX's default font encoding (T1) was exported
  with `pdflatex -recorder`, and its inputs were mapped to packages through
  `texlive.tlpdb`. Everything came from basic, latex, latexrecommended and
  bibtexextra, except `cm-super` (collection-fontsrecommended). Without it
  pdflatex falls back to bitmap EC fonts, so the builder's smoke test now uses
  T1 and fails on Type 3 fonts. TikZ left the smoke test; `test-optional.sh`
  compiles it instead.
- **Mode check reads mounts, not the file.** `SANDBOX.toml` may have been
  edited since creation; the mounts are what is true. `install-optional.sh`
  refuses on the mounts for the same reason.
- **Firewall required off for `install-optional.sh`.** PyPI, P3M,
  Bioconductor and CTAN are all outside the allowlist, so an armed run would
  only fail late.

## HOST steps

- [ ] 8a. Build the lean base under the new names:
  `bash .setup/packages.sh all`. Expect the builder's TeX smoke test to pass
  on the lean tree, and a final `chown -R node:node` line.
- [ ] 8b. `bbox --rebuild` in mode 1, then in the container:
  `bash .devcontainer/tests/test-packages.sh`. `test-optional.sh` should
  fail here (the optional set is absent), which shows the base stands alone.
- [ ] 8c. Mode 3: `packages = "writable"`, `firewall = false`,
  `bbox --rebuild`. Check the startup mode line and the shell warning. Run
  `bash .devcontainer/tests/test-packages.sh` (writable branch), then
  `bash .devcontainer/install-optional.sh`, then
  `bash .devcontainer/tests/test-optional.sh`.
- [ ] 8d. Things to check in mode 3 (0926a): `install.packages()` writes to
  the site library, not a personal one; `tlmgr install` works as node;
  note whether pip replaced any base dependency.
- [ ] 8e. Back to mode 1, `bbox --rebuild`, `test-packages.sh` once more.
  Re-measure the volumes for `docs/storage-needs.md`, then prune the old
  volumes (`venv-noble-py3.12`, `r-site-library-noble-4.5.3-2026-07-15`,
  `texlive-2026-small-noble`) when satisfied.

Untested until 8b: that the devcontainer CLI passes `readonly=false` through
to `docker run --mount` as expected (Docker accepts it; `bbox`'s mount check
will catch it if not).

## log

- 2026-09-26: container-side steps 1–7 implemented.
