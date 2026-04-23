# Agent guidelines

## Guidelines

- Latex: Build using pdflatex and biber
- Note taking: Use lyx. We often do math and the human finds this much easier to work with.
- LyX equations: For key equations, use numbered `equation` environments with `\label{...}` instead of display math with manual `\tag{...}` labels.
- LyX math style: Prefer `\text{...}` over `\operatorname{...}` in LyX math where the goal is readable prose-style notation.
- LyX equation references: Prefer LyX's native reference inset form rather than raw ERT `\eqref{...}`. Use the full pattern below, including the closing `\end_inset`, because an unterminated inset breaks the `.lyx` file:
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
