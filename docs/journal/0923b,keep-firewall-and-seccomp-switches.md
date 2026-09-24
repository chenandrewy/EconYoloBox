# 0923b — keep separate firewall and seccomp switches

Discussion snapshot, 2026-09-23, branch `yolo-default-posture`. This follows
[0919c](0919c,yolo-default-posture.md). The decision is to keep the current
two settings for the merge: `firewall = true` and `seccomp = "builtin"` remain
the checked-in YOLO posture, while each can still be changed explicitly in
`SANDBOX.toml`. Do not replace them with a single `yolo` boolean.

## Why keep the seccomp switch

The user often prefers Codex, including for work that needs substantial
internet access. Host Codex is an alternative, but it has separate user
configuration, skills, credentials, CLI installation, and tools. The container
seeds guidance and skills from `.devcontainer/agents/`, bakes in Codex defaults
and app/plugin restrictions, and persists its own `~/.codex` volume. Moving
internet work to the host would introduce another agent setup to remember and
maintain. Keeping the switch preserves a route to use Codex in the familiar
container with the firewall open and its inner sandbox requested.

That route has a cost: `seccomp = "unconfined"` removes Docker's outer syscall
filter from every container process, including unsandboxed agents, and requires
container recreation through `bbox --rebuild`. The user accepts keeping this
as an explicit option, not as the default. The firewall is independent:
`firewall = false` opens container egress at the next container start, while
Codex's workspace-write sandbox has its own command-network policy. Opening
the firewall alone does not turn on sandboxed command networking. Leaving that
policy off can cause repeated network escalations and auto-review overhead;
enabling it changes what sandboxed commands may access. Neither TOML setting
selects an agent's approval mode.

## What the Bubblewrap record establishes

- [0915b](0915b,codex-nested-sandbox-runtime-evidence.md) reproduced namespace
  failures under Docker's builtin seccomp: `unshare`, plain Bubblewrap, and
  `codex sandbox linux /bin/true` all failed before useful work. The active
  filter was the strongly supported cause, but the exact denied syscall was
  not isolated.
- [0917a](0917a,seccomp-builtin-and-codex-auto-review.md) found that a
  read-only shell command could succeed after automatic review allowed it
  outside the inner sandbox. Auto-review did not make Bubblewrap work.
- [0917c](0917c,bwrap-auto-review-friction.md) found that the native
  `apply_patch` tool failed at Bubblewrap setup and lacked an escalation path.
  Invoking the installed helper by absolute path through an escalated shell
  eventually worked, so editing was possible but required tool-specific
  recovery.
- [0919a](0919a,workspace-rename-validation.md) recorded a rebuilt container
  with unconfined seccomp, but did not record successful Bubblewrap, native
  editing, filesystem-denial, or command-network tests. The unconfined path
  remains an available compatibility option, not a fully validated fix.

## Why keep two explicit settings

The controls answer different questions. The firewall bounds container egress;
Docker seccomp filters syscalls. A `yolo` boolean would imply that it chooses
agent approval behavior, which these settings do not do, and would hide the
option of opening the firewall while retaining builtin seccomp. The TOML
comments were shortened and corrected in commit `9ebabee`, with `firewall`
above `seccomp`; the values were unchanged.

## Follow-up when using the open-internet Codex posture

Recreate with `firewall = false` and `seccomp = "unconfined"`, then validate
Bubblewrap and ordinary Codex workspace-write behavior as described in
[the container guide](../../.devcontainer/README.md#codex-sandbox-modes-and-launchers).
Check native editing, allowed workspace writes, denied outside writes, and
the chosen command-network policy before calling the compatibility path
working. No rebuild or runtime probe was performed in this discussion.
