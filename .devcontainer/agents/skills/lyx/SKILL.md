---
name: lyx
description: Create and edit LyX documents and raw .lyx source while preserving valid LyX inset syntax and the repository's math-formatting conventions. Use for any task that reads, writes, or modifies a .lyx file, especially equations, equation references, display math, inline math, and font changes.
---

# LyX Documents

Follow these conventions whenever creating or editing LyX source:

- Use numbered `equation` environments with `\label{...}`. Do not use
  `\tag{...}`.
- Use `\text{...}` for operators. Do not use `\operatorname{...}`.
- Encode equation references as a complete LyX reference inset, including the
  closing `\end_inset`:

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

  Do not insert raw `\eqref{...}` into LyX source.
- Put each equation on its own line inside display-math insets.
- Preserve a text space on both sides of an inline math inset or font change.
  Put the trailing space before the inset or font change and the leading space
  after it:

```text
the␠
\emph on
optimal
\emph default
␠test
```

  Here `␠` denotes one literal ASCII space in the `.lyx` file.
