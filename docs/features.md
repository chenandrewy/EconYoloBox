# Sandbox Features

Agents run unsupervised but bounded, the container supplies the system layer for
economics research, and the daily workflow around all of it is short.

## 1. Safe YOLO agents

The container provides the outer execution boundary. The default is the YOLO
posture: the deny-by-default egress firewall is up, the package volumes are
read-only, and Docker's outer syscall filter (`builtin` seccomp) is on. The host
launcher picks the posture when it creates the container (`bbcode`, or
`bbcode --normie`), and it is fixed from then on.
Explicit YOLO launchers skip permissions and refuse to start unless the
firewall is enabled and PID 1 has filtered seccomp. Egress blocking is a hard
boundary; an LLM reviewer is a soft one.

For internet access, switch to normie mode (`bbcode --normie`: open internet,
writable package volumes, `unconfined` seccomp) and use Claude's
`claude --permission-mode auto`. Its two-stage classifier skips in-project
edits and is cheap per call. Codex's automatic review is a full model call per
escalation, and with the firewall down every network action escalates, so it
degrades noticeably; see
[docs/journal/0919b](journal/0919b,claude-vs-codex-reviewer-speed.md). The
mode does not configure either agent's approval mode.

Codex's sandboxed modes (the `/etc/codex` defaults request workspace-write
sandboxing and on-request approval; we recommend
`approvals_reviewer = "auto_review"` in your user config for "Approve for me")
need `unconfined` seccomp, which normie mode sets. Builtin seccomp
blocks Bubblewrap setup, and automatic review could not reliably recover
native editing tools. Unconfined removes Docker's outer syscall filter for
every process, including Claude and unsandboxed commands, and requires
validation of ordinary execution, native editing, and sandbox restrictions
after recreation. Normie mode is the only way to get it; an open-firewall,
builtin-seccomp combination is no longer offered (docs/journal/0923b kept one).
See [sandbox modes and launchers](../.devcontainer/README.md#codex-sandbox-modes-and-launchers)
for configuration and the distinction between sandbox networking and the firewall.

### Inherited from Anthropic

The container design descends from the reference devcontainer in
[anthropics/claude-code](https://github.com/anthropics/claude-code). The original
design uses an isolated container holding the workspace, `NET_ADMIN`/`NET_RAW`
granted so startup can install a default-deny egress firewall, and an agent
running without permission prompts inside that boundary.

The current configuration and the files and credentials exposed inside the
container determine its protection. Traces of the lineage remain — the
container user is `node`, and the shell-history volume is still named
`claude-code-bashhistory-*`.

The consequence is worth stating plainly: ordinary agent preferences are not
the boundary. The container isolates the process and the firewall bounds its
network reach when enabled; files deliberately bind-mounted into `/sandbox`
remain live host files. With the firewall down, commands approved to run outside
the inner sandbox have the container's internet access and can affect or transmit
accessible data. Automatic review is a safeguard, not an OS-level restriction
on each operation performed by an approved script or subprocess.

### Adapted for economics research

Every layer above that inherited skeleton is retuned for the actual work. The
tooling those changes exist to support is described in
[§2](#2-economics-research).

- **Base image.** Rebased onto `ubuntu:24.04` rather than a Node image, because
  the stack that matters here is R, Python, TeX Live, and LyX. Image-level tools
  such as Git, Node, delta, R, Pandoc, and LyX are pinned, and layers are
  cache-conscious. The Claude Code and Codex CLIs deliberately live outside the
  image in a named npm volume: the first start installs them, and
  `install-base.sh cli` updates both to their current releases without a
  rebuild undoing the update. The image
  stays disposable, with everything worth keeping in named volumes or on the
  host.

- **Firewall.** Upstream's allowlist covers what a software engineer needs.
  This one runs its own dnsmasq for domain-based allowlisting and adds the
  sources econ research runs on — data providers and paper repositories. R and
  Python package registries are left out, since packages are installed during
  the image build or with the firewall off. It is also **fail-closed**: any setup failure drops
  all traffic rather than leaving the container open, and blocked hosts are
  REJECTed so they fail fast instead of hanging.

- **Startup scripts.** `postStartCommand` (`post-start.sh`) configures the firewall,
  seeds canonical agent guidance and shared skills, and checks the enforced
  agent policy. The firewall stays off only in a container `bbox --normie`
  created: the choice is in the container's environment, set at creation, and
  anything other than `open` arms. Every shell says so while it is off. That
  takes the switch out of the workspace, so an agent can no longer open the
  firewall by editing a settings file. The startup scripts themselves still
  are in the tracked, writable workspace, and so is the host launcher,
  `.host/devcontainer.zsh`, which the host's `~/.zshrc` sources straight from
  the checkout: an agent that edits either changes what the next start, or
  the next host shell, runs. They are not a security boundary against an
  agent that edits the repo; `git diff` before restarting or opening a new
  host terminal is the review step. A
  fresh container has the system toolchain immediately. The R, Python and TeX
  stacks come from shared volumes that Docker seeds from the image on the
  first build, and the AI CLIs install at first start into a per-container
  volume.

- **Enforced agent policy.** Root-owned configuration disables Claude's online
  connectors and Codex Apps, Plugins, and remote plugin catalogs. A startup
  check verifies the effective policy. This reduces unavailable or unintended
  integration surfaces; like the rest of the agent configuration, it is not the
  sandbox boundary.

### Credential handling

WRDS and LLM API keys have to reach a container that a YOLO agent is running
inside. The design: secrets live in the **host** credential store (macOS
Keychain / Windows Credential Manager), mapped by `credentials-map.json`.
`inject-credentials.py` runs on the host before Docker starts, resolves them,
and writes a mode-`600` file that is bind-mounted **read-only** at
`/run/secrets/credentials.env`. Nothing is passed with `--env-file`. Scripts
call `get-credentials.py`, which reads the file on demand and returns the one
value asked for.

- **Credentials are not injected into the ambient process environment.** They
  are not in PID 1's `environ`, so they are not inherited by every shell, agent,
  and subprocess in the container. An agent that dumps its own environment — or
  a crash reporter, or a logging library that helpfully serializes `os.environ`
  — gets nothing unless a caller explicitly supplied a per-command environment
  override.

- **Credentials never enter Docker metadata.** `--env-file` values become
  `Config.Env`: `docker inspect` prints them, and they persist in the daemon's
  `config.v2.json` for the life of the container, surviving stop/start. That is
  an at-rest copy outside the container, longer-lived than the file itself and
  readable by anyone who can reach the Docker socket. The bind mount has no such
  copy.

**What this does not do.** It is not a boundary against the agent. Anything
running as `node` can read `/run/secrets/credentials.env` — it must, or WRDS
queries would not work. Nor does it stop the host user, who can always
`docker exec -u root`. The claim is narrower and worth stating precisely: by
default, the injected secret exists in one place inside the container, in one
file, readable on demand — instead of being copied into every process
environment and into Docker's own metadata, where it outlives the thing it was
scoped to and spreads to places nobody thinks to check.

## 2. Economics research

What the container makes reachable and installable: the analysis stacks, and the
network allowlist that lets research data through. The
commands built on top of them are in [§3](#3-ergonomic-research-tooling).

- **Read-only package stacks.** The Python venv, the R site-library and a
  minimal pdfLaTeX TeX Live live in shared Docker volumes. The first build
  fills them with a lean base: the image carries a copy, and Docker seeds each
  empty volume from it. After that the human changes them with
  `bash .setup/install-base.sh` from inside the container in normie mode, with
  the firewall off and the volumes writable, and every project mounts them
  read-only by default. Agents run the stacks but cannot
  change them. Packages change only in normie mode, from inside.

- **Two working modes, one flag.** YOLO mode, the default (`bbcode`, `bbe`),
  is firewalled, read-only and builtin: agents run unsupervised. Normie mode
  (`bbcode --normie`, `bbe --normie`) is open, writable and unconfined:
  supervised work that feels like the Mac, with agents in approval modes.
  There the user installs with the ordinary `install.packages()`, `pip
  install` and `tlmgr install`, then switches back. `bbox` recreates the
  container when the mode changes and checks the result; with no flag it
  means YOLO mode, so normie mode never outlasts the command that asked for
  it. The mode stays in view: a red VS Code window, a `normie` tag in the
  prompt and Claude's status line, and a banner in every shell. The rest of
  what we use beyond the base is an
  optional set that `install-optional.sh` installs in normie mode.

- **Pinned R package state.** R resolves against a dated P3M snapshot rather
  than live CRAN, so an R environment rebuilt months later resolves the same
  package versions. Python intentionally resolves current packages from PyPI;
  it is convenient, not lockfile-reproducible. The shared volumes are named by
  distro, interpreter version and snapshot date, so a stack upgrade builds a new
  volume rather than mounting incompatible compiled packages.

- **Research-friendly defaults.** A tracked user R profile suppresses stray
  `Rplots.pdf` files, while the container supplies TeX Live, Biber, LyX, Pandoc,
  and the native libraries needed by the R and Python stacks.

- **Research-tuned network allowlist.** When enabled, the firewall is deny-by-default and
  allows FRED, OpenAlex, arXiv, SSRN, WRDS and the Ken French data library
  alongside npm, code hosting, and agent APIs. Google's published first-party
  ranges are also allowed, so Google-hosted services resolve; arbitrary GCP
  customer ranges are not. R and Python package registries are deliberately
  blocked: the stacks are installed in normie mode, with the firewall off. CDN-fronted
  documentation hosts are added at DNS resolution time so ordinary address
  rotation does not break them.

## 3. Ergonomic research tooling

The largest share of the work here. Getting into a container, starting an agent,
finding it again, moving between machines, and turning a PDF into something
workable should each be one step.

### User-facing commands, by location

| Location | Commands |
| --- | --- |
| `.host/devcontainer.zsh` (host shell) | `bbox` (`bbu`, `bbe`, and `bbcode` are short wrappers) |
| `.devcontainer/shellrc.sh` (container shell) | `cchat-yolo`, `gptchat-yolo`, `gptmini-yolo`, `loccode`, `hostname-local`, `container-folder-local`, `gitlog` |
| `.tools/ai-sesh/` | `sesh-init`, `sesh-push`, `sesh-wipe`, `gpt-fork` |
| `.tools/pdf/` | `pdf2md.py`, `rebookmark.py` |
| `.tools/latex/` | `sync-lyx.sh` |
| `.tools/lit/` | `cited_by.py` |
| `.devcontainer/agents/` | `seed-agent-guidelines.sh` (runs at container start) |
| `.devcontainer/` | `test-firewall.sh`, `test-agent-policy.sh` |
| `.setup/` (container; normie mode except `cli`, `--verify`) | `install-base.sh`, `install-optional.sh` |

Everything in `.tools/` is on `PATH` via `shellrc.sh`, so the filenames are the
commands.

### Documents and literature

- **PDF to Markdown (`pdf2md.py`).** Mistral OCR with figure extraction, writing
  a sibling `<stem>_images/` folder. This is what makes a paper greppable by an
  agent instead of re-read as a PDF on every question.
- **PDF bookmarks (`rebookmark.py`).** Repairs or regenerates clickable outline
  hierarchies, including section, figure, and table bookmarks.
- **LyX/TeX sync (`sync-lyx.sh`).** Two-way sync with PDF rebuild.
- **Citation lookup (`cited_by.py`).** OpenAlex API — stable and structured.
  Seeds from a DOI, a title, or an OpenAlex W-id.

### Containers, sessions, and agents

- **One-command project opening (`.host/`).** Source `devcontainer.zsh` in your
  `~/.zshrc` and use `bbcode [dir]` to bring up the enclosing devcontainer in
  YOLO mode (or `bbcode --normie [dir]`), verify its posture, and open that
  exact subfolder in VS Code. `bbe [dir]` follows the same bring-up path and
  enters zsh; `bbox --status` reports the mode. Direct VS Code creation
  remains the minimal everyday path and always gives YOLO mode.

- **Self-naming Claude sessions (`cchat-yolo`).** Starts Claude with the session
  name derived from the working directory and numbered
  (`My-Project#1`), so `bbox --shell <dir>` then `cchat-yolo` is the whole
  workflow and every session is identifiable without being named by hand.

- **Fleet control.** Every session starts under `--remote-control`, so host-side
  tooling can list sessions across all running containers and terminate them in
  one command. Running many agents at once stays tractable. Note that the
  launchers themselves (`ccsessions`, `cckill`, `cc-remote-*`) are personal
  machine-level configuration and are **not shipped here** — see `.host/README.md`.
  What this repo provides is the half that makes them possible: every session
  remote-controlled and deterministically named.

- **Cross-machine AI session sync (`ai-sesh`).** Claude/Codex session stores are
  symlinked into the Dropbox-synced workspace per machine, so sessions follow
  you between desks; `sesh-push` installs another machine's sessions when you
  switch, with fork and wipe helpers.

- **AIChatRender VS Code extension.** The transcript panel formerly bundled
  here is now maintained separately in the
  [AIChatRender repository](https://github.com/chenandrewy/aichatrender) and is
  installed automatically from the VS Code Marketplace by this devcontainer.

- **Agent config and skills as code (`.devcontainer/agents/`).** The single
  source of truth for Claude/Codex guidance, shared LyX and PDF-bookmark skills,
  and settings is re-seeded on every container start. Guidance and skills are
  symlinked so edits apply live; writable settings are copied so drift resets to
  canonical. Separately, root-owned managed policy files enforce the connector
  and plugin restrictions described above. Preferences such as model, effort
  level, statusline, and remote control remain workflow defaults, not a security
  mechanism.

- **Host-aware workspace settings.** Startup captures a stable host name and
  the host time zone (overridable in `SANDBOX.toml`), and `SANDBOX.toml` also
  provides agent-visible paths for the research library and macOS screenshots. That lets agents resolve
  phrases such as “this screenshot” without clipboard access and use the right
  zone for human-facing timestamps.

- **Persistent agent auth.** Named volumes keep Claude and Codex login state
  across rebuilds; VS Code forwards host Git credentials so in-container work
  can push branches and open PRs.
