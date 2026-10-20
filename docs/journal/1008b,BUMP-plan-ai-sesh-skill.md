# ai-sesh: one shared session store, links only

2026-10-08 discussion snapshot (a transfer skill); revised and implemented
2026-10-11 as something much simpler. The filename keeps the original topic.

## Decision

Drop machine ids from ai-sesh. Every Claude and Codex install (two Macs x
YOLO/normie, each with its own home volume since 1008a) links its session
store to the same Dropbox-synced folder:

```
~/.claude/projects -> tools/ai-sesh/data/claude
~/.codex/sessions  -> tools/ai-sesh/data/codex
```

`ai-sesh-init` (every interactive shell) is the only remaining script. Deleted:
`sesh-push`, `gpt-fork`, `sesh-wipe`, `_common.sh`, the `~/.claude/todos`
link (Claude no longer writes there; every `todos/` folder was empty), and
`AI_SESH_MACHINE` in both devcontainer configs.

## Why

- Mode separation (1008a) did not need more folders: YOLO and normie on one
  Mac already shared `data/<machine>/`, since the id came from the host.
- With one shared folder, a session exited anywhere is in every install's
  `projects/` once Dropbox syncs; `claude --resume` finds it with no copy
  step, and paths (`/yolobox/...`) match, so project keys match.
- The per-machine split existed so each file had one writing machine and
  `sesh-push` could catch a stale resume with its size/prefix ladder. With a
  shared folder the same slip makes Dropbox keep both versions as a
  "conflicted copy" (per its documentation; not tested here). Both keep
  both versions. The split cost a `sesh-push` at every desk switch,
  duplicate copies of every pushed session, and the Codex picker issue in
  1005a.
- Considered and dropped along the way: a skill that pulls one session at a
  time (`sesh-pull`); a `sesh-find` search helper plus skill; a one-time
  `sesh-migrate` merging the old stores; a per-shell warning about
  conflicted copies. With one store nothing needs pulling, `--resume`
  already lists everything, and the old transcripts are not worth merging.
  The 10-08 alternative (independent stores plus exported snapshots) would
  have needed an export mechanism and given up native resume across Macs.

## Behavior and limits

- **Old stores are left in place.** `data/<machine>/` folders stop growing
  and are no longer purged by the agents; delete them by hand when unwanted.
  Sessions in them are not resumable by the agents' pickers (read them as
  files).
- **Cutover.** `ai-sesh-init` repoints an install's link in the first
  interactive shell after this change. A session still running there then
  continues in the new folder and its transcript is split. Exit agent
  sessions in each install before opening a new shell.
- **Codex picker.** Each install's `state_5.sqlite` indexes only what it has
  seen; sessions written elsewhere may be missing from the default (cwd)
  picker. `codex resume <id>` and `--all` read-repair them (1005a).
- **Purges are global.** Any install's ~30-day cleanup trims the shared
  store for all. Fine: history beyond 30 days was never a goal.
- **Operating rule unchanged:** exit, let Dropbox settle, resume elsewhere;
  never one session live in two places.
