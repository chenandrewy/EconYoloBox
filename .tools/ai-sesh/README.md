# ai-sesh

Staging area for moving Claude Code and Codex sessions between machines and
across container rebuilds, plus fork helpers for reusing seed sessions. The
home stores (`~/.claude/projects/`, `~/.codex/sessions/`) are the source of
truth; `data/` here is a disposable cache — grab, install, clear, repeat.
This replaces the per-project `agent-sessions/` folders (e.g. in
`Live,goners` and the ABFR discussion).

## Commands

This directory is on `PATH` (via `/workspace/.devcontainer/shellrc.sh`), so
the filenames are the commands:

- `sesh-grab`: save a live session into `data/` (run from the project dir).
- `sesh-push`: install **all** of `data/` into the home stores (run from
  anywhere).
- `sesh-wipe`: delete **all** of `data/`, after listing the sessions and
  confirming; flags any session not present in its home store, since those
  are the only ones deletion actually loses.
- `cc-fork`: list the current project's cached Claude seeds and fork one.
- `gpt-fork`: same for Codex.

Typical flow:

```bash
cd /workspace/Live,goners
sesh-grab 019f1b21          # stage a session
# ... move machines / rebuild container ...
sesh-push                   # push everything back into the home stores
sesh-wipe                   # empty the staging area
```

## Layout

- `data/<project>/claude/*.jsonl`: Claude transcripts (filename = session id).
  `<project>` is the project's path relative to `/workspace`.
- `data/<project>/codex/*.jsonl`: Codex rollouts (keep original filenames —
  the date in the name drives the restore location).
- `data/` is git-ignored (`.tools/ai-sesh/data/` in the workspace
  `.gitignore`): transcripts are bulky, possibly sensitive, and disposable.
- `_common.sh`: shared helpers sourced by the commands.

There is no per-project configuration: `sesh-grab` and the fork commands
derive the project from `pwd` (run them from the directory where you run
`claude`/`codex`), and `sesh-push` derives each project from its `data/`
subfolder path.

## Forking

```bash
cc-fork --list              # numbered seeds with first-prompt summaries
cc-fork 1                   # fork by number (installs into home store first)
cc-fork d066efc8            # or by id prefix
gpt-fork 1 "continue from this context"
```

Both fork commands pass extra arguments through to `claude` / `codex`. They
default to permissive local modes (`--dangerously-skip-permissions` /
`--dangerously-bypass-approvals-and-sandbox`); set the flag variable to
empty to omit:

```bash
CLAUDE_FORK_PERMISSION_FLAG="" cc-fork
CODEX_FORK_PERMISSION_FLAG="" gpt-fork
```

## Notes

- Claude sessions are stored per project under
  `~/.claude/projects/<path-with-slashes-and-commas-as-dashes>`; the
  commands compute that key at runtime, so a moved/renamed project just
  means its cached seeds install under the new key.
- Codex sessions are global (`~/.codex/sessions/YYYY/MM/DD`), so only the
  rollout filename matters.
