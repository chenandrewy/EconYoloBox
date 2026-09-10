# Commas in paths are fine for LaTeX (relative paths dodge them)

Sep 9 2026. Came up splitting `Live,Risk-vs/risk-vs-writing` into two papers.

## What breaks

kpathsea treats `,` as a metacharacter (brace expansion). A comma in a
*search path variable* makes the component vanish:

```
TEXINPUTS="$PWD/latex-common:"  kpsewhich zimstyle.sty   # exit 1, path expands to nothing
```

That is the whole failure. It is not "LaTeX can't build under Live,*".

## What does not break

- The cwd having a comma. kpathsea searches the literal component `.`.
- A comma in a *filename argument*: `pdflatex /…/Live,Risk-vs/…/x.tex` is fine.
  (This is what VS Code LaTeX Workshop passes as `%DOC%`.)
- Relative search paths. Verified end to end from inside a comma dir:
  `TEXINPUTS="../common:" BIBINPUTS="../common:"` → pdflatex 0, biber 0
  ("Found BibTeX data source '../common/refs.bib'"), citations resolve.

So: commas in paths are fine as long as relative paths avoid them, which is the
standard case here — every build runs from inside the project.

## The decision

Went with self-contained paper dirs (own `zimstyle.sty`, own bib) rather than a
relative `TEXINPUTS`. Reason: cmd+S is bound to `latex-workshop.build`, which
runs its own recipe, not `build.sh`, and inherits no env. A shared
`latex-common/` would have needed a matching `env` block in the VS Code
settings repo — a second place to keep in sync. Copies cost duplication;
they buy every build path working identically.

Commits: 33acf0b, 369cbce, fa93e5a, b3eaa96 in risk-vs-writing.
