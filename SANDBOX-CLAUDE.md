# Agent guidelines

## Guidelines

- Latex: Build using pdflatex and biber
- Note taking: Use LyX. We often do math and the human finds this much easier to work with.

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

## Journaling

Journaling refers to taking messy notes. 

- Journal notes should be in `dev/journal/` folders within the appropriate project folder.
- Use the filename format `[MMDD]T[HH]-[max-three-word-description]`, e.g. `0423T13-sandbox-structure.md` for April 23, 1 pm.

## Time Zones
- Use New York time for all timestamps