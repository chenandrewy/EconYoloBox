# 0917b — plan: mount the repo at /sandbox, projects under /sandbox/workspace/

Discussion snapshot, 2026-09-17. Decided; not yet implemented.

**Timing:** implement after testing the `firewall-host-switch` security
posture for a few days. The layout change requires a rebuild and a session-store
migration, and we want the firewall/seccomp posture settled before stacking
another container change on top of it.

## proposal

Rename the container mount from `/workspace` to `/sandbox`, and move the
research projects into a `workspace/` subfolder:

```
/sandbox/                    <- this repo (EconYoloBox), bind-mounted
  .devcontainer/ .tools/ .credentials/ .host/ .setup/ docs/ SANDBOX.toml ...
  workspace/                 <- user content, one .gitignore line
    Live,Foo/  Ref,Bar/  DONE/  LIBRARY/  Other/  dev/
```

`docs/` (including this journal) stays with the sandbox; everything currently
matched by the `.gitignore` project globs moves under `workspace/`.

## decision

Do it. The value is almost entirely in the projects subfolder; the `/sandbox`
rename is what lets that subfolder be called `workspace` without a
`/workspace/workspace/` double meaning.

## why

- Today the repo root mixes infrastructure with research content, and
  `.gitignore` copes by enumerating name patterns (`Ref,*/`, `Live,*/`,
  `Live_*/`, `Other/`, ...). A project with a new naming scheme silently lands
  in the public sandbox repo. `workspace/` makes that one ignore line and
  removes the leak risk.
- Adopters see where projects go without reading docs; `SANDBOX.toml`'s
  `research_library` and `screenshot_directory` obviously point at user content.
- Naming is coherent: `/sandbox` is what `SANDBOX.toml` configures;
  `workspace` is where you work.
- Bonus: a `/sandbox/CLAUDE.md` would apply to every project via Claude Code's
  upward walk, a scope between user-level (`~/.claude/CLAUDE.md`, which is what
  `SANDBOX-CLAUDE.md` becomes today) and per-project.

## relation to devcontainer convention

Standard practice is one devcontainer per repo, mounted at
`/workspaces/<repo-name>` (VS Code and Codespaces default). The singular
`/workspace` is a hand-rolled-image habit (Anthropic's Claude Code devcontainer,
which this sandbox descends from, uses it). Multiple repos in one container is
supported but second-class: open the parent folder, add `mounts`, or use a
multi-root `.code-workspace`.

This sandbox inverts the convention: the devcontainer is a shared environment
that many independent repos live inside, not a property of any one repo. The
rename makes that departure explicit rather than accidental.

Names ruled out:

- `/workspace/workspace/` — double meaning.
- `/workspace/projects/` — reads as "the sandbox is a project too", muddying
  the infra/content split.
- `/sandbox/workspaces/` (plural) — collides with the VS Code/Codespaces
  convention and implies semantics we do not have (one auto-mounted checkout
  per subfolder).
- `/sandbox/projects/` — the only clearer alternative, but loses the
  "sandbox contains workspace" reading. Not chosen.

## confusion risk

Small, and about the *word*, not the path. Agents have no prior on the string
`/workspace` (images use `/workspace`, `/app`, `/code`, `/src` interchangeably)
and will read `/sandbox/workspace/Live,Foo/` correctly on sight. But
"workspace" in agent prose nearly always means "the tree I am working in" (VS
Code workspace, Codex `workspace-write`, devcontainer `workspaceFolder`), which
in this layout is one project, while our `workspace/` is the folder of all
projects. This only shows up in prose ("outside the workspace"), and the
current layout already has it: `/workspace` is the parent of the agent's
working tree, not the tree itself.

Mitigation: define the two terms once in `SANDBOX-CLAUDE.md` and once in the
README ("the sandbox is `/sandbox`; projects live in `/sandbox/workspace/`").

## costs and what has to change

1. **Hard-coded `/workspace` paths** — 34 files at time of writing (`grep -rl
   /workspace`). Mechanical. The load-bearing ones:
   - `.devcontainer/devcontainer.json:146-147` — `workspaceMount` target and
     `workspaceFolder`.
   - `.devcontainer/shellrc.sh` — `.tools` PATH entries (line 14), session
     naming `${PWD#/workspace}` (line 103) and its comment, `R_PROFILE_USER`,
     the firewall/seccomp hint strings.
   - `.tools/ai-sesh/_common.sh:4` — `workspace_root`; the "run this from
     inside a /workspace project" message. Should become
     `/sandbox/workspace`.
   - `.devcontainer/agents/SANDBOX-claude-settings.json` — statusline command
     path.
   - `.devcontainer/agents/SANDBOX-CLAUDE.md` — environment description, tools
     paths, screenshot guidance.
   - `SANDBOX.toml` — `research_library`, `screenshot_directory`.
   - `README.md`, `docs/features.md`, `docs/storage-needs.md`,
     `docs/public-release.md`, `.tools/ai-sesh/README.md`.
   - Journal entries are historical; leave them.
   - `.gitignore` — replace the project globs with `workspace/`.
2. **Session stores are keyed on cwd.** Claude Code stores transcripts under
   `~/.claude/projects/<cwd with / and , mapped to ->/` (e.g.
   `-workspace-Disc-ABFR`), and the `.jsonl` lines embed `cwd`. Codex
   sessions and the ai-sesh per-machine stores under `.tools/ai-sesh/data/`
   use the same slug via `claude_key_for_rel`. Every existing session is
   orphaned from its project unless migrated. Needs a one-shot script:
   rename the store directories (`-workspace-X` → `-sandbox-workspace-X`) and
   rewrite the `cwd` field in transcripts; same for the Codex store and every
   machine's ai-sesh store. Verify `sesh-push` / `cc-fork` round-trip after.
3. **Host side.** Projects physically move one level down in Dropbox. Dropbox
   treats that as a move; each project's own git repo does not care;
   `dce`/`dccode` walk up to the enclosing `devcontainer.json`, so they keep
   working. Host-side absolute paths break: LyX recent files, Finder
   favorites, anything in the machine-settings repo pointing at
   `.../EconYoloBox/Live,Foo`. Check `cc-remote-*` / `ccsessions` there.
4. VS Code opens the container at `/sandbox` (infra), not at projects.
   `dccode <dir>` already handles subfolders.
5. Rebuild required (mount target changes).

## steps

1. Branch. Substitute paths in the load-bearing files above; update
   `.gitignore`; update docs and agent guidance including the term
   definitions.
2. Write the session-store migration script (Claude projects, Codex sessions,
   ai-sesh data for all machines). Dry-run mode first.
3. On the host: `mkdir workspace`, move the project folders in, wait for
   Dropbox to settle.
4. Rebuild container. Run the migration. Check `claude --resume` from a
   project, `sesh-push`, `cc-fork`, the statusline, `.tools` on PATH, R
   profile, screenshots path.
5. Fix host-side shortcuts in the machine-settings repo.

Budget: an afternoon, mostly step 2 and its verification.
