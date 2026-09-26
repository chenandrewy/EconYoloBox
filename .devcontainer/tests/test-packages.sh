#!/usr/bin/env bash
# Run as node in a rebuilt devcontainer: bash .devcontainer/tests/test-packages.sh
# Inputs: the shared R, Python and TeX volumes, mounted read-only by
#   devcontainer.json; install-packages.sh (its --verify mode holds the declared
#   package lists). pip reaches PyPI only to prove an install is refused.
# Outputs: fixtures and logs in a new /tmp/packages-check.* directory (printed
#   first); a PASS line and exit 0, or a FAIL line and nonzero exit.
# shellcheck disable=SC2016 # single-quoted R and sh code expands its own $
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fail() {
    echo "FAIL: $*" >&2
    exit 1
}
test "$(id -un)" = node || fail "run as node"
dir=$(mktemp -d /tmp/packages-check.XXXXXX)
echo "Logs and fixtures: $dir"
cd "$dir"

site_library=$(Rscript -e 'cat(.libPaths()[1])')
case "$site_library" in
*/lib/R/site-library) ;;
*) fail "R's first library is $site_library, not the mounted site-library" ;;
esac

echo '--- read-only mounts'
for mount in /opt/venv "$site_library" /usr/local/texlive; do
    findmnt -n -o OPTIONS -T "$mount" | tr ',' '\n' | grep -qx ro || fail "$mount is not mounted read-only"
    if touch "$mount/consumer-write-test" 2>/dev/null; then
        fail "consumer can write to $mount"
    fi
done
bash "$here/../install-packages.sh" python >refuse-python.log 2>&1 && fail "install-packages.sh python ran in a consumer"
grep -q 'mounted read-only' refuse-python.log || fail "install-packages.sh python did not explain the refusal"

echo '--- declared stacks (install-packages.sh --verify)'
bash "$here/../install-packages.sh" --verify python r tex >verify.log 2>&1 || {
    cat verify.log >&2
    fail "declared stack verification"
}
grep 'stack OK' verify.log

echo '--- every installed R package loads'
Rscript -e 'cat(rownames(installed.packages(lib.loc = .libPaths()[1])), sep = "\n")' >r-packages.txt
xargs -P 4 -n 1 sh -c 'Rscript -e "suppressMessages(library($1))" >/dev/null 2>&1 || echo "$1"' _ \
    <r-packages.txt >r-load-failures.txt
if [ -s r-load-failures.txt ]; then
    fail "R packages failed to load: $(tr '\n' ' ' <r-load-failures.txt)"
fi
echo "$(wc -l <r-packages.txt) R packages load"

echo '--- fixest regression'
Rscript -e '
suppressMessages(library(fixest))
set.seed(1)
d <- data.frame(g = rep(1:20, each = 50), x = rnorm(1000))
d$y <- 2 * d$x + d$g + rnorm(1000, sd = 0.1)
m <- feols(y ~ x | g, d, cluster = ~g)
stopifnot(abs(coef(m)[["x"]] - 2) < 0.01, se(m)[["x"]] > 0)
cat("fixest: x =", round(coef(m)[["x"]], 4), "\n")'

echo '--- parquet round trip: pyarrow -> arrow -> pyarrow'
python3 - <<'PY'
import pyarrow as pa, pyarrow.parquet as pq
pq.write_table(pa.table({"id": [1, 2, 3], "value": [0.5, 1.5, 2.5], "name": ["a", "b", "c"]}), "from-python.parquet")
PY
Rscript -e '
suppressMessages(library(arrow))
d <- as.data.frame(read_parquet("from-python.parquet"))
stopifnot(identical(d$name, c("a", "b", "c")), all.equal(d$value, c(0.5, 1.5, 2.5)))
d$doubled <- d$value * 2
write_parquet(d, "from-r.parquet")'
python3 - <<'PY'
import pyarrow.parquet as pq
t = pq.read_table("from-r.parquet").to_pydict()
assert t["doubled"] == [1.0, 3.0, 5.0], t
assert t["name"] == ["a", "b", "c"], t
print("parquet round trip OK")
PY

