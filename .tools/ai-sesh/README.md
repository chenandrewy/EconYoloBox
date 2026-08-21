# ai-sesh

Machine-to-machine session sync for Claude Code and Codex, built on the
Dropbox-synced `/workspace`. Each machine's live home stores are symlinks
into a per-machine folder here, so this machine's sessions sync passively;
`sesh-push` installs the *other* machines' sessions when you switch desks.

## Mechanism

`sesh-init` (auto-run by `.devcontainer/shellrc.sh` on every shell) keeps
these links in place:

- `~/.claude/projects` -> `data/<machine>/claude`
- `~/.codex/sessions` -> `data/<machine>/codex`
- `~/.claude/todos` -> `data/<machine>/todos`

Claude and Codex therefore write real bytes into the synced tree; the data
survives container rebuilds because it lives in the `/workspace` mount. The
machine id derives from the host name the devcontainer injects
(`write-local-env.sh` -> `LOCAL_HOSTNAME`, e.g. `Mac-Studio.local` ->
`mac-studio`); set `AI_SESH_MACHINE` to override. Credentials, caches, and
`history.jsonl` stay machine-local. History beyond ~30 days is not a goal:
the agents' own purges self-trim each store.

## Layout

```
data/
└── <machine>/
    ├── claude/<project-key>/<uuid>.jsonl   # <- ~/.claude/projects
    ├── codex/YYYY/MM/DD/rollout-*.jsonl    # <- ~/.codex/sessions
    └── todos/                              # <- ~/.claude/todos
```

`data/` is git-ignored — Dropbox is the transport, not git.

## Commands

This directory is on `PATH` (via `/workspace/.devcontainer/shellrc.sh`), so
the filenames are the commands:

- `sesh-init`: idempotent symlink setup/migration; auto-run per shell. It
  defers migrating a store that a live session has open — exit sessions and
  rerun if it says so.
- `sesh-push`: install every other machine's sessions into the home stores.
- `cc-fork`: list other machines' Claude seeds for the current project
  (run from the project dir) and fork one.
- `gpt-fork`: same for Codex (global, newest first).
- `sesh-wipe`: manual reset — list stores, delete quarantined `*.divergent-*`
  copies, or delete a whole machine's store (typed confirmation; the
  deletion propagates to that machine via Dropbox).

Own-machine sessions never need installing: resume with `claude --resume` /
`codex resume`, fork with `claude --resume ID --fork-session` /
`codex fork ID`.

## Install ladder

Every cross-machine install (`sesh-push` and the forks) decides per file,
never as a blind copy and never from mtime:

1. Same id + same size -> skip.
2. One file a byte-prefix of the other -> take the longer (fast-forward;
   this is what normal sequential resume produces).
3. Neither a prefix -> true divergence: keep both — the incoming copy is
   quarantined as `<name>.jsonl.divergent-<machine>` (ignored by the agents'
   session scans) — and warn. Never silently discard.

## Operating rule

Switching desks: **exit sessions on the machine you're leaving -> let
Dropbox settle -> `sesh-push` and resume on the other.** Never run the same
session live on both machines at once. Claude appends to the jsonl live,
not just on exit, so exiting first stops the file moving under Dropbox.
Divergence only arises from breaking this rule (concurrent use, or resuming
before Dropbox pulled the latest); the prefix check is the safety net.
