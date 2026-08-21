#!/usr/bin/env bash
# Install the optional Python and R analysis stacks into the running container.
#
# These used to be Dockerfile layers. They are a script instead so the stack is
# extensible without a rebuild: add a package here, re-run, done. It also makes
# a broken package recoverable - the old shared-library objection ("break it and
# you need a rebuild") stops applying once reinstalling is one command.
#
# Reproducibility is unchanged: pip resolves against PyPI, R against the dated
# P3M snapshot pinned in Rprofile.site (Dockerfile ARG CRAN_SNAPSHOT). What is
# no longer baked in is *state* - a freshly built container has no stack until
# this runs, costing minutes once instead of being a cached image layer.
#
# Installs go to the existing shared locations (/opt/venv, the site R library),
# both made node-writable at build time. Deliberately no user-level layering.
#
# Usage:
#   .devcontainer/install-packages.sh           # everything
#   .devcontainer/install-packages.sh python    # Python only
#   .devcontainer/install-packages.sh r         # R only
#   .devcontainer/install-packages.sh cli       # AI CLIs only (always @latest)
#   .devcontainer/install-packages.sh --force   # reinstall even if present
#
# Re-runs are cheap: already-installed packages are skipped unless --force.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: install-packages.sh [python|r|cli|all] [--force]

  python    install the Python stack into /opt/venv
  r         install the R stack into the site library
  cli       install/update the Claude Code and Codex CLIs
  all       all three (default)
  --force   reinstall even if a package is already present

Re-runs are cheap: already-installed packages are skipped unless --force.
USAGE
}

TARGET=all
FORCE=0
for arg in "$@"; do
    case "$arg" in
    python | py) TARGET=python ;;
    r | R) TARGET=r ;;
    cli | clis) TARGET=cli ;;
    all | both) TARGET=all ;;
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

R_SCRIPT=""
cleanup() {
    if [ -n "$R_SCRIPT" ]; then rm -f "$R_SCRIPT"; fi
}
trap cleanup EXIT

install_r() {
    echo "==> R stack ($(Rscript -e 'cat(.libPaths()[1])'))"
    R_SCRIPT=$(mktemp)
    local r_script="$R_SCRIPT"

    # Plain Rscript, not --vanilla: the site Rprofile is what pins the repo to
    # the dated P3M snapshot and sets the R-version user agent that makes P3M
    # serve prebuilt noble binaries instead of silently falling back to source.
    cat >"$r_script" <<'REOF'
reinstall <- identical(Sys.getenv("STACK_FORCE"), "1")

# Econometrics/data stack. Notable entries:
#   fixest          - the regressions
#   modelsummary    - fixest models -> LaTeX/markdown/Word tables
#   sandwich+lmtest - robust/clustered SEs for base lm/glm
#   kableExtra      - LaTeX table styling on top of knitr
#   arrow           - parquet/feather I/O, interop with Python pyarrow
#   car             - regression diagnostics / hypothesis tests
#   marginaleffects - contrasts/marginal effects, pairs with modelsummary
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
  "arrow", "car", "marginaleffects"
)

# pryr is archived on CRAN, so its build deps (lobstr, Rcpp) come from the
# snapshot above and the package itself is pinned from the archive. This is the
# only thing here that talks to cran.r-project.org rather than P3M.
archive_pkgs <- c(
  pryr = "https://cran.r-project.org/src/contrib/Archive/pryr/pryr_0.1.6.tar.gz"
)

have <- function(p) requireNamespace(p, quietly = TRUE)
wanted <- function(p) reinstall || !have(p)

# install.packages() reports download and compile failures as *warnings* and
# returns normally, so nothing downstream notices. Print the one thing worth
# reading and say where to look.
report_failure <- function(failed, context) {
  cat("\n---\n")
  cat("FAILED (", context, "): ", paste(failed, collapse = ", "), "\n", sep = "")
  cat("Look above for the first 'cannot open URL' / 'Couldn't connect' line.\n")
  cat("If it names a host, that host is almost certainly not in the firewall\n")
  cat("allowlist - see .devcontainer/init-firewall.sh. Note that CDN-fronted\n")
  cat("hosts can rotate IPs after the allowlist is pinned at container start.\n")
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

  # Stop here rather than cascading: pryr needs lobstr/Rcpp/stringr from this
  # batch. Continuing past a failed batch buries one network error under a pile
  # of missing-dependency errors.
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

# Fail loudly on a partial install rather than leaving a half-built stack.
all_pkgs <- c(cran_pkgs, names(archive_pkgs))
missing <- all_pkgs[!vapply(all_pkgs, have, logical(1))]
if (length(missing)) {
  report_failure(missing, "R stack incomplete")
  quit(status = 1)
}
cat(sprintf("R stack OK (%d packages)\n", length(all_pkgs)))
REOF

    STACK_FORCE="$FORCE" Rscript "$r_script"
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

case "$TARGET" in
python) install_python ;;
r) install_r ;;
cli) install_cli ;;
all)
    install_python
    install_r
    install_cli
    ;;
esac

echo "Done."
