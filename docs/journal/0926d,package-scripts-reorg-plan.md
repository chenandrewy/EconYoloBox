# 0926d — plan: reorganize the package scripts under .setup/

2026-09-26, branch `feature/package-install-modes`. Follows
[0926b](0926b,package-install-modes-implementation.md). Implemented the same day; see [log](#log).

## why

The folders were split by where a script runs: `.host/` and `.setup/` on the
Mac, `.devcontainer/` in the container. The package workflow spans both, so it
got scattered: `.setup/packages.sh` (host driver), `.devcontainer/install-packages.sh`
(base lists + installer, plus the AI CLI installer), and
`.devcontainer/install-optional.sh` (optional set, run by hand in normie mode).
Nothing in the container's definition or lifecycle uses either installer;
`packages.sh` just bind-mounts `.devcontainer/` to reach one. The CLIs are
always installed, so they are base, not a separate job.

## folder rule

- `.devcontainer/` — the container: definition, startup, tools baked into
  the image. Everything here is referenced by devcontainer.json, the
  Dockerfile or post-start.sh, or ships in the image.
- `.host/` — the launcher: `bbox` and its installer `setup.sh`.
- `.setup/` — provisioning run by hand, on the host or in the container.
  Each script's header says where it runs.

## end state of .setup/

| File | Contents |
|---|---|
| `README.md` | the whole package and CLI story |
| `install-base.sh` | base lists and installer: python, r, tex, cli |
| `install-optional.sh` | optional set, normie mode, as now |

Two scripts because there are two lists with different policies: the base is
always present, host-built, and the sandbox's own tools depend on it; the
optional set is the user's choice, installed while watching, and nothing
depends on it.

## steps

- [x] 1. `install-base.sh` merges `.setup/packages.sh` and
  `.devcontainer/install-packages.sh`; both old files are removed.
- [x] 2. On the host it finds this checkout's devcontainer (as `packages.sh`
  does now), takes its image, and mounts the three shared package volumes plus
  the per-checkout npm-global volume, whose name comes from the container's
  mounts (target `/usr/local/share/npm-global`). It runs itself as root in a
  throwaway container with `.setup/` mounted at `/setup`, then
  `chown -R node:node` over the volumes, even after a failed install,
  returning the install's status.
- [x] 3. In a container, detected positively via `/.dockerenv`, it installs.
  `python`, `r`, `tex` require writable volume mounts; read-only refuses and
  points to the host command. `cli` requires the npm-global mount, so CLI
  updates still work from inside the devcontainer in any mode. No install
  target may run on the Mac: the context check plus the mount checks
  (`mountpoint` is absent on macOS, so that fails safe).
- [x] 4. `all` and no arguments both mean python, r, tex, cli. First setup is
  one command. Inside the devcontainer, the useful call is `cli`.
- [x] 5. `--force` and `--verify` keep their meaning (`--force` not with tex;
  `--verify` works anywhere and never writes).
- [x] 6. The file stays parseable by macOS `/bin/bash` 3.2. The only bash-4
  feature now is `mapfile`, a command in the container branch, which is fine.
- [x] 7. `install-optional.sh` moves from `.devcontainer/` to `.setup/`,
  unchanged except paths and messages.
- [x] 8. Stays in `.devcontainer/`: `tests/test-packages.sh` and
  `tests/test-optional.sh` (they check what the container sees; paths
  updated), and everything else there (baked, startup, or triggered by
  devcontainer.json).
- [x] 9. Update references: root README; `.devcontainer/`, `.setup/`,
  `.host/` READMEs; `docs/features.md`; agent guidance
  (`SANDBOX-CLAUDE.md` = `SANDBOX-AGENTS.md`); `shellrc.sh`'s missing-CLI
  note; `post-start.sh`'s hint; `test-agent-policy.sh`'s messages; Dockerfile
  and devcontainer.json comments. Journals keep the old paths.
- [x] 10. `.setup/README.md` and `.host/README.md` state the folder rule.

## checks

- [ ] 11. In the container: `test-packages.sh`, `test-optional.sh`,
  `test-seccomp.sh`, `test-agent-policy.sh`, shellcheck;
  `install-base.sh python` refuses on read-only mounts;
  `install-base.sh cli` runs.
- [x] 12. On the host: `bash -n` under `/bin/bash` 3.2;
  `install-base.sh --verify` through the builder; a full `install-base.sh`
  run fills the volumes, CLIs included; `test-bbox.zsh`, `test-setup.py`.

## not in this plan

- A stale-`bbox` guard. A terminal sourced before `3c2fc2e` (13:42 today)
  keeps the old `bbox`, which passes `SANDBOX_SECCOMP` but not
  `SANDBOX_PKG_READONLY`, so `packages = "writable"` silently came up
  read-only on the 17:43 rebuild. Idea: `devcontainer.zsh` records its mtime
  when sourced, and `bbox` refuses when the file has changed since. Pending
  a yes.

## log

- 2026-09-26: implemented. `git mv` kept history for both scripts;
  `.setup/packages.sh` removed. The `// packages.sh:` staging directive in
  devcontainer.json is now `// install-base.sh:` (dc-resolve.py). `cli` in a
  container requires its mount like the others. Host `--verify` mounts the
  volumes read-only and skips the chown.
- Checks: `/bin/bash -n` (3.2) clean; host `--verify` and a full host run
  through the builder pass (CLIs installed as root, then chowned to node,
  `claude`/`codex` run); in the container `test-optional.sh`,
  `test-seccomp.sh` (34), `test-agent-policy.sh`, shellcheck, and
  `install-base.sh cli` pass; `test-bbox.zsh` (25) and `test-setup.py` pass.
- Not checked: `test-packages.sh` and the read-only refusal. The container
  was still in normie mode (writable mounts) while SANDBOX.toml said
  `readonly`, so the test stopped at the mode mismatch, and `install-base.sh
  python` ran (all satisfied, no change) instead of refusing. Rerun both after
  `bbox --rebuild` in YOLO mode.
- npm now warns that claude-code's `postinstall` is not in `allowScripts`,
  from the host builder and from inside alike, so not from this change. The
  CLI still runs.
