# Sandbox Features

Agents run unsupervised but bounded, the environment is ready for economics
research out of the box, projects start from a known-good skeleton, and the
daily workflow around all of it is short.

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

The consequence is worth stating plainly: nothing in the agent configuration
tries to constrain a running agent, because that is not where the boundary
lives. The firewall is the blast radius.

### Adapted for economics research

Every layer above that inherited skeleton is retuned for the actual work. The
tooling those changes exist to support is described in
[§2](#2-economics-research).

- **Base image.** Rebased onto `ubuntu:24.04` rather than a Node image, because
  the stack that matters here is R, Python, TeX Live, and LyX. Tool versions are
  pinned (git, delta, Claude Code, Codex CLI) and layers are cache-conscious, so
  the image stays disposable: destroy and rebuild at will, with everything worth
  keeping in named volumes or on the host.

- **Firewall.** Upstream's allowlist covers what a software engineer needs.
  This one runs its own dnsmasq for domain-based allowlisting and adds the
  sources econ research runs on — data providers, paper repositories, R and
  Python package mirrors. It is also **fail-closed**: any setup failure drops
  all traffic rather than leaving the container open, and blocked hosts are
  REJECTed so they fail fast instead of hanging.

- **Startup scripts.** `postStartCommand` arms the firewall, seeds canonical
  agent guidance, and installs the ChatRender extension — so a fresh container is
  research-ready with no manual steps.

### Credential handling

This part is not inherited, so it has to stand on its own argument.

WRDS and LLM API keys have to reach a container that a YOLO agent is running
inside. The design: secrets live in the **host** credential store (macOS
Keychain / Windows Credential Manager), mapped by `credentials-map.json`.
`inject-credentials.py` runs on the host before Docker starts, resolves them,
and writes a mode-`600` file that is bind-mounted **read-only** at
`/run/secrets/credentials.env`. Nothing is passed with `--env-file`. Scripts
call `get-credentials.py`, which reads the file on demand and returns the one
value asked for.

Three properties follow, in decreasing order of how much they matter.

- **Credentials never enter any process environment.** They are not in PID 1's
  `environ`, so they are not inherited by every shell, agent, and subprocess in
  the container. An agent that dumps its own environment — or a crash reporter,
  or a logging library that helpfully serializes `os.environ` — gets nothing.

- **Credentials never enter Docker metadata.** `--env-file` values become
  `Config.Env`: `docker inspect` prints them, and they persist in the daemon's
  `config.v2.json` for the life of the container, surviving stop/start. That is
  an at-rest copy outside the container, longer-lived than the file itself and
  readable by anyone who can reach the Docker socket. The bind mount has no such
  copy.

- **The store is the OS's, not ours.** Keychain enforces per-app ACLs and can
  prompt. A container-side store would have to be unlocked by a passphrase
  arriving from outside at startup — the same injection problem one level down,
  and a store auto-unlocked at boot is a plaintext file with extra steps.
  Accordingly `get-credentials.py` does not attempt store lookups on Linux;
  in-container resolution is file-and-env only, by design.

**What this does not do.** It is not a boundary against the agent. Anything
running as `node` can read `/run/secrets/credentials.env` — it must, or WRDS
queries would not work. Nor does it stop the host user, who can always
`docker exec -u root`. The claim is narrower and worth stating precisely: the
secret exists in exactly one place inside the container, in one file, readable
on demand — instead of being copied into every process environment and into
Docker's own metadata, where it outlives the thing it was scoped to and spreads
to places nobody thinks to check. Given that the agent is deliberately
unsupervised, minimizing the number of places a credential can be picked up
incidentally is the part actually worth engineering.

See [`docs/journal/0725c,credential-env-file.md`](journal/0725c,credential-env-file.md)
for the analysis this replaced, including why the earlier auto-delete timer was
security theatre.


## 2. Economics research

What the container makes reachable and installable: the analysis stacks, and the
network allowlist that lets research data and package mirrors through. The
commands built on top of them are in [§4](#4-ergonomic-research-tooling).

- **Ready-to-use analysis stacks.** A full Python venv and R site-library
  installed by one script (`install-packages.sh`) into version-named persistent
  volumes, so rebuilds are fast and packages survive container recreation.

  Note that installs run *behind the firewall*, which makes them tricky: package
  hosts and their redirect mirrors must be allowlisted, and `docker build`
  having open network is no evidence a command works in a running container.

- **Reproducible package state.** R resolves against a dated P3M snapshot rather
  than live CRAN, so an environment rebuilt months later is the environment you
  had. Persistent volumes are version-named, so a stack upgrade is a new volume
  rather than a mutation of the old one.

- **Research-tuned network allowlist.** The firewall's allowlist is curated for
  economics: FRED, OpenAlex, arXiv, SSRN, WRDS, the Ken French data library,
  global-q, and JKP factor data are reachable alongside package registries and
  agent APIs — little else is.

## 3. Project templates (`template/`)

Container-level setup gets you a working environment; templates get you a
working *project*. Econ research output comes in a few recurring genres, each
with a stable file layout, build pipeline, and set of agent instructions.

Status: `template/` currently holds real work instances, not generalized
templates. A common skeleton has converged across the recent ones and is ready
to be extracted:

- `AGENTS.md` + `CLAUDE.md` — the gig, target file structure, workflow, build
  commands, forbidden actions
- `sub/` — the submission as received, plus `paper.md` from `pdf2md.py` so
  agents can grep the paper rather than re-reading a PDF
- `dev/journal/` → `notes/` → output — messy notes to clean notes to product
- `build.sh` / `final-build.sh` / `number_slides.py` — one-command builds,
  including the rename/touch trick that makes VS Code's PDF viewer refresh
- `agent-sessions/` with `cc-paper.sh` and `gpt-paper.sh` — fork a session that
  has already ingested the paper, so the reading cost is paid once

Three templates planned:

- **Live research projects** — the long-running case: data, code, drafts.
- **Referee reports** — the public version must be built around a **fabricated**
  manuscript. Real reports and the submissions they discuss are confidential and
  cannot ship.
- **Discussions** — conference and webinar discussions. These are the author's
  own work and can ship real, which makes them the strongest public
  demonstration: a short, self-contained, deadline-driven genre that exercises
  OCR, literature lookup, LyX math notes, Beamer builds, and agent session
  forking end to end.

## 4. Ergonomic research tooling

The largest share of the work here. Getting into a container, starting an agent,
finding it again, moving between machines, and turning a PDF into something
workable should each be one step.

### Every command, by location

| Location | Commands |
| --- | --- |
| `.host/devcontainer.zsh` (host shell) | `dcu`, `dce`, `dccode` (`dc-resolve.py` backs them) |
| `.devcontainer/shellrc.sh` (container shell) | `cchat-yolo`, `gptchat-yolo`, `gptmini-yolo`, `loccode`, `hostname-local`, `container-folder-local`, `gitlog` |
| `.tools/ai-sesh/` | `sesh-init`, `sesh-push`, `sesh-wipe`, `cc-fork`, `gpt-fork` |
| `.tools/pdf/` | `pdf2md.py`, `rebookmark.py` |
| `.tools/latex/` | `sync-lyx.sh` |
| `.tools/lit/` | `cited_by.py`, `openalex_cited_by.py` |
| `.tools/chatrender/` | `install-extension.sh` (runs at container start) |
| `.devcontainer/agents/` | `seed-agent-guidelines.sh` (runs at container start) |
| `.devcontainer/` | `install-packages.sh`, `test-firewall.sh` |

Everything in `.tools/` is on `PATH` via `shellrc.sh`, so the filenames are the
commands.

### Documents and literature

- **PDF to Markdown (`pdf2md.py`).** Mistral OCR with figure extraction, writing
  a sibling `<stem>_images/` folder. This is what makes a paper greppable by an
  agent instead of re-read as a PDF on every question.
- **PDF bookmarks (`rebookmark.py`).** Regenerates section bookmarks.
- **LyX/TeX sync (`sync-lyx.sh`).** Two-way sync with PDF rebuild.
- **Citation lookup.** `cited_by.py` (Google Scholar — fresh but scraped) and
  `openalex_cited_by.py` (OpenAlex API — stable and structured).

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
  (`Live,Risk-vs-Writing#1`), so `dce <dir>` then `cchat-yolo` is the whole
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

- **ChatRender VS Code extension.** A live transcript panel for the current
  Claude/Codex session with KaTeX-rendered math, auto-following whichever
  session wrote most recently. Deliberately hookless, serverless, and
  HTML-inert; auto-installed on container start.

- **Agent config as code (`.devcontainer/agents/`).** The single source of truth
  for Claude/Codex guidance and settings, re-seeded on every container start:
  guidance is symlinked so edits apply live; settings are copied so drift resets
  to canonical. These are preferences and workflow defaults — model, effort
  level, statusline, remote control at startup — not a security mechanism.

- **Persistent agent auth.** Named volumes keep Claude and Codex login state
  across rebuilds; VS Code forwards host Git credentials so in-container work
  can push branches and open PRs.
