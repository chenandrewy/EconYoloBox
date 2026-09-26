# 0926b — implementation: YOLO and normie modes, lean base, optional set

Working checklist, 2026-09-26, branch `feature/package-install-modes`.
Implements [0926a](0926a,package-install-modes-plan.md); read it first. Where
they differ, this file wins: the three modes of 0926a became two (see
[decisions](#decisions)). Container-side work is done, including the doc pass
in step 7b. What is left runs on the host (**HOST**): the container has no
Docker socket, so nothing here has been built or rebuilt yet.

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
- [x] 5. `post-start.sh` prints the posture: `YOLO mode`, `Normie mode`, or
  `Custom posture` (to stderr), each with `internet=… packages=… seccomp=…`.
  `internet` is as armed; `packages` comes from the live mounts (new
  `package-mode.sh`) and `seccomp` from PID 1, since both are fixed at
  creation. It still warns when the mounts differ from `SANDBOX.toml`.
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
- [x] 7b. Doc pass for two modes. Still written for 0926a's three modes, or
  with "chaperoned": `.devcontainer/README.md` "Working modes",
  `docs/features.md` "Three working modes", the root README's feature list,
  `.setup/README.md` setup steps, the agent guidance's numbered modes, and
  `install-optional.sh`'s closing hint. Say YOLO is the default and normie is
  supervised.

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
- **Two modes, not three** (after the first commit). `SANDBOX.toml` names two
  presets: YOLO mode (`internet = "firewalled"`, `packages = "readonly"`,
  `seccomp = "builtin"`), the default, and normie mode (`"open"`,
  `"writable"`, `"unconfined"`), meant to feel like ordinary work on the Mac,
  with the user watching and agents in approval modes. 0926a's mode 2 (open
  internet, read-only packages) is dropped as a named mode: it guarded against
  an agent changing the shared volumes during supervised web work, which is not
  worth a third preset. The three keys stay independent, per 0923b; other
  combinations still work and are reported as custom.
- **Normie mode includes `seccomp = "unconfined"`.** In approval modes Codex
  runs commands in its Bubblewrap sandbox, which fails under builtin seccomp
  (0915b, 0917c), so normie mode would not work for Codex without it. It also
  matches the Mac, which has no Docker syscall filter. The unconfined route was
  never fully validated (0923b), so step 8d now tests it.
- **Setting renamed.** `firewall = true | false` became
  `internet = "firewalled" | "open"` (commit `313834d`); anything but `"open"`
  arms.
- **Firewall required off for `install-optional.sh`.** PyPI, P3M,
  Bioconductor and CTAN are all outside the allowlist, so an armed run would
  only fail late.

## HOST steps

- [x] 8a. Build the lean base under the new names:
  `bash .setup/packages.sh all`. Expect the builder's TeX smoke test to pass
  on the lean tree, and a final `chown -R node:node` line.
- [x] 8b. YOLO mode, `bbox --rebuild`. Check the startup line reads
  `YOLO mode`, then in the container:
  `bash .devcontainer/tests/test-packages.sh`. `test-optional.sh` should
  fail here (the optional set is absent), which shows the base stands alone.
- [x] 8c. Normie mode (the preset in `SANDBOX.toml`), `bbox --rebuild`. Check
  the startup line reads `Normie mode` and shells warn about writable volumes
  and the open firewall. Run `bash .devcontainer/tests/test-packages.sh`
  (writable branch), then `bash .devcontainer/install-optional.sh`, then
  `bash .devcontainer/tests/test-optional.sh`. Also check, from 0926a:
  `install.packages()` writes to the site library, not a personal one;
  `tlmgr install` works as node; note whether pip replaced any base
  dependency.
- [x] 8d. Still in normie mode, validate Codex's sandbox under unconfined
  seccomp (0923b's follow-up): Bubblewrap starts, native editing works,
  workspace writes are allowed, writes outside it are denied, and the chosen
  command-network policy behaves.
- [ ] 8e. Back to YOLO mode, `bbox --rebuild`, `test-packages.sh` once more.
  Re-measure the volumes for `docs/storage-needs.md`, then prune the old
  volumes (`venv-noble-py3.12`, `r-site-library-noble-4.5.3-2026-07-15`,
  `texlive-2026-small-noble`) when satisfied.

Untested until 8c: that the devcontainer CLI passes `readonly=false` through
to `docker run --mount` as expected (Docker accepts it; `bbox`'s mount check
will catch it if not).

## log

- 2026-09-26: container-side steps 1–7 implemented.
- 2026-09-26: `firewall` renamed to `internet` (`313834d`); `SANDBOX.toml`
  rewritten around two presets, YOLO and normie. `post-start.sh` now names
  the posture; docs still to follow (7b).
- 2026-09-26: 7b doc pass. The root README, `.devcontainer/README.md`,
  `docs/features.md`, `.setup/README.md`, the agent guidance and
  `install-optional.sh`'s messages now describe YOLO and normie mode, with all
  three keys; "chaperoned", "mode 3" and "install mode" are gone.
