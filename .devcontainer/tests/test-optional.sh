#!/usr/bin/env bash
# Run as node in the devcontainer, any mode: bash .devcontainer/tests/test-optional.sh
# Inputs: the shared R, Python and TeX volumes after install-optional.sh has
#   filled them; install-optional.sh (its --verify mode holds the lists).
# Outputs: fixtures and logs in a new /tmp/optional-check.* directory (printed
#   first); a PASS line and exit 0, or a FAIL line and nonzero exit.
#
# Separate from test-packages.sh on purpose: the base must pass without this
# set, and a user may skip it.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() {
    echo "FAIL: $*" >&2
    exit 1
}
test "$(id -un)" = node || fail "run as node"
dir=$(mktemp -d /tmp/optional-check.XXXXXX)
echo "Logs and fixtures: $dir"
cd "$dir"

echo '--- declared optional set (install-optional.sh --verify)'
bash "$here/../install-optional.sh" --verify >verify.log 2>&1 || {
    cat verify.log >&2
    fail "optional set verification; install it with install-optional.sh in writable mode"
}
grep 'set OK' verify.log

echo '--- R: archive and Bioconductor packages load'
Rscript -e 'suppressMessages({library(pryr); library(pcaMethods)}); cat("pryr, pcaMethods OK\n")'

echo '--- TeX: TikZ and a latexextra package'
cat >tikz.tex <<'TEX'
\documentclass{article}
\usepackage{tikz}
\usepackage{booktabs,threeparttable}
\begin{document}
\tikz \draw (0,0) -- (1,1);
\end{document}
TEX
pdflatex -interaction=nonstopmode -halt-on-error tikz.tex >pdflatex.log || fail "TikZ document; see $dir/pdflatex.log"
test -s tikz.pdf

printf 'PASS: optional set present; pryr, pcaMethods; TikZ\n'
