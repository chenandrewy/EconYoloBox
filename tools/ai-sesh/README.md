# ai-sesh

Session sharing for Claude Code and Codex, built on the Dropbox-synced
`/yolobox` mount. Every install, on every Mac and in both container modes
(YOLO and normie), links its session store to the same folder here, so a
session exited in one place can be resumed anywhere once Dropbox has synced.
Design notes: `docs/journal/1008b,BUMP-plan-ai-sesh-skill.md`.

## Mechanism

`ai-sesh-init` (auto-run by `.devcontainer/shellrc.sh` on every interactive
shell) keeps two links in place:

- `~/.claude/projects` -> `data/claude`
- `~/.codex/sessions` -> `data/codex`

Each home (`~/.claude`, `~/.codex`) is a private Docker volume for one mode
on one Mac; only these two folders point out into the shared tree. Claude
and Codex therefore write real bytes into `data/`, which Dropbox syncs.
Logins, settings, caches, Codex's session index and database, daemon state
and `history.jsonl` stay private to each install.

`data/` is git-ignored — Dropbox is the transport, not git. Folders named
after a machine (`data/macstudio25/`, ...) are the old per-machine stores
from before 2026-10-11, left as they were; delete them when no longer
wanted.

## Resuming elsewhere

- Claude: `claude --resume` from the same project folder (paths are
  `/yolobox/...` in every install, so the project matches).
- Codex: `codex resume <id>` or `codex resume --all`. The default picker
  lists from a per-install index and may omit sessions written elsewhere
  until indexed.

## Operating rule

**Exit the session where you are -> let Dropbox settle -> resume in the
other place.** Never run one session live in two places at once. Claude
appends to the jsonl live, so exiting first stops the file moving under
Dropbox. Breaking the rule makes Dropbox keep both versions, the second as
`<name> (<Mac>'s conflicted copy <date>).jsonl`; compare and delete by hand.

The first shell after an install's link changes repoints it immediately.
Exit that install's agent sessions first, or a running session continues in
the new folder and its transcript is split.

## Reading sessions in a host VS Code window

Because `data/` is a bind-mounted, Dropbox-synced folder, the transcripts are
ordinary files on the Mac, and AIChatRender in a local (host) VS Code window
can read them. Add the shared stores as extra roots and map the container's
`/yolobox` to the host checkout, in VS Code **user** settings (the settings
are machine-scoped and ignored in workspace settings):

```jsonc
"aichatrender.claudeTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/claude"
],
"aichatrender.codexTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/codex"
],
"aichatrender.pathMappings": [
  { "from": "/yolobox/", "to": "/ABS/CHECKOUT" }
]
```

Paths must be literal and absolute: no `~`, globs or `${...}`. The same
settings work on every Mac as long as the checkout path is the same. Full
walkthrough: [extended setup](../../docs/extended-setup.md#using-more-than-one-mac).
