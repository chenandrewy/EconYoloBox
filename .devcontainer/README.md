# Dev Container & Credentials

Both `.devcontainer/` and `.credentials/` are designed to be copied across projects.

## Credentials (`.credentials/`)

Credentials are resolved in two ways, in order:

1. **Environment variable** (set automatically inside the container)
2. **Host credential store** (macOS Keychain or Windows Credential Manager)

This means scripts work both inside and outside the container without changes.

### Files

- `credentials-map.json` — maps credential store keys to env var names. This is the only file that changes per project.
- `get-credentials.py` — shared module that resolves credentials. Import `get_credential(env_var, keychain_target)` or `get_all_credentials()`.
- `setup.py` — interactive script to save credentials to the host credential store. Run once per machine: `python .credentials/setup.py`
- `check-wrds.py` — validates WRDS credentials and tests the connection.

### Adding credentials to a new project

Edit `credentials-map.json`:

```json
{
  "wrds-username": "WRDS_USERNAME",
  "wrds-password": "WRDS_PASSWORD",
  "mistral-api-key": "MISTRAL_API_KEY"
}
```

Keys are credential store entry names; values are the env var names scripts will use. `setup.py` automatically groups prompts by the first segment of the key (e.g. `wrds-username` and `wrds-password` are grouped under "WRDS").

## Dev Container (`.devcontainer/`)

- `inject-credentials.py` — runs on the host before the container starts (`initializeCommand`). Reads credentials via `get-credentials.py` and writes `/tmp/devcontainer-credentials.env`, which the container picks up via `--env-file`. The file is auto-deleted after 10 minutes.
- `devcontainer.json` — container configuration.
- `Dockerfile` — container image definition.
- `init-firewall.sh` — network firewall rules applied post-create.
- `aliases.sh` — shell aliases for the container environment.

### Persistent auth state

The template mounts persistent volumes for:

- `/home/node/.claude` — Claude auth and config
- `/home/node/.codex` — Codex auth and config
- `/home/node/.config/gh` — GitHub CLI auth and config

This keeps interactive login state across container rebuilds and restarts.

### Dockerfile ordering

Keep the Dockerfile ordered for cache efficiency as well as readability.

- Put expensive, stable layers early
- Put frequently edited or convenience-oriented layers later
- Avoid small package additions near the top of the file when they would force rebuilds of expensive downstream layers

In practice, large system installs, source builds, and language package installs should be placed so minor template tweaks do not invalidate more of the image cache than necessary.

### Timezone

The container defaults to `America/New_York`. To override, set the `TZ` environment variable on your host before building:

```bash
export TZ=America/Chicago
```

The container picks up `TZ` from your host via `${localEnv:TZ}` and falls back to `America/New_York` if unset.
