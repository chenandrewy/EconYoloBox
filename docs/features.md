# Sandbox Features

Agents run unsupervised but bounded, the container supplies the system layer for
economics research, and the daily workflow around all of it is short.

## 1. Safe YOLO agents

Agents run with permissions skipped. That is the point, and it is only tenable
because the container — not the prompt — is the boundary.

### Inherited from Anthropic

The container design descends from the reference devcontainer in
[anthropics/claude-code](https://github.com/anthropics/claude-code), so the
security posture is theirs rather than something invented here: an isolated
container holding the workspace, `NET_ADMIN`/`NET_RAW` granted only so that
startup can install a default-deny egress firewall, and the agent then run
without permission prompts inside that boundary.

Keeping the upstream shape is deliberate. It is a design many people have
reviewed, and it means the safety argument does not rest on this repo's own
judgment. Traces of the lineage are still visible — the container user is
`node`, and the shell-history volume is still named
`claude-code-bashhistory-*`.

The consequence is worth stating plainly: ordinary agent preferences are not
the boundary. The container isolates the process and the firewall bounds its
network reach; files deliberately bind-mounted into `/workspace` remain live
host files and must be treated accordingly.

### Adapted for economics research

Every layer above that inherited skeleton is retuned for the actual work. The
tooling those changes exist to support is described in
[§2](#2-economics-research).

- **Base image.** Rebased onto `ubuntu:24.04` rather than a Node image, because
  the stack that matters here is R, Python, TeX Live, and LyX. Image-level tools
  such as Git, Node, delta, R, Pandoc, and LyX are pinned, and layers are
  cache-conscious. The Claude Code and Codex CLIs deliberately live outside the
  image in a named npm volume: `install-packages.sh cli` installs or updates both
  to their current releases without a rebuild undoing the update. The image
  stays disposable, with everything worth keeping in named volumes or on the
  host.

- **Firewall.** Upstream's allowlist covers what a software engineer needs.
  This one runs its own dnsmasq for domain-based allowlisting and adds the
  sources econ research runs on — data providers, paper repositories, R and
  Python package mirrors. It is also **fail-closed**: any setup failure drops
  all traffic rather than leaving the container open, and blocked hosts are
  REJECTed so they fail fast instead of hanging.

- **Startup scripts.** `postStartCommand` arms the firewall, seeds canonical
  agent guidance and shared skills, and checks the enforced agent policy. A
  fresh container has the system toolchain immediately; the optional Python and
  R stacks and the AI CLIs are installed once into persistent volumes with
  `install-packages.sh`.

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
network allowlist that lets research data and package mirrors through. The
commands built on top of them are in [§3](#3-ergonomic-research-tooling).

- **One-command analysis stacks.** `install-packages.sh` populates a Python venv
  and R site-library in version-named persistent volumes, so rebuilds are fast
  and packages survive container recreation. A newly created volume starts
  empty; the script is the explicit, one-time setup step and can be rerun to add
  or repair packages.

  Note that installs run *behind the firewall*, which makes them tricky: package
  hosts and their redirect mirrors must be allowlisted, and `docker build`
  having open network is no evidence a command works in a running container.

- **Pinned R package state.** R resolves against a dated P3M snapshot rather
  than live CRAN, so an R environment rebuilt months later resolves the same
  package versions. Python intentionally resolves current packages from PyPI;
  it is convenient, not lockfile-reproducible. Persistent volumes are
  interpreter- and platform-versioned, so a stack upgrade starts a new volume
  rather than mounting incompatible compiled packages.

- **Research-friendly defaults.** A tracked user R profile suppresses stray
  `Rplots.pdf` files, while the container supplies TeX Live, Biber, LyX, Pandoc,
  and the native libraries needed by the R and Python stacks.

- **Research-tuned network allowlist.** The firewall is deny-by-default and
  allows FRED, OpenAlex, arXiv, SSRN, WRDS, the Ken French data library,
  global-q, and JKP factor data alongside package registries, code hosting, and
  agent APIs. Google's published first-party ranges are also allowed, so
  Google-hosted services resolve; arbitrary GCP customer ranges are not.
  CDN-fronted package and documentation hosts are added at DNS resolution time
  so ordinary address rotation does not break installs.

## 3. Ergonomic research tooling

The largest share of the work here. Getting into a container, starting an agent,
finding it again, moving between machines, and turning a PDF into something
workable should each be one step.

### User-facing commands, by location

| Location | Commands |
| --- | --- |
| `.host/devcontainer.zsh` (host shell) | `dcu`, `dce`, `dccode` (`dc-resolve.py` backs them) |
| `.devcontainer/shellrc.sh` (container shell) | `cchat-yolo`, `gptchat-yolo`, `gptmini-yolo`, `loccode`, `hostname-local`, `container-folder-local`, `gitlog` |
| `.tools/ai-sesh/` | `sesh-init`, `sesh-push`, `sesh-wipe`, `cc-fork`, `gpt-fork` |
| `.tools/pdf/` | `pdf2md.py`, `rebookmark.py` |
| `.tools/latex/` | `sync-lyx.sh` |
| `.tools/lit/` | `cited_by.py` |
| `.devcontainer/agents/` | `seed-agent-guidelines.sh` (runs at container start) |
| `.devcontainer/` | `install-packages.sh`, `test-firewall.sh`, `test-agent-policy.sh` |

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
  `~/.zshrc` and any project folder is one command away: `dccode [dir]` walks up
  from any subfolder to the enclosing devcontainer and opens that exact
  subfolder in VS Code inside the container; `dce [dir]` does the same but drops
  you into an in-container zsh. No manual "Reopen in Container" and no
  navigating after attach. The toolkit takes no configuration and names no
  personal paths, so it works against any repo with a devcontainer and ports
  across machines unchanged.

- **Self-naming Claude sessions (`cchat-yolo`).** Starts Claude with the session
  name derived from the working directory and numbered
  (`My-Project#1`), so `dce <dir>` then `cchat-yolo` is the whole
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
  detects the host time zone, while `SANDBOX.toml` provides agent-visible paths
  for the research library and macOS screenshots. That lets agents resolve
  phrases such as “this screenshot” without clipboard access and use the right
  zone for human-facing timestamps.

- **Persistent agent auth.** Named volumes keep Claude and Codex login state
  across rebuilds; VS Code forwards host Git credentials so in-container work
  can push branches and open PRs.
