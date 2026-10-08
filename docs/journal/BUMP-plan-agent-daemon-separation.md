# Plan: separate agent installations and daemon state by container

2026-10-08. Discussion snapshot. Implementation deferred; this entry records the
decision and questions to resolve when we return to it.

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

1. Inventory actual installed versions, process managers, home contents and
   symlinks, authentication locations, session formats, and CLI install paths.
   Check applicable guidance and current upstream documentation. Inventory
   active work before choosing a maintenance window.
2. Allocate distinct persistent Codex and Claude home volumes for YOLO and
   normie in `.devcontainer/devcontainer.json` and its normie twin. Keep the
   in-container paths stable so existing seeding and ai-sesh scripts still work.
3. Separate the agent executable installations too. Today npm-global is shared;
   inspect everything installed there before deciding between mode-specific
   npm-global volumes and dedicated agent install locations. Keep R/Python/TeX
   package sharing unchanged. Explicitly preserve a workable update path for
   YOLO under its firewall/package restrictions; do not silently relax them.
4. Stop affected agent sessions/managers for migration. Preserve the original
   volumes; seed durable preferences/authentication only where supported and
   desired. Do not copy live PID records, sockets, locks, or daemon bookkeeping
   into new homes. Avoid a blind recursive copy of either live home.
5. Reapply `agents/` guidance/settings/skills and establish ai-sesh links in both
   homes. Preserve existing transcript bytes. Check whether other durable state
   needs migration for the installed Codex/Claude versions.
6. Recreate containers with the new mounts and start each agent independently.
   Verify daemon records and executable paths belong to the correct mode.
   Confirm `ybgpt` starts without the version warning and supported restart and
   update operations no longer collide. Inspect Claude's supported daemon status
   if that feature exists in the installed version.
7. Validate independent updates/restarts with no active user work; confirm the
   other container is unaffected. Check authentication, managed policies, skill
   discovery, sequential session resume/fork, and transcript visibility in both
   modes. Cover relevant launcher/mount regressions with existing tests.
8. Update repository documentation and volume naming/cleanup instructions.
   Retain old volumes until migration is verified; remove them only as a
   separately authorized cleanup. Rollback means restoring old mounts, with
   awareness that doing so also restores the original shared-state problem.

No container, installation, or agent-state changes were made for this plan.
