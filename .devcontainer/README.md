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

`.devcontainer/` defines the container, `.host/` is session navigation, and
[`.setup/`](../.setup/README.md) is host machine setup and maintenance.

### TeX Live and LyX

TeX Live 2026 is installed with `bash .setup/packages.sh tex` **on the host**,
using upstream `install-tl`. It is minimal and pdfLaTeX-only. The base is
`scheme-small` without XeTeX, plus bibtexextra (biblatex, biber), latexindent,
latexmk and cm-super; `install-optional.sh` adds latexextra, fontsrecommended,
pictures, mathscience and fontsextra. It has no documentation files. It lives
in the shared `texlive-2026-base-noble` volume at `/usr/local/texlive`. The
image puts the matching architecture's binaries on PATH; user TeX caches live
in the writable home directory. Packages are added with `tlmgr install` in
install mode, or by listing them in `TEX_PKGS` and rerunning the builder;
existing packages are never updated in place.

`tex-refresh` runs LyX converter detection as `node` in `~/.lyx` at startup,
after the firewall configuration step. A missing installation warns without
preventing other container use. If TeX is installed after startup, run
`tex-refresh` manually in each consumer and reopen any already-running LyX.
The user configuration is not persisted across container recreation, so it
is regenerated at startup. Custom LyX `-userdir` locations are not managed by
this helper. See the host setup README for installation and failure handling.

### Configuration files

- `inject-credentials.py` — runs on the host before the container starts
  (`initializeCommand`). It writes a `0600` file at
  `/tmp/devcontainer-credentials.env`, bind-mounted read-only at
  `/run/secrets/credentials.env`. The file is not timed: it remains available
  for the container session and is overwritten on the next initialization.
  Because it is host-side, it may remain after the container stops until it is
  overwritten, manually removed, or cleaned up by the host OS.
- `devcontainer.json` — container configuration.
- `Dockerfile` — container image definition.
- `check-yolo-boundaries.sh` — refuses supplied YOLO launchers unless the
  firewall is enabled and PID 1 has filtered seccomp.
- `init-firewall.sh` — network firewall rules applied by `post-start.sh` when enabled.
- `install-packages.sh` — the base package lists and installer for the R,
  Python and TeX volumes (run on the host through `.setup/packages.sh`), and
  the AI CLI installer inside the container (see "Package stacks and AI CLIs"
  below).
- `install-optional.sh` — the optional package set, installed by the user in
  install mode (see "Working modes" below).
- `strict-setting.sh`, with its wrappers `seccomp-setting.sh` and
  `packages-setting.sh` — strict readers for SANDBOX.toml's enumerated
  switches; `package-mode.sh` reports how the package volumes are mounted.
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

### Codex sandbox modes and launchers

Docker's outer seccomp policy is selected in root-level `SANDBOX.toml`:

```toml
seccomp = "unconfined" # or "builtin"
```

`unconfined` is the chosen configuration
because builtin seccomp blocks Bubblewrap setup here and
automatic review did not provide reliable recovery for all native tools.
Validation after container recreation is still required; this setting alone is
not evidence that the inner sandbox works.

