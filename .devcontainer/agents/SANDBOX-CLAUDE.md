# User level agent guidelines for Sandbox

## The Environment

- The sandbox repo is bind-mounted at `/sandbox`, so edits are live on the
  host. User projects live under `/sandbox/workspace/`, which is gitignored
  by the sandbox repo. Terms: **sandbox** = the infrastructure repo at
  `/sandbox`; **workspace** = user content under `/sandbox/workspace/`;
  **project** = one working tree inside the workspace.

You are running inside a devcontainer, defined in `/sandbox/.devcontainer/`.

## Sandbox Configuration

`/sandbox/SANDBOX.toml` is the single source of truth for the research library
(`cellar`), finished and retired projects (`done`), time zone (`timezone`), and
macOS screenshots (`screenshot_directory`). Read it when you need a location;
do not assume or hard-code these paths.

The same file holds three switches: `internet`, which arms (`"firewalled"`) or
disables (`"open"`) the egress firewall at the next container start;
`packages`, which mounts the R, Python and TeX volumes `"readonly"` or
`"writable"`; and `seccomp`, Docker's outer syscall filter (`"builtin"` or
`"unconfined"`). The last two take effect at the next `bbox --rebuild`. Never
change any of them; that is the user's decision (see `USER PERMISSION
REQUIRED`). They combine into two modes, and startup prints the current one:

1. **YOLO mode** (`"firewalled"`, `"readonly"`, `"builtin"`), the default:
   everyday work, with agents free to run unsupervised.
2. **Normie mode** (`"open"`, `"writable"`, `"unconfined"`): like ordinary
   work on the Mac, with the user watching and agents in approval modes. This
   is where the web is open and packages get installed.

Other combinations work and are reported as a custom posture.

### Guidance that depends on `SANDBOX.toml`

- Shared resources that are not projects include the research library (cellar),
  the finished and retired projects folder (done), and the screenshot drop.
- **Network access depends on `internet`.** When `"firewalled"`, `init-firewall.sh`
  builds a deny-by-default IP allowlist at container start. Blocked hosts are
  REJECTed, so they fail fast rather than hanging — suspect the firewall before
  the code. When `"open"`, the container starts without these network
  restrictions. The allowlist when the firewall is on:
  - **Packages**: npm and the VS Code marketplace (per-publisher
    `*.gallerycdn.vsassets.io` — a new extension publisher needs a new entry
    or its install silently fails). PyPI, P3M, CRAN, Bioconductor and CTAN
    are deliberately **not** allowed: packages are installed on the host or
    in normie mode, so a missing package goes to the user.
  - **Code hosting**: GitHub's published IP ranges, plus Copilot endpoints.
  - **LLM APIs**: Anthropic, OpenAI/ChatGPT, OpenRouter, Mistral.
  - **Research**: arXiv, SSRN, OpenAlex, and Google's own published ranges
    (`goog.json`), which cover Google's first-party fleet. GCP customer ranges
    (`cloud.json`) are deliberately **not** allowed.
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
- **Package installs depend on `packages`.** When `"readonly"` (YOLO mode), the
  R, Python and TeX stacks are **read-only**. If a package is missing, **ASK THE
  USER TO ADD IT** (name the package) rather than installing it some other way.
  They add it in normie mode, or to a list in
  `.devcontainer/install-packages.sh` (base) or
  `.devcontainer/install-optional.sh` (optional set). In normie mode the volumes
  are writable, but install **only what the user asks for**, with the ordinary
  commands (`install.packages()`, `pip install`, `tlmgr install`), and say when
  pip replaced a dependency. New **system** libraries (`apt-get`, `-dev`
  packages) always need permission — see `USER PERMISSION REQUIRED`.
- If the firewall blocks a resource you need: **ASK THE USER TO ADD IT**
- For "this screenshot," "the image," or "latest screenshot," look up
  `screenshot_directory` in `/sandbox/SANDBOX.toml`.

## Software and Services

- **Python: use bare `python3`/`pip`.** They resolve to the venv at `/opt/venv`,
  which is already active via `PATH` (so `VIRTUAL_ENV` is unset — that's
  expected).
  - Base: numpy, pandas, matplotlib, statsmodels, pyfixest, PyMuPDF, pikepdf,
    requests, openai, mistralai.
  - Optional set, if the user installed it: scipy, linearmodels,
    scikit-learn, polars, pyarrow, openpyxl, sas7bdat, wrds,
    openassetpricing, beautifulsoup4, lxml, PyYAML.
- R 4.5.3 with packages from a dated P3M snapshot. Base: fixest, data.table,
  tidyverse, modelsummary, sandwich, lmtest, languageserver. The optional set
  adds the rest (arrow, lme4, kableExtra, ..., `pryr` from the CRAN archive,
  `pcaMethods` from Bioconductor); `install-optional.sh --verify` says whether
  it is present.
- **The R, Python and TeX stacks live in shared volumes**, mounted read-only
  unless the user chose normie mode. The base is built on the host by
  `bash .setup/packages.sh` from the lists in
  `.devcontainer/install-packages.sh`; the optional set is installed by the
  user in normie mode with `.devcontainer/install-optional.sh`.
  `install-packages.sh --verify python r tex` checks the base without changing
  it. If an import fails, or startup warns that a package volume is not built,
  notify the user.
- **The Claude Code and Codex CLIs come from the same script**
  (`install-packages.sh cli`, its default), into a writable npm-global
  *volume* — so an update survives rebuilds rather than being reverted by
  them. The npm-managed CLIs should not be assumed to self-update; re-run the
  script's `cli` target to update both. A rebuild is unnecessary.
- TeX Live 2026 is **minimal and pdfLaTeX-only**. Base: scheme-small plus
  bibtexextra (biblatex, biber), latexindent, latexmk and cm-super. The
  optional set adds latexextra, fontsrecommended, pictures (TikZ),
  mathscience and fontsextra. There is no XeLaTeX and no `texdoc`
  documentation; LuaLaTeX is present only because core TeX Live needs it.
  Build with pdflatex. It lives in the shared `texlive-2026-base-noble`
  volume at `/usr/local/texlive`. A missing LaTeX package goes to the user
  like any other package. Run `tex-refresh` as node after TeX changes; it also
  runs at container startup. Reopen an already-running LyX afterward.
- **Connectors and Codex Apps/Plugins are disabled in this sandbox.** Claude's
  AI connectors are disabled by `/etc/claude-code/managed-settings.json`.
  Codex Apps, Plugins, and remote plugin catalogs are disabled by
  `/etc/codex/requirements.toml`. Do not try to bypass or re-enable them; ask
  the user for the unavailable mail, calendar, or other private data instead.
  These are client controls rather than a complete OS security boundary; see
  `docs/features.md` under `Safe YOLO agents` for the threat model.
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
