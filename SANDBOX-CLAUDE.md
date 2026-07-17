# User level agent guidelines for Sandbox

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

## Journaling

Journaling refers to taking messy notes. 

- Journal notes should be in `docs/journal/` folders within the appropriate project folder.
- Use the filename format `[MMDD][a-z],[max-three-word-description].md`, e.g. `0713a,first-note.md`, `0713b,second-note.md`

## Time Zones
- Use New York time for all timestamps

## Codex and Claude Code Reviews
The user will ask for code reviews from using Codex or Claude.
1. Check if you are in the container
2. Launch with or without yolo mode, depending
    - a. If in the container, use yolo mode: 
        `codex exec --dangerously-bypass-approvals-and-sandbox "your prompt"`
        or
        `claude -p --dangerously-skip-permissions "your prompt"`
    - b. If not in the container, use normal mode:
        `codex exec "your prompt"`
        or
        `claude -p "your prompt"`
3. Do not necessarily use all of the feedback
    - a. Codex tends to overemphasize edge cases
    - b. Claude tends to be too positive

## Custom Tools

Custom tools live in `/workspace/.tools/`, organized by topic. Check these folders when the user asks for using '.tools'. All are on `PATH` (set in `.devcontainer/shellrc.sh`), so the filenames are the commands:

- `.tools/pdf/`: `pdf2md.py` (PDF to markdown), `rebookmark.py` (bookmarks PDFs)
- `.tools/latex/`: `sync-lyx.sh`; other LaTeX tools go here
- `.tools/ai-sesh/`: stage/restore/fork Claude and Codex sessions (`sesh-grab`, `sesh-push`, `sesh-wipe`, `cc-fork`, `gpt-fork`); see its README
- `.tools/dev/`: experimental scripts (`cited_by.py`)
