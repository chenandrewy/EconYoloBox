---
name: lyx
description: Create, edit, import, and validate LyX documents and raw .lyx source while preserving valid inset syntax and repository formatting conventions. Use for any task that reads, writes, or modifies a .lyx file, especially equations, references, display or inline math, font changes, tables, LaTeX-to-LyX conversion, and headless LyX export.
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

## Tables and LaTeX imports

- Prefer a native `Tabular` inset when the table should remain visible and
  editable in LyX. Use ERT only for small commands that LyX cannot represent.
- To convert a complex LaTeX table, create a minimal standalone `.tex` file in
  a temporary directory and import it headlessly:

```bash
QT_QPA_PLATFORM=offscreen lyx -batch -f all \
  -i latex /tmp/table.tex /tmp/table.lyx
```

  LyX requires the output `.lyx` filename for a batch import. Transplant only
  the needed float or tabular inset; do not copy `\begin_body` or `\end_body`.
- Inspect imported ERT before using it. In particular, LaTeX group commands
  such as `\begingroup` and `\endgroup` can interact badly with LyX-generated
  font groups. Prefer native alignment and font settings, and keep a required
  `\setlength{\tabcolsep}{...}` as a small ERT inset before the table.
- Preserve an externally assigned table number only when the destination
  document needs that number. Put `\setcounter{table}{N-1}` in ERT before the
  caption so LyX emits “Table N.”
- Check wide tables for overflow after export. First restore the source table's
  column spacing; if needed, reduce the native LyX font size one step rather
  than dropping content.

## Validation

- Keep exactly one `\begin_document`, `\begin_body`, `\end_body`, and
  `\end_document` in raw LyX source.
- Export LaTeX headlessly, then compile it explicitly in a temporary directory.
  This exposes errors that a direct LyX PDF export may not report clearly:

```bash
QT_QPA_PLATFORM=offscreen lyx -batch -f all \
  -E pdflatex /tmp/document.tex path/to/document.lyx
build_dir=$(mktemp -d /tmp/lyx-build.XXXXXX)
pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory="$build_dir" /tmp/document.tex
```

- Inspect the log for LaTeX errors and `Overfull` warnings, and visually inspect
  changed tables or layout-sensitive pages. Leave project PDFs untouched unless
  the user explicitly requests rebuilding them.