echo '--- installs of absent packages are refused'
r_absent=$(Rscript -e 'p <- c("praise", "fortunes", "cowsay", "beepr")
a <- p[!nzchar(vapply(p, function(x) system.file(package = x), ""))]
cat(a[1][length(a) > 0])')
[ -n "$r_absent" ] || fail "no absent R candidate package"
if Rscript -e "install.packages('$r_absent')" >r-install.log 2>&1; then
    fail "install.packages('$r_absent') succeeded"
fi
Rscript -e "quit(status = requireNamespace('$r_absent', quietly = TRUE))" ||
    fail "$r_absent became loadable after a refused install"
grep -q 'not writable' r-install.log || fail "R refusal was not about writability; see $dir/r-install.log"
echo "R: install.packages('$r_absent') refused"

py_absent=$(python3 - <<'PY'
from importlib.metadata import PackageNotFoundError, distribution
for name in ("pyjokes", "cowsay", "art", "emoji"):
    try:
        distribution(name)
    except PackageNotFoundError:
        print(name)
        break
PY
)
[ -n "$py_absent" ] || fail "no absent Python candidate package"
if pip install --no-deps --no-cache-dir "$py_absent" >pip-install.log 2>&1; then
    fail "pip install $py_absent succeeded"
fi
python3 -c "import importlib.metadata as m, sys; m.distribution(sys.argv[1])" "$py_absent" 2>/dev/null &&
    fail "$py_absent became installed after a refused pip install"
echo "Python: pip install $py_absent refused"

echo '--- TeX: user trees, binaries'
for tree in TEXMFVAR TEXMFCONFIG TEXMFHOME; do
    path=$(kpsewhich -var-value="$tree")
    case "$path" in
    "$HOME"/*)
        mkdir -p "$path"
        test -w "$path"
        ;;
    *) fail "$tree is outside the user home: $path" ;;
    esac
done
for binary in pdflatex biber; do
    ldd "$(command -v "$binary")" >"$binary.ldd" 2>&1 || true
    if grep -q 'not found' "$binary.ldd"; then
        cat "$binary.ldd" >&2
        fail "$binary has missing libraries"
    fi
done
if command -v xelatex >/dev/null 2>&1; then
    echo "note: xelatex is present; the minimal TeX volume should not have it"
fi

cat >references.bib <<'BIB'
@book{knuth1984,
  author = {Donald E. Knuth},
  title = {The TeXbook},
  year = {1984},
  publisher = {Addison-Wesley}
}
BIB
cat >document.tex <<'TEX'
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

echo '--- TeX: pdflatex + biber, latexindent, latexmk'
pdflatex -interaction=nonstopmode -halt-on-error document.tex >pdflatex-first.log
biber document >biber-run.log
pdflatex -interaction=nonstopmode -halt-on-error document.tex >pdflatex-second.log
pdflatex -interaction=nonstopmode -halt-on-error document.tex >pdflatex-final.log
test -s document.pdf
if grep -Eiq 'undefined|Please \(re\)run Biber|Rerun to get cross-references right' document.log; then
    fail "unresolved references"
fi
pdftotext document.pdf document.txt
grep -q 'Knuth' document.txt
grep -q '1984' document.txt
latexindent document.tex >indented.tex
test -s indented.tex
latexmk -v >latexmk-version.log

echo '--- LyX: refresh, import, export'
tex-refresh >lyx-refresh.log 2>&1
# A second scan must replace stale generated detection, preserving preferences.
printf '\nSTALE_DETECTION_SENTINEL\n' >>"$HOME/.lyx/lyxrc.defaults"
tex-refresh >lyx-refresh-second.log 2>&1
if grep -q STALE_DETECTION_SENTINEL "$HOME/.lyx/lyxrc.defaults"; then
    fail "stale LyX converter detection survived refresh"
fi
export QT_QPA_PLATFORM=offscreen
tex2lyx -f document.tex document.lyx >lyx-import.log 2>&1
test -s document.lyx
lyx -batch -f all -E pdflatex lyx-export.tex document.lyx >lyx-tex-export.log 2>&1
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex >lyx-pdflatex-first.log
biber lyx-export >lyx-biber.log
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex >lyx-pdflatex-second.log
pdflatex -interaction=nonstopmode -halt-on-error lyx-export.tex >lyx-pdflatex-final.log
if grep -Eiq 'undefined|Please \(re\)run Biber|Rerun to get cross-references right' lyx-export.log; then
    fail "unresolved LyX export references"
fi
lyx -batch -f all -E pdf2 lyx-direct.pdf document.lyx >lyx-pdf-export.log 2>&1
test -s lyx-direct.pdf
pdftotext lyx-direct.pdf lyx-direct.txt
grep -q 'Knuth' lyx-direct.txt
grep -q '1984' lyx-direct.txt

printf 'PASS: %s; read-only R/Python/TeX volumes; declared stacks; %s R packages load; fixest; parquet round trip; installs refused; pdflatex, biber, latexindent, latexmk, LyX\n' \
    "$(dpkg --print-architecture)" "$(wc -l <r-packages.txt)"
