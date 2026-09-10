#!/usr/bin/env bash
# Run as node in a fresh rebuilt container: bash /checks/test-texlive.sh
# Inputs: real TeX volume mounted read-only; this script mounted at /checks.
# Outputs: logs, PDF, and LyX fixtures in /tmp/texlive-check; nonzero on failure.
set -euo pipefail
test "$(id -un)" = node
mkdir /tmp/texlive-check
cd /tmp/texlive-check

findmnt -n -o OPTIONS -T /usr/local/texlive | tr ',' '\n' | grep -qx ro
if touch /usr/local/texlive/consumer-write-test 2>readonly.log; then
  echo 'FAIL: consumer can write to the TeX installation' >&2
  exit 1
fi
for tree in TEXMFVAR TEXMFCONFIG TEXMFHOME; do
  path=$(kpsewhich -var-value="$tree")
  case "$path" in
    "$HOME"/*) mkdir -p "$path"; test -w "$path" ;;
    *) echo "FAIL: $tree is outside the user home: $path" >&2; exit 1 ;;
  esac
done
for binary in pdflatex xetex biber; do
  ldd "$(command -v "$binary")" > "$binary.ldd" 2>&1 || true
  if grep -q 'not found' "$binary.ldd"; then
    cat "$binary.ldd" >&2
    exit 1
  fi
done

cat > references.bib <<'BIB'
@book{knuth1984,
  author = {Donald E. Knuth},
  title = {The TeXbook},
  year = {1984},
  publisher = {Addison-Wesley}
}
BIB
cat > document.tex <<'TEX'
\documentclass{article}
\usepackage{amsmath}
\usepackage[backend=biber,style=authoryear]{biblatex}
\addbibresource{references.bib}
\begin{document}
TeX volume acceptance check. See \autocite{knuth1984}.
\begin{equation}\label{eq:model}
y = \alpha + \beta x + \varepsilon
\end{equation}
Equation~\eqref{eq:model} is the model.
\printbibliography
\end{document}
TEX

pdflatex -interaction=nonstopmode -halt-on-error document.tex > pdflatex-first.log
biber document > biber-run.log
pdflatex -interaction=nonstopmode -halt-on-error document.tex > pdflatex-second.log
pdflatex -interaction=nonstopmode -halt-on-error document.tex > pdflatex-final.log
test -s document.pdf
if grep -Eiq 'undefined|Please \(re\)run Biber|Rerun to get cross-references right' document.log; then
  echo 'FAIL: unresolved references' >&2
  exit 1
fi
pdftotext document.pdf document.txt
grep -q 'Knuth' document.txt
grep -q '1984' document.txt
latexindent document.tex > indented.tex
test -s indented.tex

cat > xetex-smoke.tex <<'TEX'
\documentclass{article}\begin{document}XeTeX smoke test: $x^2$.\end{document}
TEX
xelatex -interaction=nonstopmode -halt-on-error xetex-smoke.tex > xelatex-run.log
test -s xetex-smoke.pdf

tex-refresh > lyx-refresh.log 2>&1
# A second scan must replace stale generated detection, preserving preferences.
printf '\nSTALE_DETECTION_SENTINEL\n' >> "$HOME/.lyx/lyxrc.defaults"
tex-refresh > lyx-refresh-second.log 2>&1
if grep -q STALE_DETECTION_SENTINEL "$HOME/.lyx/lyxrc.defaults"; then
  echo 'FAIL: stale LyX converter detection survived refresh' >&2
  exit 1
fi
export QT_QPA_PLATFORM=offscreen
tex2lyx -f document.tex document.lyx > lyx-import.log 2>&1
test -s document.lyx
lyx -batch -f all -E pdflatex lyx-export.tex document.lyx > lyx-tex-export.log 2>&1
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex > lyx-pdflatex-first.log
biber lyx-export > lyx-biber.log
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex > lyx-pdflatex-second.log
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex > lyx-pdflatex-final.log
if grep -Eiq 'undefined|Please \(re\)run Biber|Rerun to get cross-references right' lyx-export.log; then
  echo 'FAIL: unresolved LyX export references' >&2
  exit 1
fi
lyx -batch -f all -E pdf2 lyx-direct.pdf document.lyx > lyx-pdf-export.log 2>&1
test -s lyx-direct.pdf
pdftotext lyx-direct.pdf lyx-direct.txt
grep -q 'Knuth' lyx-direct.txt
grep -q '1984' lyx-direct.txt
printf 'PASS: %s; pdflatex, xelatex, biber, latexindent, LyX; read-only TeX and writable user trees\n' "$(dpkg --print-architecture)"
