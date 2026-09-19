# 0918a — plan: rename the mount to `/sandbox`, put user content in `workspace/`

Discussion revision, 2026-09-18. Decided; not yet implemented.

This supersedes `0917b,BUMP-sandbox-workspace-layout-plan.md`. The layout
decision is unchanged, but session-history migration is no longer on the
critical path. First make the filesystem and container layout coherent; repair
or migrate old cross-machine session history later if it proves worthwhile.

## outcome

Mount the host's `1-SANDBOX` repository directory at `/sandbox` and put user
content beneath a single ignored `workspace/` directory:

```
/sandbox/                         <- host 1-SANDBOX folder, bind-mounted
  .devcontainer/ .tools/ .credentials/ .host/ .setup/ docs/
  README.md SANDBOX.toml ...
  workspace/                      <- ignored user content
    Live,Foo/ Ref,Bar/ DONE/ LIBRARY/ Other/ dev/
```

The important change is the `workspace/` boundary. It replaces a growing set
of naming-convention-based ignore rules with one structural rule, so a project
with a new name cannot silently become part of the public sandbox repository.

Use these terms consistently in documentation and agent guidance:

- **sandbox**: the infrastructure repository mounted at `/sandbox`;
- **workspace** or **user workspace**: user content under
  `/sandbox/workspace/`;
- **project**: one working tree inside the user workspace.

## what the bind mount does and does not protect

The projects are not individually bind-mounted. The host's entire `1-SANDBOX`
directory is mounted once, currently at `/workspace` and afterward at
`/sandbox`.

Changing only the container mount target would therefore change
`/workspace/Live,Foo` to `/sandbox/Live,Foo`; it would not create the new
`workspace/` level. Achieving the proposed layout also requires moving the
project directories one level down on the host.

That move does not alter project contents, Git metadata, branches, remotes, or
history. Each project remains an ordinary directory in the same Dropbox tree.
What does change is its absolute path:

```
host:      .../1-SANDBOX/Live,Foo
        -> .../1-SANDBOX/workspace/Live,Foo

container: /workspace/Live,Foo
        -> /sandbox/workspace/Live,Foo
```

Relative paths within a project remain valid. Host applications, recent-file
lists, scripts, shortcuts, and session records that saved the old absolute path
may need updating.

## scope

### Required now

1. Change the container mount target and default folder from `/workspace` to
   `/sandbox`.
2. Change all active infrastructure paths that refer to the sandbox root.
3. Move the current root-level user-content directories into `workspace/`.
4. Replace the project-name globs in `.gitignore` with `/workspace/`.
5. Update current documentation, agent guidance, host helpers/tests, and helper
   names.
6. Rebuild and validate the container and nested-project launch flow.

### Deferred

Migration of old Claude, Codex, and `ai-sesh` history is explicitly not a
prerequisite for the layout change.

Old Claude sessions are keyed by their old cwd and may no longer appear when
resuming from the new project path. Codex rollouts are stored globally, though
their metadata can retain the old cwd. The synced `ai-sesh` stores can likewise
retain old Claude keys. This is accepted for the initial migration.

The live `ai-sesh` configuration still needs its workspace root changed to
`/sandbox/workspace`, so future `cc-fork` operations resolve new project paths
correctly. What is deferred is rewriting and renaming historical stores, not
making the helper aware of the new layout.

If historical migration is done later, it should be a separate plan with an
explicit old-path-to-new-path map. A blanket `-workspace-X` to
`-sandbox-workspace-X` substitution is wrong because the old sandbox root maps
to `/sandbox`, infrastructure maps to `/sandbox/...`, and only moved user
content maps to `/sandbox/workspace/...`.

## files to change

Regenerate the inventory immediately before editing with a targeted search of
active files. Do not edit historical journal entries merely to modernize their
paths.

Load-bearing changes include:

- `.devcontainer/devcontainer.json`
  - `workspaceMount` target: `/sandbox`
  - `workspaceFolder`: `/sandbox`
- `.devcontainer/Dockerfile`
  - `WORKDIR`
  - creation and ownership of the mount-point directory
  - zsh startup line that sources `.devcontainer/shellrc.sh`
  - active comments that describe the mount
- `.devcontainer/shellrc.sh`
  - `.tools` entries on `PATH`
  - shell/session naming based on `PWD`
  - `R_PROFILE_USER`
  - security diagnostic paths
