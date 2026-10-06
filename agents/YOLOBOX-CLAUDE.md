# User level agent guidelines for EconYoloBox

## Permission guidelines

### USER PERMISSION REQUIRED

The actions below are forbidden unless the user explicitly asks for them in the
current conversation. If one seems necessary, STOP work, describe the problem,
and ask. The default fix is for the user to update the environment.

- Get permission before installing packages or other software into the running environment.
- Get permission before authenticating to GitHub or pushing/publishing anything.
- Get permission before connecting to WRDS or testing WRDS credentials. Permission
  allows one connection attempt only. If authentication, 2FA, or connection setup
  fails, stop and ask the user; do not retry, use another client, or delegate the
  attempt to another agent.
- Get permission before hand-rolling replacements for missing libraries or tools.
- Get permission before working around environment problems (Dropbox locks, auth, firewall, or similar).

### Git Guidelines for Codex

Codex specific instructions: When working with git and sandbox protections, request elevated sandbox permissions upfront.

## Key Paths

- Research library (cellar): `/yolobox/cellar/`
- Finished and retired projects (hangar): `/yolobox/hangar/`
- macOS screenshots: `/yolobox/workshop/dev/screenshots/`

### Custom Tools

Custom tools live in `/yolobox/tools/`, organized by topic. Check these folders when the user asks to use the tools. All are on `PATH` (set in `.devcontainer/shellrc.sh`), so the filenames are the commands:

- `tools/pdf/`: `pdf2md.py` (PDF to markdown), `rebookmark.py` (bookmarks PDFs)
- `tools/latex/`: `sync-lyx.sh`; other LaTeX tools go here
- `tools/ai-sesh/`: sync Claude and Codex sessions across machines via Dropbox-synced per-machine stores (`sesh-init`, `sesh-push`, `sesh-wipe`, `gpt-fork`); see its README
- `tools/lit/`: citation lookup — `cited_by.py` (OpenAlex); see its README

## Git Worktrees

- Put worktrees at `.wt/<branch-name>` in the repository root, e.g.
  `git worktree add -b fix/foo .wt/fix/foo main`. A branch name with a slash
  gives nested folders, which is fine. `.wt/` is gitignored.
- Remove a worktree when its branch is merged: `git worktree remove .wt/<branch-name>`.

## Coding and Writing Guidelines

- Python: Use bare `python3`/`pip`. They resolve to the venv at `/opt/venv`,
  which is already active via `PATH`; an unset `VIRTUAL_ENV` is expected.
- Latex: Build using pdflatex and biber
- Note taking: Use LyX if math is involved. We often do math and the human finds this much easier to work with.
- Dropbox: Online-only files cannot be read inside the container. They may
  stat and open normally, but reads fail with `EDEADLK` (errno 35), or `mmap`
  fails with `SIGBUS` (exit code 135). This can also break git when an index or
  object is online-only. Ask the user to run `dbhydrate -f <path>` on the host,
  then retry. `dbhydrate <path>` alone checks without downloading. Do not
  regenerate or re-download the data as a workaround without permission.
- R: When running R scripts non-interactively (`Rscript`), add `pdf(NULL)` near the top to suppress the stray `Rplots.pdf` that R creates whenever a transient graphics device is opened (e.g. by `ggsave()` on a `gridExtra::arrangeGrob` output).

## Documentation

### Script headers

- At the top of every script, document how to run it, its inputs, and its outputs.

## The Environment

- The yolobox repo is bind-mounted at `/yolobox`, so edits are live on the
  host. User projects live under `/yolobox/workshop/`, which is gitignored
  by the yolobox repo. Terms: **yolobox** = the infrastructure repo at
  `/yolobox`; **workshop** = user content under `/yolobox/workshop/`;
  **project** = one working tree inside the workshop.

You are running inside a devcontainer, defined in `/yolobox/.devcontainer/`.
For container behavior and agent configuration, see
[the devcontainer documentation](/yolobox/.devcontainer/README.md). For installed
software, package stacks, and installation procedures, see
[the setup documentation](/yolobox/.devcontainer/setup/README.md). The security design and
available services are described in [the feature guide](/yolobox/docs/features.md).

## Yolobox Configuration

Each mode is its own container,
built from its own config file (`.devcontainer/devcontainer.json` or
`.devcontainer/normie/devcontainer.json`), and the posture is fixed for the
container's life. Both containers may be running at once, sharing `/yolobox`,
the package volumes and `~/.claude`/`~/.codex`. You are in one of them, and
startup prints which:

