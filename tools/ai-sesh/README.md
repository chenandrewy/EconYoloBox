# ai-sesh

Machine-to-machine session sync for Claude Code and Codex, built on the
Dropbox-synced `/yolobox` mount. Each machine's live home stores are symlinks
into a per-machine folder here, so this machine's sessions sync passively;
`sesh-push` installs the *other* machines' sessions when you switch desks.
Design notes: `docs/journal/0708T08-ai-sesh-redesign.md`.

## Mechanism

`sesh-init` (auto-run by `.devcontainer/shellrc.sh` on every shell) keeps
these links in place:

- `~/.claude/projects` -> `data/<machine>/claude`
- `~/.codex/sessions` -> `data/<machine>/codex`
- `~/.claude/todos` -> `data/<machine>/todos`

Claude and Codex therefore write real bytes into the synced tree; the data
survives container rebuilds because it lives in the `/yolobox` mount. The
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

This directory is on `PATH` (via `/yolobox/.devcontainer/shellrc.sh`), so
the filenames are the commands:

- `sesh-init`: idempotent symlink setup/migration; auto-run per shell. It
  defers migrating a store that a live session has open — exit sessions and
  rerun if it says so.
- `sesh-push`: install every other machine's sessions into the home stores.
- `gpt-fork`: list other machines' Codex seeds (global, newest first) and
  fork one.
- `sesh-wipe`: manual reset — list stores, delete quarantined `*.divergent-*`
  copies, or delete a whole machine's store (typed confirmation; the
  deletion propagates to that machine via Dropbox).

Own-machine sessions never need installing: resume with `claude --resume` /
`codex resume`, fork with `claude --resume ID --fork-session` /
`codex fork ID`.

## Install ladder

Every cross-machine install (`sesh-push` and `gpt-fork`) decides per file,
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

## Reading sessions in a host VS Code window

Because `data/` is a bind-mounted, Dropbox-synced folder, the transcripts are
ordinary files on the Mac, and AIChatRender in a local (host) VS Code window
can read them. Add this machine's stores as extra roots and map the
container's `/yolobox` to the host checkout, in VS Code **user** settings (the
settings are machine-scoped and ignored in workspace settings):

```jsonc
"aichatrender.claudeTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/<machine>/claude"
],
"aichatrender.codexTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/<machine>/codex"
],
"aichatrender.pathMappings": [
  { "from": "/yolobox/", "to": "/ABS/CHECKOUT" }
]
```

Paths must be literal and absolute: no `~`, globs or `${...}`. If several Macs
share one user `settings.json` (e.g. symlinked from Dropbox), list every
machine's store in each array, since one file cannot pick a store per machine.
Each new ai-sesh machine then needs its two paths added. The mapping is the
same on every machine as long as the checkout path is.

After `sesh-push`, a session can appear twice: the other machine's original
and this machine's installed copy. The picker shows each copy's directory.
**Follow Active Terminal Chat** cannot match a terminal across the container
boundary, so in a host window it always falls back to the picker:

- **Automatic** (newest mtime) is right in normal use: resuming appends to
  this machine's copy, which becomes the newest, and the original stops
  changing.
- Picking by hand, choose the copy under this machine's `data/<machine>/`.

In a devcontainer window the extension runs in the container and reads only
`~/.claude/projects` (this machine's store), so there are no duplicates and
terminal matching works. Full walkthrough:
[extended setup](../../docs/extended-setup.md#using-more-than-one-mac).
