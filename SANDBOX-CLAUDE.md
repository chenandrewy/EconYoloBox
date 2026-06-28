# User level agent guidelines for Sandbox

## Coding and Writing Guidelines

- Latex: Build using pdflatex and biber
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

- Journal notes should be in `dev/journal/` folders within the appropriate project folder.
- Use the filename format `[MMDD]T[HH]-[max-three-word-description]`, e.g. `0423T13-sandbox-structure.md` for April 23, 1 pm.

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

There are various custom tools in  `/workspace/.tools/`. Check this folder when the user asks for using '.tools'. 

## Paths

- Discussions: `Disc-*/`
- Travel: `Travel-*/`
- Research projects: No special prefix
- Templates for reference: `template/`
