# Plan: separate agent installations and daemon state by container

2026-10-08. Discussion snapshot. Implementation deferred; this entry records the
decision and questions to resolve when we return to it.

**Update 2026-10-11:** config change made (mode-specific source names as in the
table below, enforced by `test_config_twins.py`). Decision: cross-mode resume
listings are not a requirement; losing them is accepted, so step 5's index
work is dropped. No version pinning: new CLI volumes install `@latest`. Old
shared volumes are left in place for rollback.

## Decision / why

Give YOLO and normie independent persistent Codex and Claude Code homes and
installations. Keep the intentional sharing provided by `agents/` and
`tools/ai-sesh/`. Do not perform the migration today.

Currently both devcontainer configurations mount the same per-checkout volumes
at `/home/ubuntu/.codex` and `/home/ubuntu/.claude`. They also share the
`/usr/local/share/npm-global` volume containing the agent CLIs. The original
benefit: same login, preferences, binaries, and sessions when switching modes.
But sharing files does not share processes: the two containers have separate
process namespaces and `/tmp` directories.

The concrete trigger was a Codex warning on `ybgpt`. Investigation found:

- `ybgpt` selects YOLO even when invoked from the host shell; it is not host Codex.
- Both CLIs were 0.161.0 and the shared managed daemon installation was 0.161.0.
- Normie's running daemon was 0.161.0; YOLO's remained 0.160.0.
- Updating through `/daemon` in normie succeeded there, but did not restart YOLO.
- In YOLO, `codex app-server daemon restart` failed with
  `app server is running but is not managed by codex app-server daemon`.
- The shared `app-server-daemon/daemon-updater.pid` identified normie's updater
  process (282810), while YOLO's updater was a different process (8919).
  `daemon.pid` was absent at inspection time. The control socket symlink pointed
  into `/tmp/codex-daemon-1000/`, which resolves within each container's own `/tmp`.

This is evidence of conflicting shared management state for independent
daemons. Updating shared executable files does not replace code already loaded
by a running process. Relaunching the CLI reconnects to the old server.

No conversation corruption, lost work, or broken ordinary prompts was
established. `ybgpt` still worked. Potential consequences of the version mismatch
are missing server-side fixes and incompatibility with newer CLI features; we
did not inspect the 0.160.0-to-0.161.0 release changes to identify a specific
affected feature. The demonstrated failure is unreliable restart/update
management, not proof that everyday work is currently failing.

## Claude too

Current Claude Code documentation describes a background-session supervisor,
daemon version diagnostics, and state under its config directory. Separate
`CLAUDE_CONFIG_DIR` directories produce separate supervisor instances. The
supervisor normally updates itself and migrates idle sessions; version
mismatches can still occur.

Sources consulted:

- https://code.claude.com/docs/en/agent-view#how-background-sessions-are-hosted
- https://code.claude.com/docs/en/agent-view#where-state-is-stored

We did NOT establish that the installed Claude version is running this
supervisor, or reproduce a Claude daemon collision. The reason to separate
Claude too is to avoid the same class of shared runtime-state problem and make
the two containers independently maintainable. This is a design decision, not
a claim that Claude currently has the observed Codex failure.

## What remains shared

- `agents/managed/` supplies system configuration/policy baked into the image.
  Codex's `/etc/codex/config.toml` supplies defaults; its home `config.toml`
  retains user preferences.
- `agents/seed-agent-guidelines.sh` links guidance and skills from `agents/`.
  Claude settings are copied from the canonical file on container startup.
- `tools/ai-sesh/sesh-init` links Codex `sessions/` and Claude `projects/` and
  `todos/` into `tools/ai-sesh/data/<machine>/`. The machine identity normally
  comes from the host, so both modes can retain the same transcript store.
  This data is git-ignored and Dropbox-synced, not committed history.

Important qualification: sharing transcript files does not establish identical
resume listings or complete session continuity with separate local indexes,
databases, or newer paginated history formats. Verify the installed versions'
storage behavior before assuming ai-sesh covers everything. Do not share runtime
databases just to make listings match without understanding their ownership.

## Benefits / costs

Benefits:

- Each daemon's PID records, sockets, locks, caches, and update state belong to
  the container whose processes they describe.
- Updates and restarts can be reasoned about per mode. Separate CLI installations
  also prevent an installation update in one mode from changing the other's
  executable files unexpectedly.
- Keep common guidance and transcript storage through explicit existing paths,
  instead of sharing every new internal file an agent happens to introduce.
- Avoid selective mounts of undocumented daemon subdirectories that might move
  in a future release.

Costs / remaining risks:

