# Codex fork rejects the ai-sesh sessions symlink

Date: 2026-08-31 (NY)

Investigation started because `setup-read-paper.sh` appeared to have stopped
working for Codex. The setup script is not the failing part: it still creates
a seed session, the seed reads the entire paper, the session JSONL is written,
and `gpt-paper.sh` is updated with the new session id. The failure happens
later, when `gpt-paper.sh` asks current Codex to fork that seed.

## The ai-sesh arrangement

`sesh-init`, which is run automatically from the shell setup whenever a new
configured zsh shell starts, establishes and maintains this link:

```text
~/.codex/sessions
  -> /workspace/.tools/ai-sesh/data/<machine>/codex
```

It performs the actual replacement on initial setup, or if the expected link
has been removed or changed. Opening later terminals ordinarily just verifies
and enforces the existing link. `sesh-push` does not create the link; it copies
other machines' sessions into the already-linked local store.

This link is intentional and central to ai-sesh. Codex writes session bytes
directly into the Dropbox-backed tree, so sessions survive container rebuilds
and travel between machines without a save/export step.

## What current Codex rejects

The apparent rollout path is under Codex home:

```text
/home/node/.codex/sessions/2026/08/31/rollout-....jsonl
```

Following the link puts the physical file here:

```text
/workspace/.tools/ai-sesh/data/macbook25/codex/2026/08/31/rollout-....jsonl
```

Codex 0.151.0's fork path resolves the rollout and checks that it remains
inside the physical Codex home, `/home/node/.codex`. The resolved file is
outside that tree, so fork preparation rejects it:

```text
thread/fork failed: rollout path `...` must be in Codex home directory
```

This is not missing or corrupt session data. Codex can create the session,
write it through the link, discover its id, and project its paginated history.
The incompatibility is specifically between a sessions directory whose link
target is outside `CODEX_HOME` and the newer containment check used during
fork lifecycle handling.

The check appears intended to prevent Codex from treating arbitrary files
outside its managed store as rollouts. The problematic detail for ai-sesh is
that it checks containment against the physical Codex home rather than
accepting a rollout contained within the canonical target of the configured
`~/.codex/sessions` directory.

## Why the failure was misleading

The noninteractive form exposes the real error:

```bash
codex exec fork <seed-id> ...
```

The interactive `codex fork <seed-id>` used by `gpt-paper.sh` opened a new TUI
conversation, but that conversation did not inherit the seed history. It
therefore looked like a successful fork while behaving like a fresh thread.

The investigation itself supplied a useful check. The seed was
`01a05831-d093-7c92-9c88-b30ac9515dd0`, created by Codex 0.150.1. Its final
paper-reading request contained 33,091 input tokens. The supposed fork was
created by Codex 0.151.0, and its first request contained only 14,030 input
tokens. Its projected history began with the request to investigate
`setup-read-paper.sh`, not with the paper-reading seed. Thus the paper context
was not inherited.

## Scope

`sesh-init` is not completely broken:

- Claude's symlinked stores are not implicated by this Codex error.
- Codex still creates and writes sessions into the synced store.
- Passive Dropbox persistence still works.
- Codex `fork` is confirmed broken for these rollouts.

`resume`, `archive`, `delete`, and migration were not tested end to end. Some
current Codex lifecycle code uses related path-containment checks, so their
status should not be inferred from creation and writing continuing to work.

## Current direction

Do not redesign ai-sesh around explicit session export or manual copying. Its
purpose is the convenience of a live, passively synced store, and replacing
that with a save step would discard the main design goal recorded in
`archive/0708T08-ai-sesh-redesign.md`.

The preferred direction is a minor Codex compatibility patch: preserve the
containment protection while allowing a deliberately symlinked sessions root,
most naturally by validating a rollout against the canonical target of
`~/.codex/sessions`. No patch has yet been implemented, and the exact upstream
code path and regression boundary still need to be isolated before editing.
