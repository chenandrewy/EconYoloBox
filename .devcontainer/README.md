# Dev Container & Credentials

Both `.devcontainer/` and `.credentials/` are designed to be copied across projects.

This file documents how the pieces work.

## Credentials (`.credentials/`)

Credentials are resolved in two ways, in order:

1. **Environment variable.** In the container, Docker sets every credential in
   the environment at creation (`--env-file`, below); a variable set for one
   command still overrides it.
2. **Host credential store** (macOS Keychain or Windows Credential Manager),
   which is how scripts on the host find them.

This means scripts work both inside and outside the container without changes.
The costs of the environment are accepted (docs/journal/0927a): the values
appear in `docker inspect` on the host and persist in Docker's container
metadata, every process in the container inherits them, and they are fixed at
creation.

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

After changing credentials on the host, recreate the containers
(`bbox --rebuild`, and `bbox --rebuild --normie` if you use normie mode):
`initializeCommand` rewrites the env file from the host store, and Docker
reads it only when it creates a container. Revoking access likewise means
recreating them; emptying the file no longer does it.

## Dev Container (`.devcontainer/`)

`.devcontainer/` is the container itself: its definition, its startup, and the
tools baked into it. `.host/` is the launcher (`bbox`), and
[`.setup/`](../.setup/README.md) is provisioning you run by hand, in the
container: the package volumes and the AI CLIs.

### TeX Live and LyX

TeX Live 2026 is installed with `bash .setup/install-base.sh tex` in the
container, **in normie mode**, using upstream `install-tl`. It is minimal and pdfLaTeX-only. The base is
`scheme-small` without XeTeX, plus bibtexextra (biblatex, biber), latexindent,
latexmk and cm-super; `install-optional.sh` adds latexextra, fontsrecommended,
pictures, mathscience and fontsextra. It has no documentation files. It lives
in the shared `texlive-2026-base-noble` volume at `/usr/local/texlive`. The
image puts the matching architecture's binaries on PATH; user TeX caches live
in the writable home directory. Packages are added with `tlmgr install` in
normie mode, or by listing them in `TEX_PKGS` and rerunning the builder;
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
  `/tmp/devcontainer-credentials.env`, which `runArgs` passes as `--env-file`,
  so a new container gets the credentials as environment variables. It is
  overwritten on the next initialization, and may remain on the host until
  then or until the host OS cleans `/tmp`.
- `devcontainer.json` — container configuration, YOLO mode.
  `normie/devcontainer.json` is its twin for normie mode; they differ only in
  the posture and the name, which `tests/test_config_twins.py` enforces.
- `check-checkout.sh` — refuses a second checkout with the same folder name,
  whose containers would share this one's volumes (run by `post-start.sh`).
- `Dockerfile` — container image definition.
- `check-yolo-boundaries.sh` — refuses supplied YOLO launchers unless the
  firewall is enabled and PID 1 has filtered seccomp.
- `init-firewall.sh` — network firewall rules applied by `post-start.sh` when enabled.
- `posture.sh` — reports the container's posture (`yolo`, `normie` or
  `custom`) from the container itself; `package-mode.sh` reports how the
  package volumes are mounted.
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

Docker's outer seccomp policy is part of each mode's config: `builtin` in the
YOLO container (the default), `unconfined` in the normie container
(`bbcode --normie`). Codex's sandboxed modes need `unconfined`,
because builtin seccomp blocks Bubblewrap setup here and
automatic review did not provide reliable recovery for all native tools.
Validation after container recreation is still required; the mode alone is
not evidence that the inner sandbox works.

