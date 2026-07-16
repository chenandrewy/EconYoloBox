# Devcontainer rebuild fails: credentials env file deleted before docker run

2026-07-15, ~16:20 NY time

## How we found it

Full container rebuild (cold cache) failed at the very end with:

```
docker: --env-file: open /tmp/devcontainer-credentials.env: no such file or directory
```

The image build itself succeeded (all 37 steps). The failure was at `docker run`.

## Root cause

A race between the credentials auto-delete timer and the image build:

1. `initializeCommand` runs `inject-credentials.py`, which writes `/tmp/devcontainer-credentials.env` and spawns a detached reaper: `sleep 1200 && rm -f <file>` (`inject-credentials.py:23,48-53`).
2. The image build then runs — this time it took **1243 s** (~21 min cold cache; the R package layers alone are ~10 min).
3. `docker run` fired at ~1247 s with `--env-file=/tmp/devcontainer-credentials.env`, but the reaper had deleted the file ~47 s earlier. `--env-file` hard-fails on a missing file.

Lost by 43 seconds. Cached rebuilds finish in seconds, so this only bites on full rebuilds longer than 20 minutes — which is now every cold rebuild of this image.

The irony: the script already knows `--env-file` hard-fails on a missing file — the no-credentials path writes an *empty* file for exactly that reason (`inject-credentials.py:33-38`) — but the reaper uses `rm -f`, recreating the failure it was designed around.

## Why "create the file later" doesn't work

The devcontainer lifecycle has exactly one host-side hook: `initializeCommand`, which always runs **before** the build. Every later hook (`onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`) runs inside the container — after `--env-file` has already been evaluated, and with no access to the macOS keychain anyway. So the file must be created before a step of unbounded duration (the build) and consumed after it. Any fixed timer is structurally a guess.

## Fixes (not yet applied)

1. **Truncate instead of delete** (preferred): change the reaper to `sleep 1200 && : > /tmp/devcontainer-credentials.env`. Secrets still vanish after 20 min, but `--env-file` never hard-fails. Worst case on a slow build: container starts without credentials, which the script already warns about. One-word change.
2. Event-based reaper: poll `docker ps` (or watch `docker events`) for a container with the `devcontainer.local_folder` label and delete once it has started, with the sleep as a fallback ceiling. Secret lifetime becomes "exactly as long as needed," but more moving parts.
3. Raise the timer (e.g. 3600 s): trivial but still a guess; only worth doing alongside fix 1.

Immediate unblock, no code change: rebuild again — the image is now fully cached, so `docker run` fires well inside the 20-minute window.

## Misc observations

- Credentials only pass through `docker run`'s environment; they never persist in the image or config, so modestly extending the host file's lifetime is a small exposure increase.
- Build log also flagged two `LegacyKeyValueFormat` warnings (`ENV key value` → `ENV key=value`, Dockerfile lines 189–190) — same vintage marker as noted in the firewall lineage entry.

Related: `0426T17-devcontainer-secrets.md`, `0715a,firewall-fails-open.md`
