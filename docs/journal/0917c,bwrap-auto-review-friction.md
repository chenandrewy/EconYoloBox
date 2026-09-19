# 0917c — Bubblewrap failure still causes editing friction

Discussion snapshot, 2026-09-17. This note is limited to the Codex/Bubblewrap
problem observed with Docker's builtin seccomp profile. It supplements
[0917a](0917a,seccomp-builtin-and-codex-auto-review.md).

## observed behavior

The active container uses:

```text
--security-opt=seccomp=builtin
```

An ordinary Codex command failed before the requested command ran:

```text
bwrap: No permissions to create new namespace, likely because the kernel does
not allow non-privileged user namespaces.
```

The failure affected even routine read-only commands within the workspace. A
shell command could recover by explicitly requesting execution outside the
inner sandbox. With `approvals_reviewer = "auto_review"`, that escalation was
reviewed automatically and allowed.

The dedicated `apply_patch` file-editing helper did not recover. It attempted
to use the unavailable Bubblewrap sandbox, failed during namespace creation,
and exposed no corresponding escalation option. Running the `apply_patch`
executable through an already escalated shell still reached the same failing
sandbox helper. We therefore had to consider the system `patch` utility as a
fallback merely to make a normal workspace edit.

## why Approve for me is incomplete here

`approval_policy = "on-request"` plus
`approvals_reviewer = "auto_review"` changes who reviews eligible escalation
requests. It does not repair Bubblewrap and does not automatically make every
tool escalation-capable.

This works reasonably well for shell execution because that tool can request
escalated sandbox permissions. It does not solve failures in tools such as the
observed `apply_patch` helper when they have no escalation path. Consequently,
the current setup adds repeated failed calls and fallback logic to ordinary
repository work even though automatic review is enabled.

Setting `approval_policy = "never"` is not a fix: it suppresses approval
requests rather than automatically escalating failed sandbox operations.

## recommendation

Reconsider the September 17 decision to keep `seccomp=builtin`. The newly
observed `apply_patch` failure shows that automatic review is not a complete
operational substitute for a working inner sandbox.

For the immediate configuration, switch the devcontainer to
`seccomp=unconfined` and recreate the container, then verify as the `node` user:

```text
bwrap --unshare-user --ro-bind / / /bin/true
codex sandbox linux /bin/true
```

Also verify an ordinary workspace edit with the native `apply_patch` helper.
This is intended to restore the ordinary `workspace-write` path; success remains
unverified until container recreation and runtime checks. It disables Docker's
outer seccomp filter for every process in the container; that tradeoff must
remain explicit.

The initial recommendation proposed a custom seccomp profile as a later
hardening task. The user subsequently chose unconfined as the intended final
configuration, so a custom profile is not a planned follow-up or a condition
for merging.

## reassessment and configuration update

The user authorized the configuration and documentation update after reviewing
this report. Selected `seccomp=unconfined` in `devcontainer.json` for Bubblewrap
compatibility and updated the README, feature guide, and source comments.
The firewall setting, Codex approval settings, and YOLO firewall checks were not
changed. Earlier journal entries remain historical snapshots.

Correction to the recovery evidence: in the earlier conversation, invoking the
installed `apply_patch` helper by its absolute path through an escalated shell
succeeded, after the native tool and plain command invocation failed. Editing
was therefore not universally blocked, but the native path remained broken and
required tool-specific recovery. That friction meets the reassessment criterion
in `0917a`.

No container recreation was performed as part of this update. The live container
still reported seccomp filter mode before the edit. The guide now requires both
namespace probes and native tool checks, including allowed workspace writes,
denied writes outside writable roots, and the selected command network policy.
Do not call the fix validated until those checks pass after recreation.

The security cost applies beyond Codex: its inner sandbox does not restore the
outer filter for Claude, YOLO sessions, or approved unsandboxed commands. This
is the accepted tradeoff of the chosen configuration. Runtime validation remains
pending; that does not make the configuration provisional.
