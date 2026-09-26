#!/usr/bin/env bash
# Install the Python, R and TeX stacks, and the AI CLIs.
#
# Run:
#   On the host, via the builder (python, r, tex):
#     bash .setup/packages.sh [python] [r] [tex] [all] [--force]
#   which runs this script as root in this workspace's own devcontainer image,
#   with the shared package volumes mounted read-write.
#   Inside the devcontainer, as node:
#     .devcontainer/install-packages.sh            # AI CLIs (same as `cli`)
#     .devcontainer/install-packages.sh cli        # AI CLIs, always @latest
#
# Inputs:  the package lists below; the dated P3M snapshot pinned in the image's
#          Rprofile.site (Dockerfile ARG CRAN_SNAPSHOT); PyPI; Bioconductor;
#          the rolling TeX Live tlnet repository; npm.
# Outputs: python -> /opt/venv; r -> the R site library; tex -> TeX Live in
#          /usr/local/texlive (with install.log and the .sandbox-installed
#          marker there); cli -> NPM_CONFIG_PREFIX. Each target ends with an
#          "... OK" line or exits nonzero.
#
# python, r and tex fill shared volumes that the devcontainer mounts; each
# refuses to run unless its install directory is a mount, so an install can
# never land in a disposable image layer. Adding a package means editing a list
# here and re-running the builder: python and r are idempotent (present packages
# are skipped unless --force), and tex adds whatever TEX_COLLECTIONS/TEX_PKGS
# name that the marked tree lacks. See docs/journal/0921a and 0925b.
#
# Deliberately no user-level layering: one declared stack per language.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: install-packages.sh [python] [r] [tex] [cli] [all] [--force]

  python    install the Python stack into /opt/venv
  r         install the R stack into the site library
  tex       install minimal TeX Live, or add missing TEX_PKGS to it
  cli       install/update the Claude Code and Codex CLIs (the default)
  all       python r tex (the host builder's stacks; not cli)
  --force   reinstall present python/r packages (not accepted with tex)

Several targets may be given. python, r and tex are normally run on the host
with bash .setup/packages.sh. Re-runs skip what is already installed.
USAGE
}

DO_PYTHON=0
DO_R=0
DO_TEX=0
DO_CLI=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
    python | py) DO_PYTHON=1 ;;
    r | R) DO_R=1 ;;
    tex) DO_TEX=1 ;;
    cli | clis) DO_CLI=1 ;;
    all)
        DO_PYTHON=1
        DO_R=1
        DO_TEX=1
        ;;
    --force | -f) FORCE=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "install-packages.sh: unknown argument '$arg'" >&2
        usage >&2
        exit 2
        ;;
    esac
done
if [ $((DO_PYTHON + DO_R + DO_TEX + DO_CLI)) -eq 0 ]; then
    DO_CLI=1
fi
if [ "$FORCE" -eq 1 ] && [ "$DO_TEX" -eq 1 ]; then
    echo "install-packages.sh: --force does not apply to tex; rebuilding TeX means a new volume." >&2
    echo "Run tex without --force, and python/r --force separately." >&2
    exit 2
fi

