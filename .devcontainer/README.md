# Dev Container & Credentials

`.devcontainer/` holds the environment implementation, including host launchers,
provisioning, and tests. User-maintained agent configuration and credential
management stay visible at the repository root in `agents/` and `credentials/`.
Copy these directories together when adapting the environment to another project.

This file documents how the pieces work.

## Credentials (`credentials/`)

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
(`yolobox --rebuild`, which recreates both modes' containers):
`initializeCommand` rewrites the env file from the host store, and Docker
reads it only when it creates a container. Revoking access likewise means
recreating them; emptying the file no longer does it.

## Dev Container (`.devcontainer/`)

`.devcontainer/` is the container itself: its definition, its startup, and the
tools baked into it. `.devcontainer/host/` is the launcher (`yolobox`), and
[`.devcontainer/setup/`](setup/README.md) is provisioning you run by hand, in the
container: the package volumes and the AI CLIs.

The checkout mounts at `/yolobox` inside both containers. The host checkout
folder can keep its existing name. When changing an existing installation from
the former `/sandbox` mount, close attached VS Code windows and run
`yolobox --rebuild` on the host. The launcher recreates both modes if both exist;
an old container cannot be reused with the new working directory. Open a fresh
shell afterward so `sesh-init` can update the home-directory session links.
Stored session transcripts may still mention the old path as historical data.

### Updating an existing checkout after the directory reorganization

Host support and provisioning moved from `infra/` into `host/` and `setup/`
inside `.devcontainer/`; credential management moved to root `credentials/`.
From the checkout root on the host, rerun `bash .devcontainer/host/setup.sh`,
then open a new shell (or run `exec zsh`) to load the new launcher registration.
Setup migrates earlier registrations while preserving unrelated shell settings.
Run `yolobox --rebuild` to recreate the containers with the updated initialization
commands and image scripts. Existing package and authentication volumes are kept.

### TeX Live and LyX

TeX Live 2026 is installed with `bash .devcontainer/setup/install-base.sh tex` in the
container, **in normie mode**, using upstream `install-tl`. It is minimal and pdfLaTeX-only. The base is
`scheme-small` without XeTeX, plus bibtexextra (biblatex, biber), latexindent,
latexmk and cm-super; `install-optional.sh` adds latexextra, fontsrecommended,
pictures, mathscience and fontsextra. It has no documentation files. It lives
in the shared `texlive-2026-base-noble` volume at `/usr/local/texlive`. The
image puts the matching architecture's binaries on PATH; user TeX caches live
in the writable home directory. Packages are added with `tlmgr install` in
normie mode, or by listing them in `TEX_PKGS` and rerunning the builder;
existing packages are never updated in place.

`tex-refresh` runs LyX converter detection as `ubuntu` in `~/.lyx` at startup,
after the firewall configuration step. A missing installation warns without
preventing other container use. If TeX is installed after startup, run
`tex-refresh` manually in each consumer and reopen any already-running LyX.
The user configuration is not persisted across container recreation, so it
is regenerated at startup. Custom LyX `-userdir` locations are not managed by
this helper. See the [package setup README](setup/README.md) for installation and failure handling.

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
- `posture.sh` — reports the declared container mode (`yolo` or `normie`)
  after checking live internet and seccomp state; `custom` flags a mismatch.
  Its `package_access` field comes from `package-mode.sh` and describes the
  mounts visible to the calling process.
- `shellrc.sh` — interactive shell setup for the container environment, including workspace-local `PATH` additions, aliases, and functions.
- `home/` — user-level dotfiles that must survive a rebuild. The container's
  home directory is not a persisted volume, so a file placed at `~` would be
  wiped; these live in the tracked repo instead and are pointed at by
  environment variables exported in `shellrc.sh`. Currently `Rprofile`
  (via `R_PROFILE_USER`).

### Hostname and Claude session names

`host/write-local-env.sh` captures the host's name as `LOCAL_HOSTNAME` when the
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
(`nbcode`). Codex's sandboxed modes need `unconfined`,
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
keeps its seccomp policy for life. `yolobox` inspects the exact container
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

A bare `codex` requests "Approve for me": `/etc/codex/config.toml` (from
`agents/managed/YOLOBOX-codex-config.toml`) sets `approval_policy = "on-request"`,
`sandbox_mode = "workspace-write"`, and `approvals_reviewer = "auto_review"`.
User configuration can override these defaults. The container does not rewrite
your user config. For a single session, use `codex --approve-for-me` (available
in the inspected CLI 0.154.0).

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

**Validation after recreation.** Run these harmless probes as `ubuntu`:

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
  location is writable by `ubuntu` outside the sandbox so the check tests sandbox
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

- `/home/ubuntu/.claude` — Claude auth and config
- `/home/ubuntu/.codex` — Codex auth and config

This keeps interactive login state across container rebuilds and restarts.
Both modes' containers mount the same volumes, so one login serves both.

VS Code extensions live in one per-checkout volume mounted at
`/home/ubuntu/.vscode-server/extensions`. Normie mounts it writable; YOLO
mounts it read-only. Neither config asks VS Code to install extensions on
attach. For a fresh volume, attach to normie first and run
`bash .devcontainer/setup/install-vscode-extensions.sh` in its integrated
terminal. This invokes VS Code's container CLI for each workspace extension
and fails if any are absent from the registry. Run the same command with
`--verify` in either mode to check without installing. Extension auto-update
and checks are off in both configs; install or update extensions in normie. The
UI-only PDF viewer (`tomoki1207.pdf`) is installed in host VS Code separately;
the remote CLI refuses it because it cannot run in the container. The
YOLO firewall has no marketplace or extension CDN entries. It filters IPs, so
an unrelated allowed host that shares an IP can still make one reachable.
After a VS Code update, its versioned server binary is downloaded on the host
and transferred again; only the extension directory persists.

### GitHub auth

GitHub access is split by mode (plan: `docs/journal/1006a`). YOLO holds no
GitHub credentials; normie holds the user's `gh` login.

- **Normie.** Log in once from an `nb*` or `nbe` session with
  `gh auth login --with-token` (preferably a fine-grained token scoped to the
  needed repositories), then run `gh auth setup-git` so Git uses the same
  login. Both write to the container's own `~/.config/gh` and `~/.gitconfig`,
  which are not on a shared volume, so YOLO never sees them. The login
  survives a restart but not a rebuild.
- **YOLO.** Run agents with `ybcc`/`ybgpt` (or a shell with `ybe`) from a
  local VS Code window on the host. These use `devcontainer exec`, which
  forwards no credentials. Local commits work; pushes go through normie or a
  host terminal on the same checkout.

**Do not attach VS Code to the YOLO container** (`ybcode` without `--normie`,
or Reopen in Container with the YOLO config). An attached window starts VS
Code's credential relay: sockets in `/tmp` (`vscode-remote-containers-ipc-*`,
`vscode-git-*`, `vscode-ssh-auth-*`) that any process in the container can use
to request credentials from the host, and a helper line in both
`/usr/local/etc/gitconfig` and `~/.gitconfig`. The relay lasts while the
window is attached. The host setting
`"dev.containers.gitCredentialHelperConfigLocation": "none"` only stops the
helper line being written; it is not known to stop the relay answering, and
no setting stops SSH agent forwarding.