- `.devcontainer/check-seccomp.sh`
- `.devcontainer/agents/SANDBOX-claude-settings.json`
- `.devcontainer/agents/SANDBOX-CLAUDE.md`
- `.tools/ai-sesh/_common.sh`
  - set the project root to `/sandbox/workspace`
  - update its user-facing error message
- `SANDBOX.toml`
  - `research_library = "/sandbox/workspace/LIBRARY/"`
  - `screenshot_directory = "/sandbox/workspace/dev/screenshots/"`
- `.host/tests/test-bbox.zsh`
- `README.md`, `.devcontainer/README.md`, `docs/features.md`,
  `docs/storage-needs.md`, `docs/public-release.md`, and
  `.tools/ai-sesh/README.md`
- `.gitignore`

The host resolver itself derives the remote path from `workspaceFolder` and
should not need a layout-specific code change. Its current public helper names
are `bbox`, `bbe`, and `bbcode`; replace stale documentation that still refers
to `dce` or `dccode`.

## exact move set

Before moving anything, generate and review an explicit list of root-level
directories selected by the existing ignore rules. At present the intended
classes are:

```
Ref,*/
Disc,*/
Travel,*/
Live,*/
Live_*/
Other/
LIBRARY/
dev/
DONE/
```

Apply those patterns only to immediate children of the sandbox root. Do not
recursively search for matching names. Record the expanded list in the
migration output so unexpected or missing directories are visible before any
move occurs.

Infrastructure and repository state—including `.git`, `.devcontainer`,
`.tools`, `.host`, `.setup`, `.credentials`, `docs`, and `SANDBOX.toml`—remain
at the sandbox root.

## implementation order

1. **Prepare the repository changes.** On a branch, update `.gitignore` first
   so `/workspace/` is ignored before it exists. Update the active hard-coded
   paths, documentation, agent guidance, and host-helper tests. Keep historical
   journals unchanged.
2. **Check the move manifest.** Expand only the root-level patterns above,
   review the resulting source and destination paths, and ensure every
   destination is absent.
3. **Move user content on the host.** Create `workspace/`, move the manifest
   entries into it, and let Dropbox settle. This is a host filesystem move,
   not a copy or project rewrite.
4. **Rebuild.** Recreate the devcontainer so the new `/sandbox` mount target,
   Dockerfile working directory, startup configuration, and generated agent
   guidance take effect.
5. **Validate.** Exercise the sandbox root and at least one nested project.
6. **Repair host references.** Update known absolute paths in the
   machine-settings repository, Finder favorites, LyX recent files, and any
   remote-control/session-discovery helpers that still point to the old host
   location.

Do not combine the physical move with historical session rewriting. Keeping
those operations separate makes the core migration smaller and leaves the
session cleanup optional and reversible.

## validation

### Layout and ignore boundary

- `/sandbox` is the repository root inside the container.
- `/sandbox/workspace` contains all intended user content and no sandbox
  infrastructure.
- A newly created, arbitrarily named directory directly under
  `/sandbox/workspace` is ignored without adding another pattern.
- The root-level project directories no longer exist.

### Container startup

- The image builds and the container starts at `/sandbox`.
- `postStartCommand` succeeds.
- The firewall/seccomp checks and `test-agent-policy.sh` pass.
- The status line, `.tools` on `PATH`, `R_PROFILE_USER`, TeX helpers, and
  screenshot discovery use the new paths.

### Host launchers and projects

- `.host/tests/test-bbox.zsh` passes with `/sandbox` expectations.
- `bbe` opens a shell at the sandbox root.
- `bbe workspace/<project>` opens at `/sandbox/workspace/<project>`.
- `bbcode workspace/<project>` opens the same nested project in VS Code.
- A representative project has the same Git branch, status, remotes, and
  tracked files as before the move.

### Sessions

- A new Claude session launched from a moved project is stored under the new
  cwd key.
- A new Codex session records `/sandbox/workspace/<project>` as its cwd.
- `cc-fork` recognizes the new project root, even if no old sessions have been
  migrated.
- Failure to discover an old path-keyed session is documented as an accepted
  deferred issue, not a failure of the layout migration.

## rollback

If startup or project discovery fails, the layout can be rolled back without
touching project internals:

1. restore the previous infrastructure-path changes;
2. move the entries from `workspace/` back to the sandbox root using the saved
   manifest;
3. restore the former `.gitignore` rules; and
4. rebuild with the `/workspace` mount target.

Do not delete or regenerate project repositories or session stores during
rollback.

## estimate

The core rename and content move should fit in a focused half day, plus Dropbox
settling and host-reference cleanup. Historical session migration, if desired,
is a separate task and estimate.