`unconfined` removes Docker's outer syscall filter for every container process,
including Claude, YOLO sessions, and commands approved to run outside Codex's
sandbox. A working Codex sandbox does not restore that outer protection for
other processes. `posture.sh` reads container PID 1's live `/proc` mode, and
every interactive shell outside YOLO mode says so. Filtered mode is only a
runtime mode check, not proof of Docker's exact builtin profile.
See [Docker's seccomp documentation](https://docs.docker.com/engine/security/seccomp/).

Changing mode means using the other container, not changing this one; each
keeps its seccomp policy for life. `bbox` inspects the exact container
returned by `devcontainer up` and stops before attachment if its posture is
not its config's. VS Code's **Rebuild Container** rebuilds from the window's
config, so it keeps the mode.

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
controls. The YOLO container, with builtin, is expected to show the observed
namespace failure until compatibility is addressed.

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
Both modes' containers mount the same volumes, so one login serves both.

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

User-specific settings live in the root-level `SANDBOX.toml`: `timezone`
(IANA zone; comment out to use the detected host zone), `cellar` (the research
library), `done` (finished and retired projects), and `screenshot_directory`. Paths are container paths. Agents read path settings
directly, so path edits take effect immediately.
`timezone` becomes `TZ` at create time, so it needs a
rebuild. Settings are read with `sandbox-setting.sh`, a `sed` over flat `key = "value"`
/ `key = true|false` lines rather than a TOML parser.

### Working modes

The security posture is not in `SANDBOX.toml`. Each mode is its own
container, built from its own config file, which hard-codes the posture:

| Mode | Config | Launch | Internet | Package volumes | Seccomp | Use |
|---|---|---|---|---|---|---|
| YOLO mode (default) | `devcontainer.json` | `bbcode`, `bbe` | firewalled | read-only | `builtin` | everyday work; YOLO launchers allowed; agents ask when a package is missing |
| Normie mode | `normie/devcontainer.json` | `bbcode --normie`, `bbe --normie` | open | writable | `unconfined` | supervised work, like the Mac: open web, package installs, agents in approval modes |

Normie mode needs `unconfined` because Codex's approval modes run commands in
Bubblewrap, which builtin seccomp blocks (see
[Codex sandbox modes](#codex-sandbox-modes-and-launchers)). There are only the
two presets; `post-start.sh` reports any other combination (a container made
before the per-mode configs, say) as a custom posture.

The config sets seccomp in `runArgs`, `readonly` on the three package mounts,
and `SANDBOX_INTERNET` in `containerEnv` (read by `post-start.sh` at every
start; anything but `open` arms the firewall). All three are fixed at
creation. The Dev Containers tooling keys a container on its folder and config
file, so the two containers coexist, and whatever recreates one, `bbox` or VS
Code's own Rebuild or Reopen, recreates it from the same config, in the same
mode. Neither container ever replaces the other: switching modes is attaching
to the other one. A normie container runs, firewall open, until it is stopped
(`bbox --stop --normie`); `bbox --status` lists both, and every YOLO
bring-up mentions a running normie one. Why two files and not one with a
switch: docs/journal/0927a.

The two containers share every volume. The package volumes are shared by
design: normie writes what YOLO then runs read-only (a running R or Python
session sees new packages after a restart). The per-checkout volumes, which
hold `~/.claude`, `~/.codex`, the AI CLIs and shell history, are named for the
checkout's folder name alone, not `${devcontainerId}` (which depends on the
config file and would give each mode its own). So one login and one CLI
install serve both modes, and **each checkout's folder name must be unique on
the Docker daemon**: a second checkout with the same name would share the
Claude and Codex tokens and the CLIs themselves. `check-checkout.sh` enforces
this at every start: it records the host folder in `~/.claude` the first
time and refuses a different one, with the command to accept a deliberate
move.

The mode stays visible: `post-start.sh` prints it at every start; outside YOLO
mode (in the normie container) every interactive shell prints a warning banner
spelling out the loosened boundaries, the zsh prompt and Claude's status line
lead with a `normie` (or `custom`) tag, and the VS Code window title starts
with `normie:`, set by `window.title` in `normie/devcontainer.json`.

In normie mode, install as `node` with the ordinary commands:
`install.packages()` writes to the shared site library, `pip install` to
`/opt/venv`, and `tlmgr install` to the TeX tree (then run `tex-refresh`).
The image seeds the volumes `node`-owned, so no sudo is needed. pip
resolves against current PyPI and can replace dependencies, one reason the mode
is supervised. Agents install in normie mode only when the user asks.
`.setup/install-base.sh` installs the base this way, and
`.setup/install-optional.sh` the optional set;
`install-optional.sh --verify` and `tests/test-optional.sh` check it in any
mode.

### Package stacks and AI CLIs (`.setup/install-base.sh`)

The R, Python and TeX stacks live in three shared Docker volumes. The image
carries a copy of the lean base only to seed them: its build runs
`install-base.sh --image-build`, and Docker copies the image's directory into
each volume the first time an empty one is mounted (docs/journal/0926f). After
that the human changes the base in normie mode with
`bash .setup/install-base.sh` (see the [setup README](../.setup/README.md)),
and optionally adds the rest with `.setup/install-optional.sh`.
The YOLO container mounts them read-only and the normie container writable:

| Volume | Mount |
|---|---|
| `r-site-library-noble-4.5.3-2026-07-15-base` | `/opt/R/4.5.3/lib/R/site-library` |
| `venv-noble-py3.12-base` | `/opt/venv` |
| `texlive-2026-base-noble` | `/usr/local/texlive` |

The principle is that agents in the container only execute; the human maintains
the environment, watching in normie mode (docs/journal/0921a, 0926e). In the
default read-only mode, `install-base.sh python|r|tex` refuses and says how to
switch, and
`install-base.sh --verify python r tex` checks the base without writing.
`pip install` and `install.packages()` into the stacks fail with a read-only or
not-writable error. At startup, `post-start.sh` warns if a volume is not built.
It tests a sentinel package (`pyfixest`, `fixest`, the TeX marker), because
a volume created by an older image holds only the skeleton it was seeded
with. Interactive shells print a one-line note as well.

The volumes are shared by every project on the Docker daemon, and they are
built in this workspace's own devcontainer. R packages link against the
image's libraries and install from the dated P3M snapshot in `Rprofile.site`.
System dependencies that need root (`gfortran`, `libcurl4-openssl-dev`,
`libxml2-dev`, `libpq-dev`, `libsecret-1-dev`, freetype/harfbuzz/fribidi,
`cmake`) stay in the Dockerfile. After a snapshot or interpreter bump, give
the volume a new name, rebuild the container in normie mode, then fill it.

The Claude Code and Codex CLIs are part of the base, installed into a writable
per-container volume by the same script, `bash .setup/install-base.sh cli`,
which works in any mode. `post-start.sh` runs it at startup while either CLI
is missing, so a fresh volume fills itself. They were a Dockerfile layer pinned to
`@latest`, which turned out to mean "whatever was current the day the layer
was first cached": rebuilds kept restoring a months-old Codex. They now install
into `/usr/local/share/npm-global`, which is a **volume**, so updating Codex in
a running container is no longer reverted by the next rebuild.

Because the install at startup can fail, `test-agent-policy.sh` reports `SKIP`
(not `PASS`) for a CLI that is not installed, and interactive shells nudge
while either CLI is missing. The npm-managed CLIs should not be assumed to
self-update; re-run `install-base.sh cli` to update both to their current
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