WORK_DIR=""
cleanup() {
    if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT
WORK_DIR=$(mktemp -d)

# An unmounted target would install into this container's writable layer and
# vanish with it, while the volume the devcontainer mounts stays unchanged.
require_mount() {
    if ! mountpoint -q "$1"; then
        echo "install-packages.sh: $1 is not a mounted volume; refusing to install into the image layer." >&2
        echo "On the host run: bash .setup/packages.sh $2" >&2
        exit 1
    fi
}

PY_PKGS=(
    numpy
    pandas
    matplotlib
    statsmodels
    scipy
    linearmodels
    scikit-learn
    openpyxl
    wrds
    mistralai
    polars
    sas7bdat
    beautifulsoup4
    lxml
    pyarrow
    pyfixest
    PyMuPDF
    pikepdf
    openai
    openassetpricing
    requests
    PyYAML
)

install_python() {
    require_mount /opt/venv python
    echo "==> Python stack (/opt/venv), ${#PY_PKGS[@]} packages"
    local args=(--no-cache-dir)
    if [ "$FORCE" -eq 1 ]; then
        args+=(--force-reinstall)
    fi
    # pip is already idempotent: satisfied requirements are skipped.
    pip install "${args[@]}" "${PY_PKGS[@]}"

    # Verify by distribution name rather than import name, so the check does not
    # need a dist->module mapping (scikit-learn/sklearn, PyMuPDF/fitz, ...).
    python3 - "${PY_PKGS[@]}" <<'PYEOF'
import sys
from importlib.metadata import PackageNotFoundError, distribution

missing = []
for name in sys.argv[1:]:
    try:
        distribution(name)
    except PackageNotFoundError:
        missing.append(name)

if missing:
    print("MISSING (python): " + ", ".join(missing))
    sys.exit(1)
print("Python stack OK (%d packages)" % (len(sys.argv) - 1))
PYEOF
}

install_r() {
    local lib
    lib=$(Rscript -e 'cat(.libPaths()[1])')
    require_mount "$lib" r
    echo "==> R stack ($lib)"
    local r_script="$WORK_DIR/install-r.R"

    # Plain Rscript, not --vanilla: the site Rprofile is what pins the repo to
    # the dated P3M snapshot and sets the R-version user agent that makes P3M
    # serve prebuilt noble binaries instead of silently falling back to source.
    cat >"$r_script" <<'REOF'
mode <- commandArgs(trailingOnly = TRUE)[1]
reinstall <- identical(Sys.getenv("STACK_FORCE"), "1")

# Econometrics/data stack. Notable entries:
#   fixest          - the regressions
#   modelsummary    - fixest models -> LaTeX/markdown/Word tables
#   sandwich+lmtest - robust/clustered SEs for base lm/glm
#   kableExtra      - LaTeX table styling on top of knitr
#   arrow           - parquet/feather I/O, interop with Python pyarrow
#   car             - regression diagnostics / hypothesis tests
#   marginaleffects - contrasts/marginal effects, pairs with modelsummary
#   BiocManager     - installs bioc_pkgs below
cran_pkgs <- c(
  "DBI", "RPostgres", "dplyr", "data.table", "keyring",
  "tidyverse", "lubridate", "readxl", "writexl",
  "lobstr", "Rcpp",
  "ggrepel", "gridExtra", "xtable",
  "doParallel", "foreach", "fst",
  "lme4", "ccaPP", "zoo",
  "fs", "getPass", "googledrive", "here", "tictoc", "tm",
  "languageserver",
  "fixest", "OpenSourceAP.DownloadR",
  "modelsummary", "sandwich", "lmtest", "kableExtra",
  "arrow", "car", "marginaleffects",
  "BiocManager", "dotenv", "extrafont", "fuzzyjoin", "huxtable", "janitor",
  "latex2exp", "lexicon", "quanteda.textstats", "roll", "splitstackshape",
  "strucchange"
)

# pryr is archived on CRAN, so its build deps (lobstr, Rcpp) come from the
# snapshot above and the package itself is pinned from the archive.
archive_pkgs <- c(
  pryr = "https://cran.r-project.org/src/contrib/Archive/pryr/pryr_0.1.6.tar.gz"
)

# Bioconductor release matching R 4.5. update = FALSE matters: the default
# would upgrade snapshot-pinned CRAN packages past the P3M date.
bioc_version <- "3.22"
bioc_pkgs <- c("pcaMethods")

all_pkgs <- c(cran_pkgs, names(archive_pkgs), bioc_pkgs)

# Verification runs in a fresh process (mode "verify"): a namespace loaded
# before a --force reinstall would otherwise pass from memory.
if (identical(mode, "verify")) {
  loads <- function(p) suppressWarnings(requireNamespace(p, quietly = TRUE))
  missing <- all_pkgs[!vapply(all_pkgs, loads, logical(1))]
  if (length(missing)) {
    cat("MISSING (r): ", paste(missing, collapse = ", "), "\n", sep = "")
    quit(status = 1)
  }
  cat(sprintf("R stack OK (%d packages)\n", length(all_pkgs)))
  quit(status = 0)
}

# Installed on disk, without loading anything into this process.
have <- function(p) nzchar(system.file(package = p))
wanted <- function(p) reinstall || !have(p)

# install.packages() reports download and compile failures as *warnings* and
# returns normally, so nothing downstream notices. Print the one thing worth
# reading and say where to look.
report_failure <- function(failed, context) {
  cat("\n---\n")
  cat("FAILED (", context, "): ", paste(failed, collapse = ", "), "\n", sep = "")
  cat("Look above for the first 'cannot open URL' / 'Couldn't connect' line.\n")
  cat("It names the host or package that failed; the full log is above.\n")
}

# Keep going on a failure here so the run still reaches the summary below,
# instead of halting R on the first error and burying the cause.
try_install <- function(nm, expr) {
  tryCatch(expr, error = function(e) {
    cat("ERROR installing ", nm, ": ", conditionMessage(e), "\n", sep = "")
  })
}

todo <- cran_pkgs[vapply(cran_pkgs, wanted, logical(1))]
if (length(todo)) {
  cat("Installing from P3M snapshot:", paste(todo, collapse = ", "), "\n")
  install.packages(todo)

  # Stop here rather than cascading: pryr and pcaMethods need this batch.
  # Continuing past a failed batch buries one network error under a pile of
  # missing-dependency errors.
  failed <- todo[!vapply(todo, have, logical(1))]
  if (length(failed)) {
    report_failure(failed, sprintf("%d of %d from P3M", length(failed), length(todo)))
    quit(status = 1)
  }
} else {
  cat("CRAN packages already present\n")
}

for (nm in names(archive_pkgs)) {
  if (wanted(nm)) {
    cat("Installing archived source:", nm, "\n")
    try_install(nm, install.packages(archive_pkgs[[nm]], repos = NULL, type = "source"))
  }
}

todo <- bioc_pkgs[vapply(bioc_pkgs, wanted, logical(1))]
if (length(todo)) {
  cat("Installing from Bioconductor ", bioc_version, ": ",
      paste(todo, collapse = ", "), "\n", sep = "")
  try_install("Bioconductor", BiocManager::install(
    todo, version = bioc_version, ask = FALSE, update = FALSE, force = reinstall
  ))
}

# Fail loudly on a partial install rather than leaving a half-built stack.
missing <- all_pkgs[!vapply(all_pkgs, have, logical(1))]
if (length(missing)) {
  report_failure(missing, "R stack incomplete")
  quit(status = 1)
}
REOF

    STACK_FORCE="$FORCE" Rscript "$r_script" install
    Rscript "$r_script" verify
}

# TeX Live: minimal, pdfLaTeX-only (docs/journal/0925b decision 3). The year
# and platform come from the image's /usr/local/texlive-bin symlink, which the
# Dockerfile builds from TEXLIVE_YEAR, so they cannot drift from the consumer.
#
# scheme-small's own packages are installed, but because the profile names
# collections, install-tl ignores the scheme's collection list: TEX_COLLECTIONS
# must therefore spell out all of them (install-tl manual, "Profiles").
# LuaTeX stays: luatex/luahbtex are in collection-basic, which nothing can drop.
TEX_PREFIX=/usr/local/texlive
TEX_MARKER="$TEX_PREFIX/.sandbox-installed"
TEX_LOG="$TEX_PREFIX/install.log"
TEX_REPOSITORY=https://mirror.ctan.org/systems/texlive/tlnet
TEX_COLLECTIONS=(
    # scheme-small's collections, minus collection-xetex
    collection-basic
    collection-latex
    collection-latexrecommended
    collection-metapost
    # additions
    collection-latexextra
    collection-fontsrecommended
    collection-bibtexextra # biblatex, biber
    collection-pictures    # tikz
    collection-mathscience
    collection-fontsextra # fontawesome5
)
TEX_EXCLUDED=(collection-xetex)
# Single packages on top of the collections. Adding a name here and re-running
# `packages.sh tex` installs it with tlmgr. latexindent's Perl dependencies are
# in the Dockerfile; latexmk is LaTeX Workshop's default recipe.
TEX_PKGS=(
    latexindent
    latexmk
)

# Package names recorded in the tree's own database; no network needed.
tex_installed() {
    awk '$1 == "name" { print $2 }' "$TEX_PREFIX/$1/tlpkg/texlive.tlpdb"
}

tex_missing() {
    local year=$1 installed pkg
    installed=$(tex_installed "$year")
    for pkg in "${TEX_COLLECTIONS[@]}" "${TEX_PKGS[@]}"; do
        if ! grep -qxF "$pkg" <<<"$installed"; then
            echo "$pkg"
        fi
    done
}

# tlmgr install for what is missing. tlnet is rolling, so an old tlmgr may
# refuse until it updates itself; that is the one update allowed here. Never
# `tlmgr update --all`: existing packages keep their install-time versions.
tex_add_missing() {
    local year=$1 out
    local missing=()
    mapfile -t missing < <(tex_missing "$year")
    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi
    echo "tlmgr install ${missing[*]}"
    if ! out=$(tlmgr install "${missing[@]}" 2>&1); then
        echo "$out"
        if grep -q 'tlmgr itself needs to be updated' <<<"$out"; then
            tlmgr update --self
            tlmgr install "${missing[@]}"
        else
            return 1
        fi
    else
        echo "$out"
    fi
    mapfile -t missing < <(tex_missing "$year")
    if [ ${#missing[@]} -gt 0 ]; then
        echo "MISSING (tex): ${missing[*]}" >&2
        return 1
    fi
}

# pdflatex + biber, latexindent, and a LyX export, all against this tree.
tex_smoke() {
    local dir="$WORK_DIR/tex-smoke"
    mkdir -p "$dir/lyx-userdir"
    cd "$dir"
    cat >references.bib <<'BIB'
@book{knuth1984,
  author = {Donald E. Knuth},
  title = {The TeXbook},
  year = {1984},
  publisher = {Addison-Wesley}
}
BIB
    cat >smoke.tex <<'TEX'
\documentclass{article}
\usepackage{amsmath}
\usepackage{tikz}
\usepackage[backend=biber,style=authoryear]{biblatex}
\addbibresource{references.bib}
\begin{document}
TeX Live smoke test: $x^2$, see \autocite{knuth1984}.
\tikz \draw (0,0) -- (1,1);
\printbibliography
\end{document}
TEX
    pdflatex -interaction=nonstopmode -halt-on-error smoke.tex >/dev/null
    biber smoke >/dev/null
    pdflatex -interaction=nonstopmode -halt-on-error smoke.tex >/dev/null
    pdftotext smoke.pdf smoke.txt
    grep -q Knuth smoke.txt
    latexindent smoke.tex >/dev/null
    latexmk -v >/dev/null
    echo "pdflatex, biber, latexindent, latexmk OK"

    # LyX run as root here, so it gets a private userdir; configure.py is
    # what tex-refresh runs for node in the consuming container.
    (cd lyx-userdir && python3 /usr/local/share/lyx/configure.py >../lyx-configure.log 2>&1)
    tex2lyx -userdir "$dir/lyx-userdir" -f smoke.tex smoke.lyx >/dev/null 2>&1
    QT_QPA_PLATFORM=offscreen lyx -userdir "$dir/lyx-userdir" -batch -f all \
        -E pdf2 lyx-smoke.pdf smoke.lyx >lyx-export.log 2>&1
    pdftotext lyx-smoke.pdf lyx-smoke.txt
    grep -q Knuth lyx-smoke.txt
    echo "LyX export OK"
    cd - >/dev/null
}

tex_write_marker() {
    local year=$1 platform=$2 installed=$3
    {
        echo "installed $installed"
        echo "verified $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "year $year"
        echo "platform $platform"
        echo "repository $TEX_REPOSITORY"
        echo "scheme scheme-small"
        echo "collections ${TEX_COLLECTIONS[*]}"
        echo "excluded ${TEX_EXCLUDED[*]}"
        echo "packages ${TEX_PKGS[*]}"
    } >"$TEX_MARKER.tmp"
    mv "$TEX_MARKER.tmp" "$TEX_MARKER"
}

tex_fresh_install() {
    local year=$1 platform=$2 repository_year coll
    cd "$WORK_DIR"
    wget -q -O texlive.tlpdb.xz "$TEX_REPOSITORY/tlpkg/texlive.tlpdb.xz"
    xz -d texlive.tlpdb.xz
    repository_year=$(awk '$1 == "depend" && $2 ~ /^release\/[0-9]+$/ {sub(/^release\//, "", $2); print $2; exit}' texlive.tlpdb)
    if [ "$repository_year" != "$year" ]; then
        echo "Repository release '$repository_year' does not match the image's TeX Live $year." >&2
        echo "Bump TEXLIVE_YEAR in the Dockerfile and the volume name together." >&2
        exit 1
    fi
    wget -q -O install-tl.tar.gz "$TEX_REPOSITORY/install-tl-unx.tar.gz"
    tar -xzf install-tl.tar.gz
    {
        echo "selected_scheme scheme-small"
        for coll in "${TEX_COLLECTIONS[@]}"; do echo "$coll 1"; done
        for coll in "${TEX_EXCLUDED[@]}"; do echo "$coll 0"; done
        cat <<PROFILE
binary_$platform 1
TEXDIR $TEX_PREFIX/$year
TEXMFLOCAL $TEX_PREFIX/texmf-local
TEXMFSYSCONFIG $TEX_PREFIX/$year/texmf-config
TEXMFSYSVAR $TEX_PREFIX/$year/texmf-var
TEXMFHOME ~/texmf
TEXMFCONFIG ~/.texlive$year/texmf-config
TEXMFVAR ~/.texlive$year/texmf-var
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
instopt_adjustpath 0
instopt_portable 0
PROFILE
    } >texlive.profile

    # From here on the log lives in the volume, so a failure is inspectable
    # after the builder container is gone. The preflight above writes nothing
    # there, so a failed download never makes the volume look installed.
    (
        set -o errtrace
        trap 'echo "Installation/check failed. Inspect $TEX_LOG; the tree has been preserved." >&2' ERR
        perl ./install-tl-*/install-tl -profile "$WORK_DIR/texlive.profile" -repository "$TEX_REPOSITORY"
        tex_add_missing "$year"
        fmtutil-sys --all
        updmap-sys
        if [ -e "$TEX_PREFIX/$year/bin/$platform/xetex" ]; then
            echo "note: xetex was pulled in by a dependency despite ${TEX_EXCLUDED[*]}"
        fi
        tex_smoke
    ) 2>&1 | tee "$TEX_LOG"
    tex_write_marker "$year" "$platform" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

install_tex() {
    require_mount "$TEX_PREFIX" tex
    local bindir year platform installed
    bindir=$(readlink /usr/local/texlive-bin) # $TEX_PREFIX/<year>/bin/<platform>
    platform=${bindir##*/}
    year=${bindir#"$TEX_PREFIX"/}
    year=${year%%/*}
    echo "==> TeX Live $year ($TEX_PREFIX, $platform)"

    if [ -f "$TEX_MARKER" ]; then
        local missing=()
        mapfile -t missing < <(tex_missing "$year")
        if [ ${#missing[@]} -eq 0 ]; then
            echo "TeX stack OK (marked; nothing to add)"
            return 0
        fi
        installed=$(awk '$1 == "installed" { print $2 }' "$TEX_MARKER")
        # The marker stays through a failed add: the base tree is still sound,
        # and re-running retries the add.
        (
            set -o errtrace
            trap 'echo "Adding packages failed; the marker and base tree are unchanged. Inspect $TEX_LOG." >&2' ERR
            echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ): adding ${missing[*]}"
            tex_add_missing "$year"
            tex_smoke
        ) 2>&1 | tee -a "$TEX_LOG"
        tex_write_marker "$year" "$platform" "$installed"
    elif [ -z "$(find "$TEX_PREFIX" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
        tex_fresh_install "$year" "$platform"
    else
        echo "TeX volume is nonempty but has no $TEX_MARKER: an earlier install failed." >&2
        echo "Inspect $TEX_LOG in the volume. Retrying needs an explicit decision to" >&2
        echo "recreate the volume; this script will not overwrite it." >&2
        exit 1
    fi
    echo "TeX stack OK (${#TEX_COLLECTIONS[@]} collections, ${#TEX_PKGS[@]} extra packages)"
}

CLI_PKGS=(
    @anthropic-ai/claude-code
    @openai/codex
)

# Always @latest, deliberately: unlike the analysis stacks there is no snapshot
# to pin against, and this is the command you reach for *because* something is
# out of date. NPM_CONFIG_PREFIX is a volume, so what this installs outlives the
# container - a rebuild no longer reverts an update made here.
#
# Neither npm-managed CLI should be assumed to update itself. --force is not
# consulted because @latest is already the strongest request available.
install_cli() {
    echo "==> AI CLIs (${NPM_CONFIG_PREFIX:-npm global}), ${#CLI_PKGS[@]} packages"
    local pinned=()
    local pkg
    for pkg in "${CLI_PKGS[@]}"; do
        pinned+=("${pkg}@latest")
    done
    npm install -g "${pinned[@]}"

    local missing=()
    for pkg in "${CLI_PKGS[@]}"; do
        # `npm ls -g` rather than `command -v`: the bin name does not always
        # match the package name, and we are asserting the install, not the PATH.
        if ! npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "MISSING (cli): ${missing[*]}" >&2
        return 1
    fi
    echo "AI CLIs OK (${#CLI_PKGS[@]} packages)"
    echo "Re-run test-agent-policy.sh to verify connector policy against them."
}

if [ "$DO_PYTHON" -eq 1 ]; then install_python; fi
if [ "$DO_R" -eq 1 ]; then install_r; fi
if [ "$DO_TEX" -eq 1 ]; then install_tex; fi
if [ "$DO_CLI" -eq 1 ]; then install_cli; fi

echo "Done."
