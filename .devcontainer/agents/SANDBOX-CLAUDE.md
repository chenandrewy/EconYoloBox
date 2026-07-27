# User level agent guidelines for Sandbox

## The Environment

You are running inside a devcontainer, defined in `/workspace/.devcontainer/`.

- The repo is bind-mounted at `/workspace`, so edits are live on the host.
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
- Latex with `texlive-full` and `biber`.
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
    (`goog.json`) — which covers Scholar and the rest of Google's first-party
    fleet. GCP customer ranges (`cloud.json`) are deliberately **not** allowed.
  - **Data**: WRDS, FRED, Ken French's data library
    (`mba.tuck.dartmouth.edu`), `global-q.org`, `www.agr.com`.
  - There is still no general web access — assume a fetch of an arbitrary URL
    will fail. A package install that dies on an unlisted **redirect** host is
    the common surprise; report the host so it can be added.
- Installing *packages* from the allowlisted sources (pip, `install.packages()`,
  or `install-packages.sh`) is fine and does not need permission. New **system**
  libraries (`apt-get`, `-dev` packages) do — see `USER PERMISSION REQUIRED`.
- If you think having access to a blocked resource would be helpful: **ASK THE USER TO ADD IT**

## Coding and Writing Guidelines

- Latex: Build using pdflatex and biber
- PDF viewer safety: For compilation, validation, and visual inspection, build into a temporary output directory rather than overwriting the project's existing PDF, because replacing an open PDF can confuse the VS Code PDF viewer. Leave the project PDF untouched unless the user explicitly asks to rebuild it. For example, use `pdflatex -output-directory=/tmp/<build-dir> ...` and run biber and subsequent pdflatex passes against that temporary build.
- Note taking: Use LyX if math is involved. We often do math and the human finds this much easier to work with.

### LyX Guidelines
- Use numbered `equation` environments with `\label{...}`. Don't use `\tag{...}`.
- Use `\text{...}` for operators. Don't use `\operatorname{...}`
- Equation references: Use the full pattern below, including the closing `\end_inset`
```text
\begin_inset CommandInset ref
LatexCommand eqref
reference "eq:model_scan_prob"
plural "false"
caps "false"
noprefix "false"
nolink "false"

\end_inset
```
Don't use raw `\eqref{...}`. 
- In displaymath, put each equation on its own line.
- Put a space in the text around an inline math inset or font change (trailing before, leading after):
```text
the 
\emph on
optimal
\emph default
 test
```

### R Guidelines
- When running R scripts non-interactively (`Rscript`), add `pdf(NULL)` near the top to suppress the stray `Rplots.pdf` that R creates whenever a transient graphics device is opened (e.g. by `ggsave()` on a `gridExtra::arrangeGrob` output).

## Research Library

The user's "library" folder is `/workspace/LIBRARY`. It contains reference papers and PDFs organized by topic.

## Journaling

Journaling refers to taking messy notes. 

- Journal notes should be in `docs/journal/` folders within the appropriate project folder.
- An entry is a snapshot of what was going on when it was written, not a document to maintain.
  - Do not maintain `docs/journal/` folders as if they are proper documentation.

## Time Zones
- Use New York time for all timestamps

## Codex and Claude Code Reviews
The user will ask for code reviews from using Codex or Claude.

Use yolo mode:
    `codex exec --dangerously-bypass-approvals-and-sandbox "your prompt"`
    or
    `claude -p --dangerously-skip-permissions "your prompt"`

Do not necessarily use all of the feedback
- a. Codex tends to overemphasize edge cases
- b. Claude tends to be too positive

Be patient. Code reviews can take up to 20 minutes.

## Script headers

- At the top of every script, document how to run it, its inputs, and its outputs.

## Custom Tools

Custom tools live in `/workspace/.tools/`, organized by topic. Check these folders when the user asks for using '.tools'. All are on `PATH` (set in `.devcontainer/shellrc.sh`), so the filenames are the commands:

- `.tools/pdf/`: `pdf2md.py` (PDF to markdown), `rebookmark.py` (bookmarks PDFs)
- `.tools/latex/`: `sync-lyx.sh`; other LaTeX tools go here
- `.tools/ai-sesh/`: sync Claude and Codex sessions across machines via Dropbox-synced per-machine stores (`sesh-init`, `sesh-push`, `sesh-wipe`, `cc-fork`, `gpt-fork`); see its README
- `.tools/lit/`: citation lookup — `cited_by.py` (Google Scholar), `openalex_cited_by.py` (OpenAlex); see its README

## USER PERMISSION REQUIRED

The actions below are forbidden unless the user explicitly asks for them in the
current conversation. If one seems necessary, STOP work, describe the problem,
and ask. The default fix is for the user to update the environment.

- Get permission before installing packages or other software into the running environment.
- Get permission before authenticating to GitHub or pushing/publishing anything. 
- Get permission before hand-rolling replacements for missing libraries or tools.
- Get permission before working around environment problems (Dropbox locks, auth, firewall, or similar).
