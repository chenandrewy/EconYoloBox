# User level agent guidelines for Sandbox

## The Environment

You are running inside a devcontainer, defined in `/sandbox/.devcontainer/`.

- The sandbox repo is bind-mounted at `/sandbox`, so edits are live on the
  host. User content (projects, `LIBRARY/`, `DONE/`, `dev/`, ...) lives under
  `/sandbox/workspace/`, which is gitignored by the sandbox repo. Terms:
  **sandbox** = the infrastructure repo at `/sandbox`; **workspace** = user
  content under `/sandbox/workspace/`; **project** = one working tree inside
  the workspace.
- **Python: use bare `python3`/`pip`.** They resolve to the venv at `/opt/venv`,
  which is already active via `PATH` (so `VIRTUAL_ENV` is unset — that's
  expected).
  - Installed: numpy, pandas, polars, pyarrow, scipy, statsmodels, linearmodels,
    pyfixest, scikit-learn, matplotlib, openpyxl, wrds, PyMuPDF, pikepdf,
    beautifulsoup4, lxml, requests, openai, mistralai.
- R 4.5.3 with packages pinned to a dated P3M snapshot, so `install.packages()`
  resolves against that snapshot, not live CRAN.
- **Neither stack is baked into the image.** Both come from
  `.devcontainer/install-packages.sh`, which is re-runnable and skips what is
  already installed. If an import fails right after a rebuild, notify the user.
- **The Claude Code and Codex CLIs come from the same script**
  (`install-packages.sh cli`), into an npm-global *volume* — so an update
  survives rebuilds rather than being reverted by them. The npm-managed CLIs
  should not be assumed to self-update; re-run the script's `cli` target to
  update both. A rebuild is unnecessary.
- TeX Live (full scheme, including biber) is host-installed with
  `bash .setup/texlive.sh` into the shared `texlive-2026-noble` Docker volume,
  mounted read-only at `/usr/local/texlive`. Do not install or update TeX in
  the devcontainer. Run `tex-refresh` as node after initial host installation;
  it also runs at container startup. Reopen an already-running LyX afterward.
  The setup script refuses nonempty volumes; updates are separate manual work.
- **Network is deny-by-default**, via an IP allowlist built at container start by
  `init-firewall.sh`. Blocked hosts are REJECTed, so they fail fast rather than
  hanging — but suspect the firewall before the code. Allowed:
  - **Packages**: npm, PyPI (`pypi.org`, `files.pythonhosted.org`), Posit P3M
    (plus `rspm-sync.rstudio.com`, where P3M redirects the payload) and
    `cran.r-project.org` for archived sources, VS Code marketplace
    (per-publisher `*.gallerycdn.vsassets.io` — a new extension publisher needs
    a new entry or its install silently fails).
  - **Code hosting**: GitHub's published IP ranges, plus Copilot endpoints.
  - **LLM APIs**: Anthropic, OpenAI/ChatGPT, OpenRouter, Mistral.
  - **Research**: arXiv, SSRN, OpenAlex, and Google's own published ranges
    (`goog.json`), which cover Google's first-party fleet. GCP customer ranges
    (`cloud.json`) are deliberately **not** allowed.
  - **Data**: WRDS, FRED, Ken French's data library
    (`mba.tuck.dartmouth.edu`) and `global-q.org`.
  - There is still no general web access — assume a fetch of an arbitrary URL
    will fail. A package install that dies on an unlisted **redirect** host is
    the common surprise; report the host so it can be added.
- For general web information, Claude should use `WebSearch`, and Codex should
  use the `web` tool. These tools access the web through the model providers'
  servers and are not subject to the devcontainer firewall. This does not make
  arbitrary URLs available to terminal commands or project code.
