# 0915e — implemented: Codex "approve for me" in the container

Snapshot. Implements the plan in [0915d](0915d,codex-approve-for-me-plan.md).
Host-side edits only; container NOT yet rebuilt, so nothing verified at runtime.

## what changed
- `.devcontainer/devcontainer.json` — added `--security-opt=seccomp=unconfined`
  to runArgs (the bwrap unblock). Long comment explains why + the accepted cost.
- `.devcontainer/agents/SANDBOX-codex-config.toml` — added top-level
  `approval_policy="on-request"` + `sandbox_mode="workspace-write"` (before the
  [tui] table). Bakes to /etc/codex/config.toml → bare `codex` is now
  approve-for-me instead of the read-only default.
- `.devcontainer/shellrc.sh` — added non-yolo `gptchat` / `gptmini` launchers
  that set the mode via `-c` overrides (version-stable; avoids the newer
  `--approve-for-me`/`--not-so-yolo` flags that may postdate 0.154.0).
- `.devcontainer/README.md` — new "Codex sandbox modes and launchers" section.

## design decisions made during impl
- Put stable defaults in SANDBOX-codex-config.toml (/etc/codex), NOT a post-start
  seed of the volatile ~/.codex/config.toml. README already designates the former
  as the home for stable defaults; user config still overrides. (Reverted an
  initial post-start seed attempt.)
- Aliases use `-c` overrides, not `--approve-for-me`: same expansion
  (approval_policy=on-request, sandbox_mode=workspace-write), works on 0.154.0.
- seccomp ONLY, no caps yet. bwrap --unshare-user should not need SYS_ADMIN
  (bwrap.rs:282). Caps are the documented fallback if a probe still fails.
- Did NOT fold in the YOLO firewall-gate (0915a) — kept the plan tight, as agreed.

## STILL TO DO — needs a container rebuild (user action in VS Code)
Rebuild Container, then verify (step 2 + acceptance from 0915d):
1. bwrap probes as node, expect exit 0:
   - `unshare --user --map-root-user /bin/true`
   - `bwrap --unshare-user --ro-bind / / /bin/true`
   - `codex sandbox linux /bin/true`
   If any still fail: add --cap-add=SYS_ADMIN,SYS_CHROOT,SETUID,SETGID, rebuild, retry.
2. ordinary `gptchat`: writes under /workspace OK, denied outside; curl blocked
   mid-command (network off).
3. `gptchat-yolo` still works.
4. `test-firewall.sh` behavior unchanged.

## watch out
- devcontainer.json is JSONC (comments) — normal for this repo, VS Code is fine,
  strict JSON parsers will choke.
- seccomp=unconfined weakens the outer syscall filter for ALL processes incl.
  yolo. Accepted tradeoff, documented in README + 0915d.
