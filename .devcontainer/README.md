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
- `install-packages.sh` — installs the optional Python and R analysis stacks into
  a running container (see "Analysis stacks" below).
- `shellrc.sh` — interactive shell setup for the container environment, including workspace-local `PATH` additions, aliases, and functions.
- `agents/` — canonical agent guidance and settings, applied to the container's user-level config on every start (see "Agent Config" below).

### Persistent auth state

The template mounts persistent volumes for:

- `/home/node/.claude` — Claude auth and config
- `/home/node/.codex` — Codex auth and config

This keeps interactive login state across container rebuilds and restarts.

GitHub auth is different: nothing is persisted in a volume, but VS Code's Dev
Containers extension forwards the host's Git credentials on demand (its default,
written into the root-owned system gitconfig). That forwarding is left on
deliberately — it is what lets work in here push branches and open PRs. Note the
capability is not a licence: pushing still gets asked about first.

To turn it off, the only effective switch is on the host, not in this repo — the
helper is injected per session by the VS Code client, so no rebuild can remove
it:

```json
"dev.containers.gitCredentialHelperConfigLocation": "none"
```

### Agent Config (`agents/`)

`.devcontainer/agents/` is the single source of truth for user-level agent config inside the container:

- `SANDBOX-CLAUDE.md` — canonical agent guidance
- `SANDBOX-AGENTS.md` — symlink to `SANDBOX-CLAUDE.md`; kept separate so Codex-specific guidance can diverge later
- `SANDBOX-claude-settings.json` — canonical user-level Claude Code settings
- `SANDBOX-claude-statusline.sh` — status line script referenced by the settings
- `seed-agent-guidelines.sh` — applies all of the above on every container start (`postStartCommand`)

The seed script handles guidance and settings differently:

- Guidance is **symlinked** (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so edits apply live without a restart.
- Settings are **copied** to `~/.claude/settings.json`, not symlinked, because Claude Code writes to its settings file (`/config`, `/model`, permission grants). Those writes land in the volume copy and are overwritten by the canonical file on the next container start. To keep a setting permanently, put it in `SANDBOX-claude-settings.json`.

### Analysis stacks (`install-packages.sh`)

The Python and R packages are **not** in the image. A freshly built container
has R, an empty venv, and the system `-dev` libraries; the stacks go in with:

```bash
.devcontainer/install-packages.sh          # both, a few minutes
.devcontainer/install-packages.sh python   # or one at a time
.devcontainer/install-packages.sh r
.devcontainer/install-packages.sh --force  # reinstall even if present
```

Re-runs skip what is already installed, and the script fails loudly if anything
in its list is missing at the end. Interactive shells print a one-line nudge
while either stack is absent.

Why not Dockerfile layers: baked-in packages made every change to the stack a
full rebuild, and a broken package unrecoverable without one. As a script, the
stack is editable and re-runnable in place — which is also what makes the
single shared library (no user-level layering) defensible.

The trade-off is state, not versions. R still resolves against the dated P3M
snapshot pinned in `Rprofile.site`, and system dependencies needing root
(`gfortran`, `libcurl4-openssl-dev`, `libxml2-dev`, `libpq-dev`,
`libsecret-1-dev`, freetype/harfbuzz/fribidi, `cmake`) stay in the Dockerfile.
What changes is that the stack costs minutes per container instead of being a
cached image layer.

Note that `docker build` runs with the **network open** while the firewall only
exists at runtime, so a command working in the Dockerfile is no evidence it
works in a started container. Moving installs to runtime puts them behind the
allowlist — which is why `rspm-sync.rstudio.com` (P3M's payload host) and
`cran.r-project.org` (archived sources) had to be added to `init-firewall.sh`.
Expect further redirect hosts to surface; they cannot be enumerated in advance.

### Dockerfile ordering

Keep the Dockerfile ordered for cache efficiency as well as readability.

- Put expensive, stable layers early
- Put frequently edited or convenience-oriented layers later
- Avoid small package additions near the top of the file when they would force rebuilds of expensive downstream layers

In practice, large system installs, source builds, and language package installs should be placed so minor template tweaks do not invalidate more of the image cache than necessary.

### Timezone

The container matches your host's timezone automatically. `write-local-env.sh`
detects it at `initializeCommand` time — `$TZ` if exported, else `timedatectl`,
else the target of the `/etc/localtime` symlink (which is how macOS and desktop
Linux actually record it) — and passes it in via `--env-file`.

To force a specific zone instead, export it on the host before the container
starts:

```bash
export TZ=America/Chicago
```

If detection finds nothing, the fallback is the Dockerfile's `ARG TZ`, which
defaults to `America/New_York`. Note that `TZ` is deliberately **not** set in
`containerEnv`: that becomes `docker run --env`, which outranks `--env-file` and
would override the detected value.