`unconfined` removes Docker's outer syscall filter for every container process,
including Claude, YOLO sessions, and commands approved to run outside Codex's
sandbox. A working Codex sandbox does not restore that outer protection for
other processes. Every interactive shell rereads the setting and compares it
with container PID 1's live `/proc` mode. It always displays **Warning: Seccomp
Unconfined** when PID 1 is unfiltered, even when that matches the setting.
It also warns on a mismatch, invalid
configuration, or an unverifiable mode. Filtered mode is only a runtime mode
check, not proof of Docker's exact builtin profile.
See [Docker's seccomp documentation](https://docs.docker.com/engine/security/seccomp/).

Changing this setting requires **container recreation** with `bbox --rebuild`
on the host, not an image change. A plain restart or plain `bbox` does not apply
it. Direct VS Code creation uses `builtin`, matching the checked-in YOLO
posture, but does not read this setting. Reuse the existing image when
recreating; named volumes and the bind-mounted workspace persist, but files
only in the old container's writable layer do not.

`bbox` inspects the exact container returned by `devcontainer up`. Reuse warns
about a mismatch and continues; explicit recreation stops before attachment if
the policy cannot be verified. VS Code's direct **Rebuild Container** path does
not inherit the launcher's validated environment and defaults to `builtin`.
Use `bbox --rebuild --code` when applying `seccomp = "unconfined"`.

Codex separates the sandbox (filesystem and network limits), approval policy
(when approval is requested), and reviewer (a person or automatic review).
"Approve for me" selects automatic review of eligible escalation requests; it
does not replace the sandbox or grant network access by itself.

Workspace-write disables command networking by default. Bubblewrap can enforce
that through a separate network namespace (`--unshare-net`), but it can also
preserve networking while restricting filesystem access. To enable command
networking in a working workspace-write sandbox, Codex supports:

```toml
[sandbox_workspace_write]
network_access = true
```

The container firewall is a separate outer restriction. Lowering it does not
enable networking inside a sandbox whose policy keeps it off. Enabling sandbox
networking does not necessarily resolve bubblewrap's namespace setup failure.

Use standard `codex` for everyday work. Select a model with `/model` or
`codex --model <model>`; separate chat and mini wrappers are unnecessary.

A bare `codex` defaults to requesting sandboxing: `/etc/codex/config.toml` (from
`agents/SANDBOX-codex-config.toml`) sets `approval_policy`/`sandbox_mode` to the
on-request/workspace-write defaults. User configuration can override them.
These two settings alone do not select automatic review.

We recommend "Approve for me". Set the following at the top level of your
`~/.codex/config.toml`, before any table headers (update existing keys rather
than adding duplicates):

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"
approvals_reviewer = "auto_review"
```

Then launch `codex` normally. Automatic review remains a user preference; the
container does not enforce it or rewrite your user config. For a single session,
use `codex --approve-for-me` (available in the inspected CLI 0.154.0).

The explicit `gptchat-yolo` / `gptmini-yolo` wrappers remain in `shellrc.sh`.
They use `--dangerously-bypass-approvals-and-sandbox`. Along with `cchat-yolo`,
they refuse to start unless the firewall is enabled and PID 1 reports filtered
seccomp mode. The runtime mode proves that a filter is active, not that it is
Docker's exact builtin profile. Standard `codex` remains available in an
unconfined container, subject to the sandbox compatibility and approval limits
below.

**Sandbox compatibility.** With builtin seccomp active, ordinary commands and
the native `apply_patch` helper failed during Bubblewrap namespace creation.
Shell escalation could recover, and invoking the installed patch helper by its
absolute path through an escalated shell worked in one session. The native
editing tool still failed. These tool-specific recovery paths are not a reliable
substitute for a working sandbox; this prompted the switch to unconfined.

**Validation after recreation.** Run these harmless probes as `node`:

```bash
bwrap --unshare-user --ro-bind / / /bin/true
codex sandbox /bin/true
```

Then start a normal Codex workspace-write session and verify:

- An ordinary shell command runs without namespace errors or escalation.
- The native `apply_patch` tool can create, edit, and remove a disposable file
  inside the workspace without an escalated shell fallback.
- A workspace write succeeds, while a write to a disposable, user-owned test
  location outside all writable roots is denied without escalation. Verify the
  location is writable by `node` outside the sandbox so the check tests sandbox
  enforcement rather than ordinary Unix permissions.
- Command networking matches the chosen policy: default workspace-write stays
  offline; explicitly enabled networking can reach an intended public endpoint,
  subject to the container firewall if enabled.

Record the results before calling the compatibility fix validated. If a check
fails, inspect that failure before adding capabilities or relaxing other
controls. Re-enabling builtin requires another recreation and is expected to
restore the observed namespace failure until compatibility is addressed.

Commands executed outside the inner sandbox retain Docker's restrictions but
have the container user's filesystem and network access. With the firewall
down, that includes outbound internet access. Live workspace files and accessible
credentials remain exposed to those commands. Automatic review is a safeguard,
not an OS-level restriction on every operation of an approved subprocess.

See the [September 17 reassessment](../docs/journal/0917c,bwrap-auto-review-friction.md),
which supersedes the builtin recommendation in `0917a`, and OpenAI's
[auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review) and
[network settings](https://learn.chatgpt.com/docs/agent-approvals-security#network-access)
documentation.

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
- `SANDBOX-codex-config.toml` — stable Codex defaults, baked to `/etc/codex/config.toml`
- `SANDBOX-codex-requirements.toml` — system-enforced Codex Apps and Plugins policy, baked to `/etc/codex/requirements.toml`
- `skills/` — canonical shared Agent Skills, linked into both Claude Code and Codex user-level skill directories
- `seed-agent-guidelines.sh` — applies the user-level guidance and Claude settings on every container start (`postStartCommand`)

The three baked system files are **not** handled by the seed script. They are
`COPY`ed into the image as root-owned `0444`, so changing one requires a
rebuild. The Codex system config provides stable, user-overridable defaults;
the two policy files enforce settings that user config cannot override.
`../.devcontainer/test-agent-policy.sh` verifies that the default is installed
and that the policies are actually in force.

The seed script handles guidance and settings differently:

- Guidance is **symlinked** (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so edits apply live without a restart.
- Shared skills are **symlinked individually** into `~/.claude/skills/` and
  `~/.agents/skills/`. This keeps one portable source while preserving unrelated
  personal skills in either directory.
- Settings are **copied** to `~/.claude/settings.json`, not symlinked, because Claude Code writes to its settings file (`/config`, `/model`, permission grants). Those writes land in the volume copy and are overwritten by the canonical file on the next container start. To keep a setting permanently, put it in `SANDBOX-claude-settings.json`.
- Codex's `~/.codex/config.toml` remains node-owned and volatile because it
  mixes model choices, project trust, and other runtime state. Stable defaults
  belong in `SANDBOX-codex-config.toml`; user config has higher precedence.

User-specific settings live in the root-level `SANDBOX.toml`: `seccomp`
(`"builtin"` or `"unconfined"`), `internet` (`"firewalled"` or `"open"`), `packages`
(`"readonly"` or `"writable"`), `timezone`
(IANA zone; comment out to use the detected host zone), `cellar` (the research
library), `done` (finished and retired projects), and `screenshot_directory`. Paths are container paths. Agents read path settings
directly, so path edits take effect immediately.
`internet` is read by `post-start.sh` at every container start (stop + reopen
or Rebuild Container); `timezone` becomes `TZ` at create time, so it needs a
rebuild. General settings use `sandbox-setting.sh`, a `sed` over flat `key = "value"`
/ `key = true|false` lines rather than a TOML parser. Internet, seccomp, and
packages use the stricter shared `strict-setting.sh` through their respective
setting scripts. It rejects tables, duplicate keys, malformed lines, and
unsupported TOML; an invalid internet value selects `"firewalled"`.
Seccomp and packages fall back to `builtin` and `readonly`. They are fixed at
container creation, so they take `bbox --rebuild`.

The checked-in default is `internet = "firewalled"`: the YOLO posture, with the
allowlist active and the YOLO wrappers permitted. Set `internet = "open"` for
internet access and use Claude's auto mode; the internet switch does not
configure either agent's approval mode. Apply changes through Dev Containers:
editing the file does not change live rules, and a bare `docker restart` skips
the startup hook. The seccomp choice is independent of either firewall mode;
enabling the firewall does not restore syscall filtering.

### Working modes

Two independent switches in `SANDBOX.toml`, `internet` and `packages`, give
three working modes (docs/journal/0926a):

| Mode | `internet` | `packages` | Use |
|---|---|---|---|
| 1. YOLO work (default) | `"firewalled"` | `"readonly"` | everyday work; agents ask when a package is missing |
| 2. Chaperoned internet work | `"open"` | `"readonly"` | open web access, with the user watching |
| 3. Careful package installs | `"open"` | `"writable"` | the user installs packages, then switches back |

Changing `internet` takes a container restart; changing `packages` takes
`bbox --rebuild`, because mounts are fixed at container creation (a rebuild
from the cached image is quick). `bbox` exports `SANDBOX_PKG_READONLY` for the
three package mounts in `devcontainer.json` and checks the created container's
mounts, as it does for seccomp. A container created without `bbox`, for example
by VS Code directly, mounts them read-only. `post-start.sh` prints the current
mode, and interactive shells warn while the volumes are writable.

In mode 3, install as `node` with the ordinary commands: `install.packages()`
writes to the shared site library, `pip install` to `/opt/venv`, and
`tlmgr install` to the TeX tree (then run `tex-refresh`). `.setup/packages.sh`
chowns the volumes to `node` so no sudo is needed. pip resolves against current
PyPI and can replace dependencies, one reason the mode is supervised. Agents
install in mode 3 only when the user asks. `install-optional.sh` installs the
optional set this way; `install-optional.sh --verify` and
`tests/test-optional.sh` check it in any mode.

### Package stacks and AI CLIs (`install-packages.sh`)

The R, Python and TeX stacks are **not** in the image. They live in three
shared Docker volumes. The human builds a lean base on the host with
`bash .setup/packages.sh` (see the [host setup README](../.setup/README.md)),
and optionally adds the rest in mode 3 with `install-optional.sh`.
`devcontainer.json` mounts them read-only unless `packages = "writable"`:

| Volume | Mount |
|---|---|
| `r-site-library-noble-4.5.3-2026-07-15-base` | `/opt/R/4.5.3/lib/R/site-library` |
| `venv-noble-py3.12-base` | `/opt/venv` |
| `texlive-2026-base-noble` | `/usr/local/texlive` |

The principle is that agents in the container only execute; the human maintains
the environment (docs/journal/0921a). In the default read-only mode,
`install-packages.sh python|r|tex` refuses with the host command, and
`install-packages.sh --verify python r tex` checks the base without writing.
`pip install` and `install.packages()` into the stacks fail with a read-only or
not-writable error. At startup, `post-start.sh` warns if a volume is not built.
It tests a sentinel package (`pyfixest`, `fixest`, the TeX marker), because
Docker seeds even a fresh read-only volume from the image, so an unbuilt venv
still shows its skeleton. Interactive shells print a one-line note as well.

The volumes are shared by every project on the Docker daemon, and they are
built by this workspace's own devcontainer image. R packages link against the
image's libraries and install from the dated P3M snapshot in `Rprofile.site`.
System dependencies that need root (`gfortran`, `libcurl4-openssl-dev`,
`libxml2-dev`, `libpq-dev`, `libsecret-1-dev`, freetype/harfbuzz/fribidi,
`cmake`) stay in the Dockerfile. After a snapshot or interpreter bump, rebuild
the container first, then build a new volume under a new name.

The Claude Code and Codex CLIs are runtime-installed into a writable
per-container volume with `install-packages.sh cli`, which is also what the
script does with no arguments. They were a Dockerfile layer pinned to
`@latest`, which turned out to mean "whatever was current the day the layer
was first cached": rebuilds kept restoring a months-old Codex. They now install
into `/usr/local/share/npm-global`, which is a **volume**, so updating Codex in
a running container is no longer reverted by the next rebuild.

Because the volume can start empty, `test-agent-policy.sh` reports `SKIP`
(not `PASS`) for a CLI that is not installed, and interactive shells nudge
while either CLI is missing. The npm-managed CLIs should not be assumed to
self-update; re-run `install-packages.sh cli` to update both to their current
releases.

`tests/test-packages.sh`, run as `node` in a rebuilt container, is the
acceptance check for the base. It covers mounts that match `packages`, the
declared base stacks, every installed R package loading, a `fixest`
regression, refused installs of absent packages (read-only mode), and pdflatex,
biber, latexindent, latexmk and LyX export. It passes without the optional
set; `tests/test-optional.sh` checks that set separately.

### Dockerfile ordering

Keep the Dockerfile ordered for cache efficiency as well as readability.

- Put expensive, stable layers early
- Put frequently edited or convenience-oriented layers later
- Avoid small package additions near the top of the file when they would force rebuilds of expensive downstream layers

In practice, large system installs, source builds, and language package installs should be placed so minor template tweaks do not invalidate more of the image cache than necessary.

### Timezone

`SANDBOX.toml`'s `timezone` wins if set. Otherwise the container matches your
host's timezone: `write-local-env.sh` detects it at `initializeCommand` time —
`$TZ` if exported, else `timedatectl`,
else the target of the `/etc/localtime` symlink (which is how macOS and desktop
Linux actually record it) — and passes it in via `--env-file`.

If detection finds nothing, the fallback is the Dockerfile's `ARG TZ`, which
defaults to `America/New_York`. Note that `TZ` is deliberately **not** set in
`containerEnv`: that becomes `docker run --env`, which outranks `--env-file` and
would override the detected value.
