# Yolobox Features

Agents run unsupervised but bounded, the container supplies the system layer for
economics research, and the daily workflow around all of it is short.

## 1. Safe YOLO agents

The container provides the outer execution boundary. The default is the YOLO
posture: the deny-by-default egress firewall is up, the package volumes are
read-only, and Docker's outer syscall filter (`builtin` seccomp) is on. Each
mode is its own container, whose config file fixes its posture at creation:
`ybcode` opens the YOLO one, `ybcode --normie` the normie one.
Explicit YOLO launchers skip permissions and refuse to start unless the
firewall is enabled and PID 1 has filtered seccomp. Egress blocking is a hard
boundary; an LLM reviewer is a soft one.

For internet access, switch to normie mode (`ybcode --normie`: open internet,
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
container determine its protection. A trace of the lineage remains: the
shell-history volume is still named `claude-code-bashhistory-*`.

The consequence is worth stating plainly: ordinary agent preferences are not
the boundary. The container isolates the process and the firewall bounds its
network reach when enabled; files deliberately bind-mounted into `/yolobox`
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
  agent policy. The firewall stays off only in the normie container: its
  config hard-codes `YOLOBOX_INTERNET=open` in the container's environment,
  fixed at creation, and anything other than `open` arms. Every shell says so
  while it is off. The configs and the startup scripts are in the tracked,
  writable workspace, and so is the host launcher, `.devcontainer/host/devcontainer.zsh`,
  which the host's `~/.zshrc` sources straight from the checkout: an agent
  that edits them changes what the next creation, start, or host shell
  runs. They are not a security boundary against an
  agent that edits the repo; `git diff` before restarting or opening a new
  host terminal is the review step. A
  fresh container has the system toolchain immediately. The R, Python and TeX
  stacks come from shared volumes that Docker seeds from the image on the
  first build, and the AI CLIs install at first start into a per-checkout
  volume that both modes share.

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
and writes a mode-`600` env file that Docker passes with `--env-file` when it
creates the container. Inside, they are ordinary environment variables, which
is what the agents and most tools expect; `get-credentials.py` and `.R` read
the environment first and fall back to the host store outside the container.

This was a bind-mounted file read on demand until 0927a. The environment was
chosen knowing what it costs:

- **Every process inherits them.** Every shell, agent and subprocess has them
  in its environment, so an agent that dumps its environment, a crash
  reporter, or a logging library that serializes `os.environ` can leak them.
- **They are in Docker's metadata.** `--env-file` values become `Config.Env`:
  `docker inspect` prints them, and they persist in the daemon's
  `config.v2.json` for the life of the container, readable by anyone who can
  reach the Docker socket.
- **They are fixed at creation.** Rotating or revoking one means recreating
  the container.

Neither design was a boundary against the agent: anything running as `ubuntu`
could read the old file too, as it had to for WRDS queries to work. Nor does
either stop the host user, who can always `docker exec -u root`.

## 2. Economics research

What the container makes reachable and installable: the analysis stacks, and the
network allowlist that lets research data through. The
commands built on top of them are in [§3](#3-ergonomic-research-tooling).

- **Read-only package stacks.** The Python venv, the R site-library and a
  minimal pdfLaTeX TeX Live live in shared Docker volumes. The first build
  fills them with a lean base: the image carries a copy, and Docker seeds each
  empty volume from it. After that the human changes them with
  `bash .devcontainer/setup/install-base.sh` from inside the container in normie mode, with
  the firewall off and the volumes writable, and every project mounts them
  read-only by default. Agents run the stacks but cannot
  change them. Packages change only in normie mode, from inside.

- **Two working modes, two containers.** YOLO mode, the default (`ybcode`,
  `bbe`), is firewalled, read-only and builtin: agents run unsupervised.
  Normie mode (`ybcode --normie`, `bbe --normie`) is open, writable and
  unconfined: supervised work that feels like the Mac, with agents in
  approval modes. There the user installs with the ordinary
  `install.packages()`, `pip install` and `tlmgr install`, then goes back to
  the YOLO container. Each mode is its own container from its own config
  file, so both can run, switching ends nothing, and a rebuild by `ybox` or
  VS Code keeps the mode. They share logins, the AI CLIs and the package
  volumes. A normie container runs until stopped (`ybox --stop --normie`),
  and every YOLO bring-up mentions it. The mode stays in view: a red VS Code
  window, a `normie` tag in the prompt and Claude's status line, and a
  banner in every shell. The rest of
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
| `.devcontainer/host/devcontainer.zsh` (host shell) | `ybox` (`bbu`, `bbe`, and `ybcode` are short wrappers) |
| `.devcontainer/shellrc.sh` (container shell) | `cchat-yolo`, `gptchat-yolo`, `gptmini-yolo`, `loccode`, `hostname-local`, `container-folder-local`, `gitlog` |
| `tools/ai-sesh/` | `sesh-init`, `sesh-push`, `sesh-wipe`, `gpt-fork` |
| `tools/pdf/` | `pdf2md.py`, `rebookmark.py` |
| `tools/latex/` | `sync-lyx.sh` |
| `tools/lit/` | `cited_by.py` |
| `agents/` | `seed-agent-guidelines.sh` (runs at container start) |
| `.devcontainer/tests/` | `test-firewall.sh`, `test-agent-policy.sh` (also installed on PATH) |
| `.devcontainer/setup/` (container; normie mode except `cli`, `--verify`) | `install-base.sh`, `install-optional.sh` |

Everything in `tools/` is on `PATH` via `shellrc.sh`, so the filenames are the
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

- **One-command project opening (`.devcontainer/host/`).** Source `devcontainer.zsh` in your
  `~/.zshrc` and use `ybcode [dir]` to bring up the enclosing YOLO container
  (or `ybcode --normie [dir]` for the normie one), verify its posture, and
  open that exact subfolder in VS Code. `bbe [dir]` follows the same bring-up
  path and enters zsh; `ybox --status` reports both containers. VS Code's own
  Reopen in Container remains the minimal everyday path; it offers both
  configs.

- **Self-naming Claude sessions (`cchat-yolo`).** Starts Claude with the session
  name derived from the working directory and numbered
  (`My-Project#1`), so `ybox --shell <dir>` then `cchat-yolo` is the whole
  workflow and every session is identifiable without being named by hand.

- **Fleet control.** Every session starts under `--remote-control`, so host-side
  tooling can list sessions across all running containers and terminate them in
  one command. Running many agents at once stays tractable. Note that the
  launchers themselves (`ccsessions`, `cckill`, `cc-remote-*`) are personal
  machine-level configuration and are **not shipped here** — see `.devcontainer/host/README.md`.
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

- **Agent config and skills as code.** `agents/YOLOBOX-CLAUDE.md` holds
  shared Claude/Codex guidance; `agents/` also holds shared LyX and
  PDF-bookmark skills and settings, all re-seeded on every container start.
  Guidance and skills are symlinked so edits apply live; writable settings are
  copied so drift resets to canonical. Separately, root-owned managed policy
  files, baked from `agents/managed/`, enforce the connector and plugin restrictions described above.

- **Host-aware workspace settings.** Startup captures a stable host name and
  the host time zone. `agents/YOLOBOX-CLAUDE.md` provides agent-visible paths for the
  research library and macOS screenshots. That lets agents resolve phrases
  such as “this screenshot” without clipboard access and use the right zone
  for human-facing timestamps.

- **Persistent agent auth.** Named volumes keep Claude and Codex login state
  across rebuilds, shared by both modes' containers, so one login serves
  both. Their names are the checkout's folder name alone, so that name must
  be unique on the Docker daemon, which startup enforces; VS Code forwards host Git credentials so in-container work
  can push branches and open PRs.
