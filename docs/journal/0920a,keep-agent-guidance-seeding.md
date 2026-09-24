# 0920a — keep agent guidance in `.devcontainer/agents/`, not a root `CLAUDE.md`

Discussion snapshot, 2026-09-20, branch `yolo-default-posture`. Considered
and rejected; nothing changed.

## the idea

Replace `.devcontainer/agents/SANDBOX-CLAUDE.md` (+ the `SANDBOX-AGENTS.md`
symlink and the two `ln -sfn` lines in `seed-agent-guidelines.sh`) with a
plain `CLAUDE.md` at the sandbox root. Conventional location, no dependence on
`postStartCommand`, and Claude Code walks ancestor directories from cwd, so
`/sandbox/CLAUDE.md` would load from any `workspace/<project>` even though
each project is its own git repo.

## why not

- **Codex asymmetry.** Codex discovers `AGENTS.md` from the *git root* of cwd
  downward. Workspace projects are separate repos, so `/sandbox/AGENTS.md`
  would be invisible inside them; `~/.codex/AGENTS.md` would still have to be
  seeded. The seed script survives regardless (skills and settings), so the
  move deletes one line, not a mechanism.
- **Host confusion.** The host session in this Dropbox folder gets the host's
  own `~/.claude/CLAUDE.md` today. A root `CLAUDE.md` would also load there,
  and its content (`/sandbox`, `python3` → `/opt/venv`, firewall allowlist,
  `dbhydrate`) is false on the host. Scoping the wording would work but adds a
  new way to be wrong.
- Minor: user-level guidance applies everywhere in the container; a root file
  applies only under `/sandbox`.

## decision

Keep the existing seeding: `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`
symlinked live to `.devcontainer/agents/` on every container start. The only
cost is the unconventional location.

## side note on journaling

Entries like this one are the noisy kind: a decision, not an investigation.
Future option, not adopted yet: a one-paragraph-per-entry `docs/decisions.md`
as an index pointing back into the journal, plus a "why not" comment at the
point where the question arises (`seed-agent-guidelines.sh:11`, README "Agent
Config"). Journal stays disposable and untidied; `archive/` gets a periodic
sweep.