- More disk usage and two installations to update; versions may intentionally
  diverge until both are maintained.
- Separate credentials, plugin installations, user preferences, and local
  caches/indexes. Decide what can be safely seeded once versus requiring login.
  Token refresh and logout will no longer automatically propagate between homes.
- Migration requires downtime for affected sessions and careful preservation of
  existing data. Old volumes should remain available for rollback.
- ai-sesh still shares transcript/todo files. Separate homes do not make
  simultaneous continuation of the same conversation safe; test sequential
  handoff and avoid concurrent writers to one session.
- Claude's canonical settings copy still runs at startup. Separation removes
  cross-container overwrites, but not each container's own startup reset.

## Implementation sketch for later

Follow-up discussion: volume identity is the central separation concern, and
distinct source names solve it straightforwardly. The main integration work is
then making ai-sesh preserve the intended session-sharing behavior. Disk usage,
duplicated updates, and migration downtime are secondary operational costs,
not reasons to complicate the design.

The source names are encoded directly in the `mounts` arrays of
`.devcontainer/devcontainer.json` and `.devcontainer/normie/devcontainer.json`.
Use the following explicit mapping, with `${localWorkspaceFolderBasename}` as
the checkout prefix:

| Target inside either container | YOLO source | Normie source |
| --- | --- | --- |
| `/home/ubuntu/.codex` | `${localWorkspaceFolderBasename}-yolo-codex-config` | `${localWorkspaceFolderBasename}-normie-codex-config` |
| `/home/ubuntu/.claude` | `${localWorkspaceFolderBasename}-yolo-claude-config` | `${localWorkspaceFolderBasename}-normie-claude-config` |
| `/usr/local/share/npm-global` | `${localWorkspaceFolderBasename}-yolo-npm-global-noble-node24` | `${localWorkspaceFolderBasename}-normie-npm-global-noble-node24` |

Docker volume identity comes from the source name, not the target path or
container name. Keep the existing paths, `CODEX_HOME`, and `CLAUDE_CONFIG_DIR`
inside each container. Inspect other npm-global contents before splitting that
volume; the preferred layout is one installation volume per mode.

Pitfalls to check explicitly:

- Changing config files does not change existing container mounts. Recreate
  both containers and inspect their actual mount maps: these three sources must
  differ by mode; intentionally shared analysis-package volumes remain shared.
- Check resolved symlinks too. Agent runtime state and installations must not
  lead back to the old shared volume. Only deliberate sharing links should
  connect the homes to common writable data.
- Mode suffixes solve YOLO/normie collisions, not collisions between two host
  checkouts with the same basename. Retain the existing one-checkout-per-basename
  rule and verify `check-checkout.sh` markers in both new Claude volumes. A
  globally unique checkout naming scheme would be a separate change.
- Keep the host-derived ai-sesh machine ID the same in both modes. Appending
  `yolo`/`normie` there would split the transcript store, contrary to the intended
  shared-history behavior. Container identity and transcript-store identity serve
  different purposes.
- `sesh-init` already supports separate homes pointing into the same data tree;
  do not assume it needs a redesign. Verify or update its initialization and
  current-format session support. Ensure the correct links exist before either
  agent starts, and test discovery/resume with independent local indexes.
- Startup seeds settings and installs missing CLIs; interactive shells run
  `sesh-init`, which can migrate files. Prepare migration before allowing normal
  startup. Its `/proc` checks cannot see writers in the other container, so stop
  affected work in both modes rather than relying on that busy check alone.
- Retaining old home volumes does not snapshot the ai-sesh data reached through
  symlinks. Back up the shared data separately while it is quiet. Rollback must
  account for any writes to that shared data after cutover.
- New installation volumes trigger an installer that requests `@latest` today.
  Use recorded initial versions to avoid mixing the migration with an unrelated
  upgrade. The launcher rebuild path also recreates the other mode; account for
  both containers when scheduling the cutover.

1. Inventory actual installed versions, process managers, home contents and
   symlinks, authentication locations, session formats, and CLI install paths.
   Check applicable guidance and current upstream documentation. Inventory
   active work before choosing a maintenance window.
2. Assign the explicit mode-specific source names above in the two configs.
   Check the pair together for accidental reuse of a source and retain stable
   in-container paths. Verify checkout-marker behavior and relevant mount tests.
3. Separate executable installations using the mode-specific npm-global volumes,
   after inventorying their contents. Keep R/Python/TeX package sharing unchanged.
   Explicitly preserve a workable update path for
   YOLO under its firewall/package restrictions; do not silently relax them.