A listening relay does not establish that the host will return a usable
credential. In the [2026-10-06 attached-container check](../docs/journal/1006c,vscode-relay-after-oauth-reset.md),
after the user revoked VS Code's GitHub OAuth authorization and signed back
in for Copilot, `gh auth status` reported no login and `git credential fill`
returned no GitHub HTTPS credential (exit 128), despite listening relay
sockets. The failure reason, direct IPC requests, and SSH-agent capabilities
were not tested; this result does not yet justify relaxing the attach guidance.

Pushing from normie is not a licence: agents still ask first.

### Agent Config

All agent configuration lives in `agents/` at the repository root:

- `YOLOBOX-CLAUDE.md` — the editable source for shared Claude and Codex guidance
- `YOLOBOX-AGENTS.md` — a symlink to it, kept separate so Codex-specific guidance can diverge later
- `YOLOBOX-claude-settings.json` — canonical user-level Claude Code settings
- `YOLOBOX-claude-statusline.sh` — status line script referenced by the settings
- `skills/` — canonical shared Agent Skills, linked into both Claude Code and Codex user-level skill directories
- `seed-agent-guidelines.sh` — applies the user-level guidance and Claude settings on every container start (`postStartCommand`)
- `managed/` — files baked into the image:
  - `YOLOBOX-claude-managed-settings.json` — system-enforced Claude Code policy, baked to `/etc/claude-code/managed-settings.json`
  - `YOLOBOX-codex-config.toml` — stable Codex defaults, baked to `/etc/codex/config.toml`
  - `YOLOBOX-codex-requirements.toml` — system-enforced Codex Apps and Plugins policy, baked to `/etc/codex/requirements.toml`

