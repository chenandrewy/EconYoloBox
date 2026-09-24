# 0919a — workspace rename: rebuilt, validation snapshot

Snapshot, 2026-09-19. Follows `0918a,BUMP-workspace-rename.md`.
Branch `sandbox-workspace-rename`, one commit (`d84652d`) ahead of `main`.

## done

- Steps 1–3 of the plan landed in `d84652d`; move manifest in
  `0918a,move-manifest.txt` (12 entries), all present under `workspace/`.
- Step 4: container rebuilt. Running container starts at `/sandbox`;
  `/workspace` no longer exists inside it.
- `bbe` confirmed working at the sandbox root (manual).

## checked today

Host:

- `zsh .host/tests/test-bbox.zsh` — 18/18 ok.
- `python .host/tests/test-setup.py` — ok.
- `dc-resolve.py remote-path` gives `/sandbox` for root and
  `/sandbox/workspace/Live,Post-hoc` for a nested project, with no
  layout-specific code change (as the plan predicted).
- Ignore boundary: a throwaway `workspace/zzz-ignore-probe/x` was ignored by
  `.gitignore:9:/workspace/`; `git status` stayed clean. Probe removed.
- Moved projects keep their git state: `Live,Post-hoc` (branch `slides/umd`,
  origin intact), `Live,Risk-vs` (`main`), `Live_AIWorkFlow` (`main`).

In container (`docker exec` on the running container):

- `.tools` on `PATH` (4 `/sandbox/.tools/...` entries).
- `R_PROFILE_USER=/sandbox/.devcontainer/home/Rprofile`, file present.
- `check-seccomp.sh` runs; reports Unconfined + firewall open (that is the
  current `SANDBOX.toml` posture, not a regression).
- `test-agent-policy.sh` — PASS, connectors disabled for Claude and Codex.
- `check-yolo-boundaries.sh` refuses because firewall is open — expected.
- `.tools/ai-sesh/_common.sh` has `workspace_root="/sandbox/workspace"`.
- `SANDBOX-CLAUDE.md` has no stale `/workspace` references.
- `/sandbox/workspace/dev/screenshots/` resolves and has content.

## not yet checked

- `bbe workspace/<project>` and `bbcode workspace/<project>` (interactive).
- `postStartCommand` output from the rebuild (not captured here).
- New Claude / Codex session from a moved project records the new cwd;
  `cc-fork` recognizes the project root.
- Status line and TeX helpers under the new paths.

## loose ends

- Three empty directory skeletons still sit at the sandbox root:
  `Live,Post-hoc/`, `Live,Risk-vs/`, `Live_AIWorkFlow/` (zero files, nested
  empty subdirs like `.worktrees/`, `Slides/`). Dropbox residue from the move.
  No longer ignored by any rule, so they will surface in `git status` if
  anything lands in them. Delete them.
- Odd: the ignore-probe dir survived the first `rm -rf` and reappeared in the
  container listing; second `rm -rf` plus a 2 s wait removed it on both sides.
  Probably Dropbox re-sync lag. Worth remembering when deleting the leftover
  skeletons above.
- Step 6 (host references: machine-settings repo, Finder favorites, LyX
  recents, remote-control/session helpers) not started.
- Branch not merged to `main`.