4. Stop affected agent sessions/managers in both modes for migration. Snapshot
   shared ai-sesh data separately and preserve the original volumes. Prepare new
   volumes before normal startup; seed durable preferences/authentication only where supported and
   desired. Do not copy live PID records, sockets, locks, or daemon bookkeeping
   into new homes. Avoid a blind recursive copy of either live home.
5. Reapply `agents/` guidance/settings/skills and establish ai-sesh links in both
   homes to the same existing machine store. Update ai-sesh only as needed for
   reliable initialization and current session formats. Preserve existing
   transcript bytes; identify supporting state needed for discovery and resume
   without reintroducing shared daemon bookkeeping or runtime databases.
6. Recreate containers with the new mounts and start each agent independently.
   Inspect actual Docker mounts and resolved links against the mapping above.
   Verify daemon records and executable paths belong to the correct mode.
   Confirm `ybgpt` starts without the version warning and supported restart and
   update operations no longer collide. Inspect Claude's supported daemon status
   if that feature exists in the installed version.
7. Validate independent updates/restarts with no active user work; confirm the
   other container is unaffected. Check authentication, managed policies, skill
   discovery, sequential session resume/fork, and transcript visibility in both
   modes. Test both pre-migration conversations and new conversations created in
   either mode; do not concurrently resume one conversation in both. Confirm
   installed CLI and running daemon versions separately in each mode. Cover
   relevant launcher/mount and ai-sesh regressions with existing tests.
8. Update repository documentation and volume naming/cleanup instructions.
   Retain old volumes until migration is verified; remove them only as a
   separately authorized cleanup. Rollback means restoring old mounts, with
   awareness that doing so also restores the original shared-state problem.

No container, installation, or agent-state changes were made for this plan.

## Cutover instructions (2026-10-11)

The config change is committed; the rebuild reads the config from the
checkout. `<folder>` below is the checkout's folder name.

1. **Before the rebuild (host).** Note the old shared volumes; they are the
   rollback.

   ```zsh
   yolobox --status
   docker volume ls | grep -E 'claude-config|codex-config|npm-global'
   ```

   Exit all Claude and Codex sessions in both modes and close VS Code windows
   attached to either container (the launcher refuses to rebuild while one
   is connected).

2. **Rebuild (host).** `yolobox --rebuild` recreates both containers if both
   exist. On first start each container records its checkout marker in the
   new `~/.claude`, seeds guidance and settings from `agents/`, and installs
   `@latest` Claude Code and Codex into its new CLI volume. The first
   interactive shell runs `sesh-init`, linking `projects/`, `todos/` and
   `sessions/` into the shared transcript store. A mode that does not exist
   yet is created on first launch (e.g. `yolobox --normie`).

3. **Log in once per mode.** In YOLO (`yolobox --shell`) and normie
   (`yolobox --normie --shell`): run `claude` and complete login (or
   `/login`), then `codex login`. If browser login fails in YOLO, try
   `codex login --device-auth`; untested through the firewall, so report the
   blocked host if one fails.

4. **Verify.** On the host:

   ```zsh
   docker volume ls | grep -E 'yolo-|normie-'
   docker inspect $(docker ps -q) --format '{{.Name}}{{range .Mounts}} {{.Name}}->{{.Destination}}{{end}}' | tr ' ' '\n' | grep -E 'config|npm-global|^/'
   ```

   Expect six new volumes, each container mounting only its own mode's three.
   Inside each container:

   ```zsh
   ls -l ~/.claude/projects ~/.claude/todos ~/.codex/sessions
   claude --version; codex --version
   ```

   Then run `ybgpt` and confirm the daemon version warning is gone. Update or
   restart the Codex daemon in one mode (`/daemon`) and confirm the other mode
   is unaffected.

5. **Optional: carry over Codex preferences.** New homes start without a
   personal `config.toml`. Copy only that file (host):

   ```zsh
   docker run --rm -v <folder>-codex-config:/old:ro -v <folder>-yolo-codex-config:/new alpine cp /old/config.toml /new/
   ```

   Repeat for `<folder>-normie-codex-config`. Do not copy the rest of the old
   home: it holds the daemon state this change separates.

6. **Rollback / cleanup.** Rollback: `git revert` the commit, then
   `yolobox --rebuild`; the old volumes are untouched. Cleanup, once
   satisfied and only as a deliberate step: `docker volume rm` the three old
   volumes. This is irreversible.

Not carried over to the new homes: Claude plugins and `.claude.json` state
(onboarding, folder trust), the personal Codex `config.toml` (unless step 5),
and Codex's local session index, so old Codex sessions will not appear in
`codex resume` listings; their transcripts remain in `tools/ai-sesh/data/`.
