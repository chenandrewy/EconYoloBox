# 0919c — flip the checked-in posture to YOLO; keep the seccomp toggle

Discussion snapshot, 2026-09-19, branch `yolo-default-posture`. Reverses the
default chosen in [0917c](0917c,bwrap-auto-review-friction.md) without
undoing the toggle machinery from [0917d](0917d,seccomp-from-sandbox-toml-plan.md).

## why

Codex's automatic review degrades noticeably in the chaperoned posture. Per
[0919b](0919b,claude-vs-codex-reviewer-speed.md) the reviewer is a full
GPT-5.4 Thinking call per escalation, and with the firewall down every network
action is an escalation (workspace-write keeps `network_access = false`), plus
the open quota-amplification bug under `on-request`. Claude's auto mode is a
two-stage classifier that skips in-project edits and is much cheaper. Codex
chaperoned was also already half-broken here: 0917c showed `apply_patch` has
no escalation path when Bubblewrap fails.

Codex outside YOLO mode also has special problems with git permissions: any
git edit (commit, checkout, branch, and the like) trips the sandbox and
escalates or fails. Worktrees make it worse simply because there is more git.
This is a big hassle and a further reason to treat Codex as YOLO-only here.

Security-wise the flip is a wash or better. Chaperoned = open network +
unconfined seccomp + an LLM reviewer between the agent and exfil. YOLO = no
egress + Docker's syscall filter + no reviewer. Egress blocking is a hard
boundary; the reviewer is a soft one. Residual YOLO risk is local destruction
of the live mount, which git and Dropbox history cover and which the
chaperoned posture never prevented for approved commands anyway.

## decision

- `SANDBOX.toml`: `firewall = true`, `seccomp = "builtin"`.
- `devcontainer.json` fallback for direct VS Code creation: `builtin`, so the
  VS Code path matches the checked-in TOML again (0917d's original fail-closed
  intent).
- Everyday: `cchat-yolo` / `gptchat-yolo`. Internet needed: `firewall = false`,
  rebuild, Claude auto mode. Codex sandboxed modes: also `unconfined`.
- The seccomp toggle stays. The user wants to keep testing Codex's sandboxed
  modes under `unconfined` before deciding whether to drop it. The Codex baked
  defaults (on-request / workspace-write) stay too; under builtin they fail at
  Bubblewrap setup, which the config comment now says.

## remaining friction

The firewall toggle still requires `bbox --rebuild` (init-firewall.sh is not
re-runnable mid-session). If switching several times a day becomes routine,
the follow-up is a runtime firewall down/up script, not reviving
Codex-chaperoned.

## not done here

No container rebuild or runtime validation in this session. After
`bbox --rebuild` on the host, expect: no `Warning: Firewall Open`, no
`Warning: Seccomp Unconfined`, `Seccomp: 2` on PID 1, and `cchat-yolo` starts.