1. **YOLO mode** (`ybcode` or `ybe` on the host; the default): firewall on,
   R, Python and TeX volumes read-only, Docker's seccomp filter on. Everyday
   work, with agents free to run unsupervised.
2. **Normie mode** (`ybcode --normie` or `ybe --normie`): firewall off,
   volumes writable, seccomp unconfined. Like ordinary work on the Mac, with
   the user watching and agents in approval modes. This is where the web is
   open and packages get installed.

To see the current mode, run `bash /yolobox/.devcontainer/posture.sh`.
Switching modes is the user's decision (see `USER PERMISSION REQUIRED`), made on
the host by opening the other container; nothing in this container can switch it.
Do not edit either config file's posture settings.

### Guidance that depends on the mode

- **Network access depends on the mode.** In YOLO mode, `init-firewall.sh`
  builds a deny-by-default IP allowlist at container start. Blocked hosts are
  REJECTed, so they fail fast rather than hanging — suspect the firewall before
  the code. In normie mode, the container starts without these network
  restrictions. The allowlist when the firewall is on:
  - **Packages**: npm. PyPI, P3M, CRAN, Bioconductor and CTAN are deliberately
    **not** allowed: packages are installed in normie mode, so a missing
    package goes to the user.
  - **VS Code extensions**: install or update them in normie mode with
    `bash .devcontainer/setup/install-vscode-extensions.sh` from a VS Code
    terminal. YOLO mounts the shared volume read-only. Neither mode auto-installs
    on attach; marketplace and extension CDN hosts are absent from the YOLO
    allowlist.
  - **Code hosting**: GitHub's published IP ranges, plus Copilot endpoints.
  - **LLM APIs**: Anthropic, OpenAI/ChatGPT, OpenRouter, Mistral.
  - **Research**: arXiv, SSRN, OpenAlex. Google's ranges are deliberately
    **not** allowed: its servers also host Docs, Drive and Forms, which an
    IP allowlist cannot separate from the rest of Google.
  - **Data**: WRDS, FRED, Ken French's data library
    (`mba.tuck.dartmouth.edu`).
  - With the firewall on, there is no general web access — assume a fetch of
    an arbitrary URL will fail. A download that dies on an unlisted
    **redirect** host is the common surprise; report the host so it can be added.
- For general web information, Claude should use `WebSearch`, and Codex should
  use the `web` tool. These tools access the web through the model providers'
  servers and are not subject to the devcontainer firewall. When the firewall
  is on, this does not make arbitrary URLs available to terminal commands or
  project code.
- **Downloads in YOLO mode.** When the user asks you to download a file
  (a manual, paper, dataset or similar) to disk, run
  `bash /yolobox/.devcontainer/posture.sh` first. If the firewall is on and the
  source host is not on the allowlist above, **STOP and ask the user to switch
  to normie mode**, naming the file and its likely source. Do not hunt through
  mirrors, retry with other clients, or try to save the file through
  `WebFetch`/`web`. You may use web search to pin down the right file and URL
  before asking, so the request is concrete.
- **Package installs depend on the mode.** In YOLO mode, the
  R, Python and TeX stacks are **read-only**. If a package is missing, **ASK THE
  USER TO ADD IT** (name the package) rather than installing it some other way.
  They add it in normie mode, or to a list in `.devcontainer/setup/install-base.sh`
  (base) or `.devcontainer/setup/install-optional.sh` (optional set). In normie mode the volumes
  are writable, but install **only what the user asks for**, with the ordinary
  commands (`install.packages()`, `pip install`, `tlmgr install`), and say when
  pip replaced a dependency. New **system** libraries (`apt-get`, `-dev`
  packages) always need permission — see `USER PERMISSION REQUIRED`.
- **GitHub credentials depend on the mode.** YOLO has none: local commits
  work, but pushes, private fetches and `gh` commands fail for lack of
  authentication. Do not try to authenticate there or look for a credential;
  tell the user the step belongs in normie (`nbcc`, `nbcodex`) or on the host.
  Normie has the user's `gh` login once they have set it up. Pushing from
  normie still needs permission — see `USER PERMISSION REQUIRED`.
- If the firewall blocks a resource you need: **ASK THE USER TO ADD IT**
- For "this screenshot," "the image," or "latest screenshot," look up
  the screenshots path under Key Paths.
