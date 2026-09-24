# 0917a — keep builtin seccomp; reassess Codex sandboxing later

Discussion snapshot, 2026-09-17. Revisits the approach in
[0915d](0915d,codex-approve-for-me-plan.md) and
[0915e](0915e,codex-approve-for-me-implemented.md).

## decision

Keep Docker's `seccomp=builtin` for now and reassess later. It was already
selected in `.devcontainer/devcontainer.json`; this discussion did not change
the container configuration. Use Codex's "Approve for me" review for requests
to execute outside the unavailable inner sandbox, accepting the extra approval
overhead and the limits of that arrangement.

The user would like to run with the container firewall down. That is a separate
decision from seccomp: `SANDBOX.toml` still contained `firewall = true` when
inspected, and we did not change it or test unrestricted outbound access.

## evidence from this session

- Installed CLI: `codex-cli 0.154.0`. Its help includes `--approve-for-me`,
  described as routing approval requests through automatic review using the
  workspace-write sandbox.
- Container PID 1 reported `Seccomp: 2` and one seccomp filter, consistent with
  the selected Docker default policy being active.
- The first ordinary shell invocation failed before executing its command:
  `bwrap: No permissions to create new namespace`.
- The subsequent read-only invocation requested execution outside the inner
  sandbox, passed automatic review, and succeeded inside the container.

This shows that the current bubblewrap failure does not prevent all useful
work with automatic review. It does not show that bubblewrap works, that every
tool supports this fallback, or that every escalation will be approved. The
failure is consistent with the earlier namespace investigation; this session
did not separately isolate every possible kernel or security-policy cause.

## three separate controls

Docker and its seccomp policy provide the outer process boundary and syscall
restrictions. Codex's bubblewrap sandbox supplies additional filesystem and
network restrictions inside that container. "Approve for me" changes who
reviews requests to cross the inner boundary: a separate reviewer agent takes
the place of a human for eligible requests.

Automatic review does not itself disable bubblewrap or grant unrestricted
network access. An approved command executed outside the inner sandbox still
runs under Docker's restrictions, but no longer has that command sandbox's
filesystem and network limits.

The older entries equated `on-request` plus `workspace-write` with automatic
review. That is incomplete: the approval policy and sandbox mode alone do not
select the reviewer. Current documentation additionally specifies
`approvals_reviewer = "auto_review"`; the actual `--approve-for-me` flag is
available in the installed CLI. We did not update the launchers or defaults.

## clarification about networking

Bubblewrap does not inherently disable networking. Its `--unshare-net` option
creates a separate network namespace without ordinary external connectivity;
it can also preserve networking while restricting filesystem access.

Codex's default workspace-write policy disables command networking, but allows
it to be enabled independently:

```toml
[sandbox_workspace_write]
network_access = true
```

That setting does not necessarily resolve the namespace-creation failure:
bubblewrap also needs namespaces for filesystem isolation. Conversely, lowering
the container firewall does not by itself enable networking inside a working
Codex sandbox whose policy keeps it off.

With the firewall down, a command approved to run outside the inner sandbox
would have the container's network access. Docker seccomp would still apply.
We corrected the earlier wording that made bubblewrap sound inherently offline.

## accepted limits and reassessment

The container contains live host files under `/workspace`, mounted credentials,
and persistent authentication volumes. Processes with access to those resources
can affect them without escaping Docker. With outbound networking available,
accessible data can also leave the container.

Automatic review is designed to reject unauthorized disclosure, credential
theft, and dangerous destructive actions. It is not an OS-level check on every
operation performed by an approved script or its subprocesses. The chosen
posture is a convenience tradeoff, not equivalent to a working inner sandbox
plus restricted networking.

Reassess when Codex or Docker changes make the inner sandbox compatible with
the default seccomp policy, or when repeated failures and escalations become
disruptive. Do not relax Docker's outer filter merely to eliminate those
failures without reconsidering the tradeoff.

Documentation follow-up: replace claims that builtin seccomp "blocks Approve
for me" with the narrower observation that it currently blocks bubblewrap setup
here, while approved execution outside the inner sandbox has worked. This entry
records that correction; existing configuration comments and guides remain
unchanged.

Follow-up later in the same chat: updated the active READMEs, `docs/features.md`,
and source configuration comments to reflect this decision, distinguish the
reviewer from approval policy, and clarify networking. Runtime settings and
launcher commands were not changed. Earlier journal entries remain historical
snapshots.

Further simplification: removed the `gptchat` and `gptmini` shell wrappers.
Standard `codex` is now the documented everyday entry point, with model choice
through `/model` or `--model`. The docs recommend
`approvals_reviewer = "auto_review"` as a user preference and show the full
on-request/workspace-write configuration. No user config was rewritten; the
explicit YOLO wrappers retain their firewall checks.

## sources consulted

- [OpenAI: Auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review)
- [OpenAI: Sandboxing](https://learn.chatgpt.com/docs/sandboxing)
- [OpenAI: Agent approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security)
- Local CLI help, container configuration, and runtime evidence described above.
