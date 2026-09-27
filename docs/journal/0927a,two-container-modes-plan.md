# 0927a — plan: one container per mode, two tracked configs, shared volumes

2026-09-27, branch `feature/package-install-modes`. Plan only; revised twice
after review. Motivation, in two lines: any design where `bbox` destroys a
container VS Code knows about races the extension, which recreates it from
the config file with its own environment (seen in the wild today: a YOLO
container materialized next to bbox's normie one). So: never recreate on a
switch — keep one container per mode, and put each mode's posture in a config
file the extension can see.

## the design

```
.devcontainer/devcontainer.json          YOLO   (unchanged path; VS Code's default)
.devcontainer/normie/devcontainer.json   normie (also tracked)
```

Both files are checked in. Each hard-codes its posture: seccomp in
`runArgs`, `readonly` on the three package mounts, `SANDBOX_INTERNET` in
`containerEnv`. The `${localEnv:SANDBOX_*}` variables and their fallbacks are
deleted. The Dev Containers tooling keys containers on the config path, so
the two files give two coexisting containers, and a recreation by the
extension — Rebuild, Reopen, or the race above — reproduces the same mode.
`name` gets a ` (normie)` suffix in the normie file so `docker ps`, the
Reopen picker and window titles tell them apart.

**Persistent volumes are shared across the modes** by dropping
`${devcontainerId}` from their names: `1-SANDBOX-claude-config`,
`1-SANDBOX-codex-config`, `1-SANDBOX-npm-global-noble-node24`,
`claude-code-bashhistory-1-SANDBOX` — basename-keyed, identical in both
configs, so one login and one CLI install serve both modes. The package
volumes (R, Python, TeX) already have fixed names and share as before.

Dropping the id retires the 2025-era same-basename defense. New rule: **one
checkout per basename per Docker daemon.** Guard: `post-start.sh` writes
`LOCAL_CONTAINER_FOLDER` to a marker file in `~/.claude` on first start and
refuses on mismatch, so a same-basename test checkout announces itself
instead of silently sharing tokens and executables. Side effect: moving the
checkout no longer orphans the volumes (renaming still does).

## bbox changes

- `--yolo` (default) / `--normie` choose the config, in three places:
  `devcontainer up --config <file>`, `devcontainer exec --config <file>`
  (without it, `bbe --normie` would exec into the YOLO container), and the
  `configFile` in the VS Code folder URI (`dc-resolve.py folder-uri` and
  `remote-path` take the config path).
- Container lookup filters on both labels (`devcontainer.local_folder` and
  `devcontainer.config_file`): `existing`, `_bbox_clear_containers` (rebuild
  only), `_bbox_check_duplicates`, and `_bbox_verify_layout` (each mode
  against its own config's `workspaceFolder`). Containers with a foreign
  config label are invisible to bbox and left alone.
- **Deleted**: the whole switch path — the posture comparison, the "recreate
  it in YOLO mode now?" prompt, the switch-time VS Code-attached refusal.
  A mode is never replaced.
- **Kept**: the post-`up` posture sanity check (after the duplicate check).
- **New**: `bbox --stop [--yolo|--normie]` stops one mode's container;
  `bbox --status` lists both; every YOLO `up` notes a running normie
  container ("normie container 12b8 is also running, firewall open;
  bbox --stop --normie") — a note, not a prompt.
- `--rebuild` recreates only the chosen mode's container; no flag means YOLO,
  as everywhere else.

## credentials become environment variables

Long deferred; the agents expect env vars anyway. `inject-credentials.py`
keeps writing `/tmp/devcontainer-credentials.env`; `runArgs` gains a second
`--env-file` pointing at it; the bind mount and
`/run/secrets/credentials.env` are removed. `get-credentials.py`/`.R`
already prefer env vars, so consumers are unchanged; retire their file
fallback with the docs. Accepted trade-offs: credentials are frozen at
creation (rotation = recreation; the truncate-to-revoke trick dies), and
they appear in `docker inspect` on the host and `/proc/*/environ` inside.
Land this as its own commit first — it shares no code with the rest.

## migration

One-time, per checkout, per host (volumes survive):

```
docker ps -aq --filter "label=devcontainer.local_folder=<root>" | xargs docker rm -f
```

Old containers carry the YOLO config label whatever their posture, and old
volumes carry `${devcontainerId}` names. The container wipe plus the rename
means fresh volumes: one re-login and CLI reinstall per checkout. Find the
orphaned old volumes later with `docker volume ls -f dangling=true`.

## costs, accepted

1. **Config duplication.** No `extends` in the spec, so the two files are
   ~95% identical. Guard: a test that parses both (JSONC) and fails unless
   they differ only in the posture keys and `name`.
2. **Normie can outlive the task.** It keeps running, firewall open, until
   stopped. Mitigations: the note on every YOLO `up`, `--stop`, `--status`.
   Whether closing its last window stops it (`shutdownAction` default) is
   unverified — test it, and if it doesn't, consider a firewall-side backstop
   later rather than more notes.
3. **Shared live package volumes.** YOLO mounts them read-only while normie
   writes; running R/Python sessions see new packages only after restart.
   Intended, harmless.
4. **Normie writes what YOLO runs.** Shared npm-global means normie installs
   the executables the YOLO container executes. Not a regression: the
   volumes already survived mode switches today.
5. **Resources.** Two containers when both run; two image tags sharing
   cached layers.

## what stays

`posture.sh`, `post-start.sh`'s firewall logic (reads `SANDBOX_INTERNET`,
now hard-coded per config), the mode displays, the `-yolo` launcher guard,
the install scripts' normie checks, the shared `/sandbox` bind mount.

## out of scope / notes

- Stray containers with unknown config labels: not bbox's problem.
- Host-side `ccsessions`/`cckill`/`cchat-yolo` tooling (not in this repo)
  assumes one container per folder; fix when touched.
- Also update: `devcontainer.json` comments (the id-key rationale block is
  replaced by the one-checkout-per-basename rule), READMEs,
  `docs/features.md`, agent guidance, tests.

## verification (real Docker, on the Mac)

1. Migration wipe (includes strays `8d65342e118e`, `12b8ecf0a036`).
2. `bbcode` → YOLO container; `--status` shows one; credentials are env
   vars; `/run/secrets` gone.
3. `bbcode --normie` with the YOLO window open → second container, "(normie)"
   name, red window, YOLO untouched.
4. In normie: Claude and Codex work after a single login done in either mode;
   shared shell history.
5. Close the normie window; log whether it stops.
6. Extension's Rebuild Container from each window → same mode, same volumes.
7. `bbe --normie` attaches without recreation; `bbe --yolo` while both run
   lands in the YOLO container.
8. Same-basename guard: a second checkout named `1-SANDBOX` elsewhere is
   refused by post-start.
9. `bbox --stop --normie`; next `bbcode` drops the note.
10. Config-drift test, `test-bbox.zsh`, `test-posture.sh` pass.
