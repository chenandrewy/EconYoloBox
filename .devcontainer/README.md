# Dev Container & Credentials

Both `.devcontainer/` and `.credentials/` are designed to be copied across projects.

This file documents how the pieces work.

## Credentials (`.credentials/`)

Credentials are resolved in three ways, in order:

1. **Environment variable** (an explicit per-command override)
2. **Mounted secret file** (`/run/secrets/credentials.env` inside the container)
3. **Host credential store** (macOS Keychain or Windows Credential Manager)

This means scripts work both inside and outside the container without changes.
Credentials are not placed in the container-wide environment: that would expose
them through Docker metadata and ambiently inherit them into every subprocess.

### Files

- `credentials-map.json` — maps credential store keys to env var names. This is the only file that changes per project.
- `get-credentials.py` — shared module that resolves credentials. Import `get_credential(env_var, keychain_target)` or `get_all_credentials()`.
- `setup.py` — interactive script to save credentials to the host credential store.
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

To update the mounted file after changing credentials, run this command **on the
host**, from the repository root:

```bash
source .devcontainer/find-python.sh
$PYTHON .devcontainer/inject-credentials.py
```

The resolver re-reads the mounted file on every lookup, so updates take effect
immediately, and truncating the file on the host
(`: > /tmp/devcontainer-credentials.env`) immediately revokes the container's
access.

If the host reboots (clearing `/tmp`) and the container is then started without
VS Code (plain `docker start`), Docker recreates the missing mount source as an
empty directory and the container may fail to start. Rerunning the command
above — or just reopening in VS Code, which runs it automatically — repairs
this.

## Dev Container (`.devcontainer/`)

- `inject-credentials.py` — runs on the host before the container starts
  (`initializeCommand`). It writes a `0600` file at
  `/tmp/devcontainer-credentials.env`, bind-mounted read-only at
  `/run/secrets/credentials.env`. The file is not timed: it remains available
  for the container session and is overwritten on the next initialization.
  Because it is host-side, it may remain after the container stops until it is
  overwritten, manually removed, or cleaned up by the host OS.
- `devcontainer.json` — container configuration.
- `Dockerfile` — container image definition.
- `init-firewall.sh` — network firewall rules applied post-create.
- `install-packages.sh` — installs the optional Python and R analysis stacks and
  the AI CLIs into a running container (see "Analysis stacks and AI CLIs" below).
- `shellrc.sh` — interactive shell setup for the container environment, including workspace-local `PATH` additions, aliases, and functions.
- `agents/` — canonical agent guidance and settings, applied to the container's user-level config on every start (see "Agent Config" below).
- `home/` — user-level dotfiles that must survive a rebuild. The container's
  home directory is not a persisted volume, so a file placed at `~` would be
  wiped; these live in the tracked repo instead and are pointed at by
  environment variables exported in `shellrc.sh`. Currently `Rprofile`
  (via `R_PROFILE_USER`).

### Hostname and Claude session names

`write-local-env.sh` captures the host's name as `LOCAL_HOSTNAME` when the
container initializes. The `hostname-local` alias prints that value inside the
container. `cchat-yolo` uses it, without the routine `.local` suffix, to prefix
Claude Code remote-control session names so sessions from different computers
are distinguishable:

```text
MacBook25:My-Project#1
```

Because the name appears in every session, a short one is worth setting.

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

`.devcontainer/agents/` is the single source of truth for agent config and
managed agent policy inside the container:

- `SANDBOX-CLAUDE.md` — canonical agent guidance
- `SANDBOX-AGENTS.md` — symlink to `SANDBOX-CLAUDE.md`; kept separate so Codex-specific guidance can diverge later
- `SANDBOX-claude-settings.json` — canonical user-level Claude Code settings
- `SANDBOX-claude-statusline.sh` — status line script referenced by the settings
- `SANDBOX-claude-managed-settings.json` — system-enforced Claude Code policy, baked to `/etc/claude-code/managed-settings.json`
- `SANDBOX-codex-requirements.toml` — system-enforced Codex Apps and Plugins policy, baked to `/etc/codex/requirements.toml`
- `skills/` — canonical shared Agent Skills, linked into both Claude Code and Codex user-level skill directories
- `seed-agent-guidelines.sh` — applies the user-level guidance and Claude settings on every container start (`postStartCommand`)

The two baked policy files are **not** handled by the seed script. They are
`COPY`ed into the image as root-owned `0444`, so changing either requires a
rebuild — that is what puts them out of reach of an agent running as `node`.
`../.devcontainer/test-agent-policy.sh` verifies they are actually in force.

The seed script handles guidance and settings differently:

- Guidance is **symlinked** (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so edits apply live without a restart.
- Shared skills are **symlinked individually** into `~/.claude/skills/` and
  `~/.agents/skills/`. This keeps one portable source while preserving unrelated
  personal skills in either directory.
- Settings are **copied** to `~/.claude/settings.json`, not symlinked, because Claude Code writes to its settings file (`/config`, `/model`, permission grants). Those writes land in the volume copy and are overwritten by the canonical file on the next container start. To keep a setting permanently, put it in `SANDBOX-claude-settings.json`.

Some user-specific agent settings live in the visible root-level `SANDBOX.toml`.
It contains the research-library location and the timezone agents use for
human-facing timestamps. Relative paths are resolved from the repository root.
Because agents read this file directly, edits take effect without rebuilding or
restarting the container.

### Analysis stacks and AI CLIs (`install-packages.sh`)

The Python and R packages are **not** in the image. A freshly built container
has R, an empty venv, and the system `-dev` libraries until `install-packages.sh`
is run.

The Claude Code and Codex CLIs are runtime-installed too — `install-packages.sh
cli`, or the default `all`. They were a Dockerfile layer pinned to `@latest`,
which turned out to mean "whatever was current the day the layer was first
cached": rebuilds kept restoring a months-old Codex. They now install into
`/usr/local/share/npm-global`, which is a **volume**, so updating Codex in a
running container is no longer reverted by the next rebuild. That is the point
of the change — the CLIs stay where you left them.

Because the volume can start empty, `test-agent-policy.sh` reports `SKIP`
(not `PASS`) for a CLI that is not installed, and interactive shells nudge the
same way they do for a missing analysis stack. The npm-managed CLIs should not
be assumed to self-update; re-run `install-packages.sh cli` to update both to
their current releases.

Python and R re-runs skip what is already installed; the `cli` target requests
`@latest` each time. The script fails loudly if anything in its list is missing
at the end. Interactive shells print a one-line nudge while either stack or CLI
is absent.

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

If detection finds nothing, the fallback is the Dockerfile's `ARG TZ`, which
defaults to `America/New_York`. Note that `TZ` is deliberately **not** set in
`containerEnv`: that becomes `docker run --env`, which outranks `--env-file` and
would override the detected value.