- **Connectors and Codex Apps/Plugins are disabled in this sandbox.** Claude's
  AI connectors are disabled by `/etc/claude-code/managed-settings.json`.
  Codex Apps, Plugins, and remote plugin catalogs are disabled by
  `/etc/codex/requirements.toml`. Do not try to bypass or re-enable them; ask
  the user for the unavailable mail, calendar, or other private data instead.
  These are client controls rather than a complete OS security boundary; see
  `docs/features.md` under `Safe YOLO agents` for the threat model.
- Installing *packages* from the allowlisted sources (pip, `install.packages()`,
  or `install-packages.sh`) is fine and does not need permission. New **system**
  libraries (`apt-get`, `-dev` packages) do — see `USER PERMISSION REQUIRED`.
- If you think having access to a blocked resource would be helpful: **ASK THE USER TO ADD IT**
- **Dropbox online-only files cannot be read in here.** `/sandbox` is a
  VirtioFS mount of a Dropbox folder, and files Dropbox has evicted still stat
  and open normally — only reads fail, with **EDEADLK (errno 35)**, or **SIGBUS**
  under `mmap` (exit code 135). Retrying never works: the refusal does not queue
  a fetch, and no syscall available in here can request one. `.git` is not
  exempt — a dataless index or loose object breaks ordinary git commands.
  - **Ask the user to run `dbhydrate -f <path>` on the host**, then retry. It
    reports before it downloads, so `dbhydrate <path>` alone is a safe check.
  - Do not route around it by regenerating or re-downloading the data; that is a
    workaround under `USER PERMISSION REQUIRED`. Ask first.
- **Images cannot be pasted into the CLI chat.** There is no host clipboard in
  here: no `DISPLAY`, no clipboard binaries, and the macOS pasteboard is
  unreachable from a Linux container. Installing `xclip` would not help, and the
  integrated terminal only carries text over the pty. So the user hands over
  images by *path* instead. The host writes macOS screenshots into the directory
  configured as `screenshot_directory` in `/sandbox/SANDBOX.toml` (`/dev/` is
  gitignored).
  - When the user refers to "this screenshot", "the image", or similar without
    naming a file, read `screenshot_directory` from `/sandbox/SANDBOX.toml`
    and use the newest image in that directory. Confirm which file you picked
    when it is ambiguous.
  - The folder is Dropbox-synced, so old shots can be evicted to online-only and
    fail to read — see the bullet above. Prune it when it gets noisy.

## Project Configuration

Read `/sandbox/SANDBOX.toml` for project-specific settings regarding

- the research library location
- time zone
- the macOS screenshot directory

The same file holds `firewall`, the switch that arms (`true`) or disables
(`false`) the egress firewall at the next container start. Never change it;
that is the user's decision (see `USER PERMISSION REQUIRED`).

## Coding and Writing Guidelines

- Latex: Build using pdflatex and biber
- Note taking: Use LyX if math is involved. We often do math and the human finds this much easier to work with.

### R Guidelines
- When running R scripts non-interactively (`Rscript`), add `pdf(NULL)` near the top to suppress the stray `Rplots.pdf` that R creates whenever a transient graphics device is opened (e.g. by `ggsave()` on a `gridExtra::arrangeGrob` output).

## Documentation

## Script headers

- At the top of every script, document how to run it, its inputs, and its outputs.

## Custom Tools

Custom tools live in `/sandbox/.tools/`, organized by topic. Check these folders when the user asks for using '.tools'. All are on `PATH` (set in `.devcontainer/shellrc.sh`), so the filenames are the commands:

- `.tools/pdf/`: `pdf2md.py` (PDF to markdown), `rebookmark.py` (bookmarks PDFs)
- `.tools/latex/`: `sync-lyx.sh`; other LaTeX tools go here
- `.tools/ai-sesh/`: sync Claude and Codex sessions across machines via Dropbox-synced per-machine stores (`sesh-init`, `sesh-push`, `sesh-wipe`, `gpt-fork`); see its README
- `.tools/lit/`: citation lookup — `cited_by.py` (OpenAlex); see its README

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