The three `managed/` files are **not** handled by the seed script. They are
`COPY`ed into the image as root-owned `0444`, so changing one requires a
rebuild. The Codex system config provides stable, user-overridable defaults;
the two policy files enforce settings that user config cannot override.
`.devcontainer/tests/test-agent-policy.sh` verifies that the default is installed
and that the policies are actually in force.

The seed script handles guidance and settings differently:

- Guidance is **symlinked** (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`), so edits apply live without a restart.
- Shared skills are **symlinked individually** into `~/.claude/skills/` and
  `~/.agents/skills/`. This keeps one portable source while preserving unrelated
  personal skills in either directory.
- Settings are **copied** to `~/.claude/settings.json`, not symlinked, because Claude Code writes to its settings file (`/config`, `/model`, permission grants). Those writes land in the volume copy and are overwritten by the canonical file on the next container start. To keep a setting permanently, put it in `YOLOBOX-claude-settings.json`.
- Codex's `~/.codex/config.toml` remains ubuntu-owned and volatile because it
  mixes model choices, project trust, and other runtime state. Stable defaults
  belong in `YOLOBOX-codex-config.toml`; user config has higher precedence.

Agent-visible paths for the research library, finished and retired projects,
and screenshots live under **Key Paths** in `agents/YOLOBOX-CLAUDE.md`.
Guidance is symlinked, so path edits require no container restart. The host
time zone is detected separately when the container is created (see
[Timezone](#timezone)).

### Working modes

Each mode is its own container, built from its own config file, which
hard-codes the security posture:

| Mode | Config | Launch | Internet | Package volumes | Seccomp | Use |
|---|---|---|---|---|---|---|
| YOLO mode (default) | `devcontainer.json` | `ybcode`, `ybe` | firewalled | read-only | `builtin` | everyday work; YOLO launchers allowed; agents ask when a package is missing |
| Normie mode | `normie/devcontainer.json` | `nbcode`, `nbe` | open | writable | `unconfined` | supervised work, like the Mac: open web, package installs, agents in approval modes |

Normie mode needs `unconfined` because Codex's approval modes run commands in
Bubblewrap, which builtin seccomp blocks (see
[Codex sandbox modes](#codex-sandbox-modes-and-launchers)). There are only the
two presets; `post-start.sh` reports any other combination (a container made
before the per-mode configs, say) as a custom posture. In normie, a Codex
command sandbox can report `package_access=readonly` while the mode remains
`normie`; an approved escalated command can see writable mounts.

The config sets seccomp in `runArgs`, `readonly` on the three package mounts,
and `YOLOBOX_INTERNET` in `containerEnv` (read by `post-start.sh` at every
start; anything but `open` arms the firewall). `YOLOBOX_MODE` names the
configured mode. `posture.sh` checks that mode against live internet and
seccomp state while reporting package access separately. All settings are fixed
at creation; existing containers need recreation to receive `YOLOBOX_MODE`.
The Dev Containers tooling keys a container on its folder and config
file, so the two containers coexist, and whatever recreates one, `yolobox` or VS
Code's own Rebuild or Reopen, recreates it from the same config, in the same
mode. Neither container ever replaces the other: switching modes is attaching
to the other one. A normie container runs, firewall open, until it is stopped
(`yolobox --stop --normie`); `yolobox --status` lists both, and every YOLO
bring-up mentions a running normie one. Why two files and not one with a
switch: docs/journal/0927a.

The two containers share the package, auth, AI CLI and VS Code extension volumes. Normie writes
packages that YOLO then runs read-only (a running R or Python session sees new
packages after a restart). The per-checkout volumes hold `~/.claude`,
`~/.codex`, the AI CLIs, shell history and VS Code extensions. They are named
for the checkout's folder name alone, not
`${devcontainerId}` (which depends on the config file and would give each mode
its own). So one login and one CLI install serve both modes, and **each
checkout's folder name must be unique on
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

In normie mode, install as `ubuntu` with the ordinary commands:
`install.packages()` writes to the shared site library, `pip install` to
`/opt/venv`, and `tlmgr install` to the TeX tree (then run `tex-refresh`).
The image seeds the volumes `ubuntu`-owned, so no sudo is needed. pip
resolves against current PyPI and can replace dependencies, one reason the mode
is supervised. Agents install in normie mode only when the user asks.
`.devcontainer/setup/install-base.sh` installs the base this way, and
`.devcontainer/setup/install-optional.sh` the optional set;
`install-optional.sh --verify` and `setup/tests/test-optional.sh` check it in any
mode.

### Package stacks and AI CLIs (`.devcontainer/setup/install-base.sh`)

The R, Python and TeX stacks live in three shared Docker volumes. The image
carries a copy of the lean base only to seed them: its build runs
`install-base.sh --image-build`, and Docker copies the image's directory into
each volume the first time an empty one is mounted (docs/journal/0926f). After
that the human changes the base in normie mode with
`bash .devcontainer/setup/install-base.sh` (see the [setup README](setup/README.md)),
and optionally adds the rest with `.devcontainer/setup/install-optional.sh`.
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
per-container volume by the same script, `bash .devcontainer/setup/install-base.sh cli`,
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

`setup/tests/test-packages.sh`, run as `ubuntu` in a rebuilt container, is the
acceptance check for the base. It covers mounts that match `packages`, the
declared base stacks, every installed R package loading, a `fixest`
regression, refused installs of absent packages (read-only mode), and pdflatex,
biber, latexindent, latexmk and LyX export. It passes without the optional
set; `setup/tests/test-optional.sh` checks that set separately.

### Dockerfile ordering

Keep the Dockerfile ordered for cache efficiency as well as readability.

- Put expensive, stable layers early
- Put frequently edited or convenience-oriented layers later
- Avoid small package additions near the top of the file when they would force rebuilds of expensive downstream layers

In practice, large system installs, source builds, and language package installs should be placed so minor template tweaks do not invalidate more of the image cache than necessary.

### Timezone

The container matches your host's timezone: `write-local-env.sh` detects it at
`initializeCommand` time — `$TZ` if exported, else `timedatectl`,
else the target of the `/etc/localtime` symlink (which is how macOS and desktop
Linux actually record it) — and passes it in via `--env-file`.

If detection finds nothing, the fallback is the Dockerfile's `ARG TZ`, which
defaults to `America/New_York`. Note that `TZ` is deliberately **not** set in
`containerEnv`: that becomes `docker run --env`, which outranks `--env-file` and
would override the detected value.
