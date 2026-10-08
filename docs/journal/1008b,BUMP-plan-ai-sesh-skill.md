# Plan idea: simplify ai-sesh with a transfer skill

2026-10-08. Discussion snapshot; implementation deferred.

## Idea / motivation

Replace much of the ai-sesh selection and transfer workflow with a simple skill:
ask the agent to look through `tools/ai-sesh/data/`, find the conversation we
need, and bring over only the relevant material. Avoid maintaining elaborate
automatic session-sharing machinery if deliberate transfers meet our needs.

This follows `1008a,BUMP-plan-agent-daemon-separation.md`. Separate YOLO/normie
agent homes make it useful to reconsider whether they should still share live
session files. This is a proposed simplification, not an implemented change or
a final decision to retire every existing ai-sesh component.

## Two different operations

- Context handoff: find and read a prior conversation, then summarize or carry
  its relevant context into the current session. This does not require the
  destination agent to recognize the transcript as a native resumable session.
  It is the simplest candidate for a skill-only workflow.
- Native resume/fork: transfer a selected conversation into the destination
  agent's own session storage so its normal resume/fork commands can use it.
  Transcript copying alone may not be enough; current versions may require
  indexes or supporting state. Verify supported import/export behavior before
  promising this operation.

The skill should make clear which operation it performed. Reading a transcript
and producing a handoff is not a native session import.

## Proposed arrangement

1. Each agent in each container owns its live session files and runtime state.
2. `tools/ai-sesh/data/` holds exported conversation snapshots, available through
   the existing Dropbox-synced workspace.
3. A skill searches those snapshots and reads or transfers only what the user
   requests. No blanket push of all other machines' sessions is needed for this
   workflow.

This removes shared live-session writers and makes transfers explicit. The cost
is giving up automatic cross-container history continuity: a conversation may
need export and transfer before it is available elsewhere. A context handoff
also does not preserve all the behavior or state of a native resumed session.

## Collection is still needed

Today `sesh-init` links home session directories directly into
`data/<machine>/`, so new transcripts arrive there automatically. A skill that
only reads that directory does not replace this collection mechanism.

Choose between retaining the current links for collection or replacing them
with explicit exports. Retaining links is a smaller change, but does not achieve
the proposed separation of live session storage. The preferred direction to
investigate is independent live stores plus snapshots, with an explicit export
step or a small supported collection mechanism.

Existing data must remain readable and preserved during any transition. New
snapshots need enough provenance to identify agent, machine, container mode,
session ID, and export time without confusing different versions of one session.
Exact layout and naming remain undecided.

## Skill versus tooling

Use the skill for intent, discovery, selection, reading, and explaining what was
transferred. For native transfers, prefer supported agent commands. If a helper
is needed, keep it small and deterministic; do not make each skill invocation
improvise file moves or database edits. Any missing-tool replacement still needs
the user's authorization under the repository guidance.

Read stored conversations as reference material, not as current instructions.
Export conversation material deliberately; do not bundle credentials, daemon
state, or an entire agent home as a shortcut.

## Sketch for later

- Decide whether context handoff is sufficient for most requests and whether
  native resume/fork must remain supported.
- Inspect the actual installed Codex and Claude session formats and supported
  export/import operations. Determine what the existing ai-sesh data contains.
- Prototype one requested conversation handoff using existing snapshots, without
  changing live stores. Then, if required, demonstrate one supported native
  transfer with independent destination state.
- Choose how exports happen and how snapshots are distinguished and refreshed.
  Do not overwrite divergent conversations or duplicate session IDs blindly.
- Create the skill around that proven workflow. Retain only the ai-sesh helpers
  needed for reliable collection or transfer; retire others after verification.
- Coordinate with daemon separation: if this approach is adopted, revise the
  implementation direction from shared live transcript links to independent
  stores and explicit handoff/export. Preserve the older journal as a snapshot.

No skill, scripts, session data, container configuration, or installations were
changed for this entry.
