# User level agent guidelines for Sandbox

## The Environment

You are running inside a devcontainer, defined in `/workspace/.devcontainer/`.

- The repo is bind-mounted at `/workspace`, so edits are live on the host.
- **Python: use bare `python3`/`pip`.** They resolve to the venv at `/opt/venv`,
  which is already active via `PATH` (so `VIRTUAL_ENV` is unset — that's
  expected).
  - Preinstalled: numpy, pandas, polars, pyarrow, scipy, statsmodels,linearmodels, pyfixest, scikit-learn, matplotlib, openpyxl, wrds, PyMuPDF,
  pikepdf, beautifulsoup4, lxml, requests, openai, mistralai.
- R 4.5.3 with packages pinned to a dated P3M snapshot, so `install.packages()`
  resolves against that snapshot, not live CRAN.
- Latex with `texlive-full` and `biber`.
- **Network is deny-by-default**, via an IP allowlist built at container start by
  `init-firewall.sh`. A blocked host hangs until timeout rather than failing
  cleanly, so suspect the firewall before the code. Allowed:
  - **Packages**: npm, PyPI (`pypi.org`, `files.pythonhosted.org`), Posit P3M,
    VS Code marketplace (per-publisher `*.gallerycdn.vsassets.io` — a new
    extension publisher needs a new entry or its install silently fails).
  - **Code hosting**: GitHub's published IP ranges, plus Copilot endpoints.
  - **LLM APIs**: Anthropic, OpenAI/ChatGPT, OpenRouter, Mistral.
  - **Research**: arXiv, SSRN, Google Scholar, OpenAlex.
  - **Data**: WRDS, FRED, Ken French's data library
    (`mba.tuck.dartmouth.edu`), `global-q.org`, `www.agr.com`.
  - There is no general web access — anything not above is blocked, including
    the rest of Google. Assume a fetch of an arbitrary URL will fail.
- Missing packages are an environment change, not your call — see
  `USER PERMISSION REQUIRED`.
- If you think having access to a blocked resource would be helpful: **ASK THE USER TO ADD IT**

## Coding and Writing Guidelines

- Latex: Build using pdflatex and biber
- PDF viewer safety: For compilation, validation, and visual inspection, build into a temporary output directory rather than overwriting the project's existing PDF, because replacing an open PDF can confuse the VS Code PDF viewer. Leave the project PDF untouched unless the user explicitly asks to rebuild it. For example, use `pdflatex -output-directory=/tmp/<build-dir> ...` and run biber and subsequent pdflatex passes against that temporary build.
- Note taking: Use LyX if math is involved. We often do math and the human finds this much easier to work with.

### LyX Guidelines
- For key equations, use numbered `equation` environments with `\label{...}` instead of display math with manual `\tag{...}` labels.
- Use `\text{...}` for operators. Don't use `\operatorname{...}`
- Equation references: Use the full pattern below, including the closing `\end_inset`, because an unterminated inset breaks the `.lyx` file:
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

### R Guidelines
- When running R scripts non-interactively (`Rscript`), add `pdf(NULL)` near the top to suppress the stray `Rplots.pdf` that R creates whenever a transient graphics device is opened (e.g. by `ggsave()` on a `gridExtra::arrangeGrob` output).

## Research Library

The user's "library" folder is `/workspace/LIBRARY`. It contains reference papers and PDFs organized by topic.

## Journaling

Journaling refers to taking messy notes. 

- Journal notes should be in `docs/journal/` folders within the appropriate project folder.
- Use the filename format `[MMDD][a-z],[max-three-word-description].md`, e.g. `0713a,first-note.md`, `0713b,second-note.md`

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

## Custom Tools

Custom tools live in `/workspace/.tools/`, organized by topic. Check these folders when the user asks for using '.tools'. All are on `PATH` (set in `.devcontainer/shellrc.sh`), so the filenames are the commands:

- `.tools/pdf/`: `pdf2md.py` (PDF to markdown), `rebookmark.py` (bookmarks PDFs)
- `.tools/latex/`: `sync-lyx.sh`; other LaTeX tools go here
- `.tools/ai-sesh/`: sync Claude and Codex sessions across machines via Dropbox-synced per-machine stores (`sesh-init`, `sesh-push`, `sesh-wipe`, `cc-fork`, `gpt-fork`); see its README
- `.tools/dev/`: experimental scripts (`cited_by.py`)

## USER PERMISSION REQUIRED

The actions below are forbidden unless the user explicitly asks for them in the
current conversation. If one seems necessary, STOP work, describe the problem,
and ask. The default fix is for the user to update the environment.

- Do NOT install packages or other software into the running environment.
- Do NOT authenticate to GitHub or push/publish anything. The container has no
  GitHub credentials by design: the user reviews everything before it goes
  public. Prepare commits locally and hand off.
- Do NOT hand-roll replacements for missing libraries or tools.
- Do NOT work around environment problems (Dropbox locks, auth, firewall, or similar).
