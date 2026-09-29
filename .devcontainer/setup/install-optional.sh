#!/usr/bin/env bash
# Install the optional package set into the shared R, Python and TeX volumes.
#
# Run, inside the devcontainer as ubuntu, in normie mode (on the host,
# `ybcode --normie` or `bbe --normie`):
#   bash .devcontainer/setup/install-optional.sh              # python r tex
#   bash .devcontainer/setup/install-optional.sh r            # one stack
#   bash .devcontainer/setup/install-optional.sh --verify     # check only; any mode
#
# Inputs:  the lists below; PyPI; the dated P3M snapshot pinned in the image's
#          Rprofile.site; the CRAN archive (pryr); Bioconductor; the TeX Live
#          repository recorded in the tree (tlnet).
# Outputs: packages added to /opt/venv, the R site library and
#          /usr/local/texlive; an "... OK" line per stack, or MISSING lines and
#          a nonzero exit.
#
# The base stacks come from .devcontainer/setup/install-base.sh, in the same mode and with the
# same check; this is the rest of what we use, installed by the user while
# watching (docs/journal/0926a, 0926e).
# The yolobox's own tools and tests never depend on it. Each step is the
# ordinary command - pip install, install.packages(), BiocManager::install(),
# tlmgr install - printed before it runs, so this script also shows how to add
# one package by hand. What is present is skipped. A package that proves
# generally useful belongs in these lists; one installed ad hoc and not added
# here is lost when its volume is rebuilt.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: install-optional.sh [python] [r] [tex] [--verify]

With no target, all three. --verify only checks, and works in any mode.
Installing needs normie mode: on the host, ybcode --normie or bbe --normie.
USAGE
}

DO_PYTHON=0
DO_R=0
DO_TEX=0
VERIFY=0
for arg in "$@"; do
    case "$arg" in
    python | py) DO_PYTHON=1 ;;
    r | R) DO_R=1 ;;
    tex) DO_TEX=1 ;;
    --verify) VERIFY=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "install-optional.sh: unknown argument '$arg'" >&2
        usage >&2
        exit 2
        ;;
    esac
done
if [ $((DO_PYTHON + DO_R + DO_TEX)) -eq 0 ]; then
    DO_PYTHON=1
    DO_R=1
    DO_TEX=1
fi

PY_PKGS=(
    scipy
    linearmodels
    scikit-learn
    polars
    pyarrow
    openpyxl
    sas7bdat
    wrds
    openassetpricing
    beautifulsoup4
    lxml
    PyYAML
)

# From the P3M snapshot, so versions match the base.
R_PKGS=(
    DBI RPostgres dplyr keyring
    lubridate readxl writexl
    lobstr Rcpp
    ggrepel gridExtra xtable
    doParallel foreach fst
    lme4 ccaPP zoo
    fs getPass googledrive here tictoc tm
    OpenSourceAP.DownloadR
    kableExtra arrow car marginaleffects
    BiocManager dotenv extrafont fuzzyjoin huxtable janitor
    latex2exp lexicon quanteda.textstats roll splitstackshape
    strucchange
)
# Archived on CRAN; its build deps (lobstr, Rcpp) come from R_PKGS.
R_ARCHIVE_PKG=pryr
R_ARCHIVE_URL=https://cran.r-project.org/src/contrib/Archive/pryr/pryr_0.1.6.tar.gz
# Bioconductor release matching R 4.5. update = FALSE matters: the default
# would upgrade snapshot-pinned CRAN packages past the P3M date.
BIOC_VERSION=3.22
BIOC_PKGS=(pcaMethods)

TEX_PKGS=(
    collection-latexextra
    collection-fontsrecommended
    collection-pictures # tikz
    collection-mathscience
    collection-fontsextra # fontawesome5
    # goners project: LuaLaTeX style branch and LyX journal header.
    # undertilde is excluded: CTAN does not include it in TeX Live.
    luacolor
    lua-ul
    mathdots
)

TEX_PREFIX=/usr/local/texlive

run() {
    printf '+ %s\n' "$*"
    "$@"
}

# Normie mode is the user's switch: the three mounts writable, which only
# ybox --normie can arrange, at creation. Checked on the container itself.
require_install_mode() {
    local mount problems=()
    [ "$(id -un)" = ubuntu ] || problems+=("run as ubuntu, not $(id -un)")
    for mount in "$@"; do
        if ! mountpoint -q "$mount"; then
            problems+=("$mount is not a mounted volume")
        elif findmnt -n -o OPTIONS -T "$mount" | tr ',' '\n' | grep -qx ro; then
            problems+=("$mount is mounted read-only")
        elif [ ! -w "$mount" ]; then
            problems+=("$mount is not writable by $(id -un) (see .devcontainer/setup/README.md, \"Volume ownership\")")
        fi
    done
    # post-start.sh leaves this marker when it skips the firewall. Armed, the
    # firewall blocks PyPI, P3M, Bioconductor and CTAN, so every install fails.
    [ -f /tmp/FIREWALL-WINDOW-OPEN ] || problems+=("the firewall is armed; PyPI, P3M, Bioconductor and CTAN are blocked")
    if [ ${#problems[@]} -gt 0 ]; then
        echo "install-optional.sh: not in normie mode:" >&2
        printf '  - %s\n' "${problems[@]}" >&2
        echo 'Switch to normie mode: on the host, ybcode --normie (or bbe --normie),' >&2
        echo 'and back to YOLO mode afterwards: ybcode or bbe; ybox --stop --normie.' >&2
        exit 1
    fi
}

python_missing() {
    python3 - "$@" <<'PYEOF'
import sys
from importlib.metadata import PackageNotFoundError, distribution

for name in sys.argv[1:]:
    try:
        distribution(name)
    except PackageNotFoundError:
        print(name)
PYEOF
}

optional_python() {
    echo "==> Python optional set (/opt/venv), ${#PY_PKGS[@]} packages"
    local missing=()
    mapfile -t missing < <(python_missing "${PY_PKGS[@]}")
    if [ "$VERIFY" -eq 0 ] && [ ${#missing[@]} -gt 0 ]; then
        # pip resolves against current PyPI and may upgrade a base package
        # to satisfy one of these; that is why this mode is supervised.
        run pip install --no-cache-dir "${missing[@]}"
        mapfile -t missing < <(python_missing "${PY_PKGS[@]}")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "MISSING (python optional): ${missing[*]}" >&2
        return 1
    fi
    # The base must still import after pip has had its way with dependencies.
    python3 -c 'import numpy, pandas, scipy, sklearn, polars, pyarrow, pyfixest' ||
        { echo "BROKEN (python): imports failed after install" >&2; return 1; }
    echo "Python optional set OK (${#PY_PKGS[@]} packages)"
}

r_missing() {
    # On disk, without loading anything.
    Rscript -e 'for (p in commandArgs(TRUE)) if (!nzchar(system.file(package = p))) cat(p, "\n", sep = "")' "$@"
}

optional_r() {
    local lib
    lib=$(Rscript -e 'cat(.libPaths()[1])')
    echo "==> R optional set ($lib)"
    local all=("${R_PKGS[@]}" "$R_ARCHIVE_PKG" "${BIOC_PKGS[@]}") missing=()
    mapfile -t missing < <(r_missing "${all[@]}")
    if [ "$VERIFY" -eq 0 ] && [ ${#missing[@]} -gt 0 ]; then
        case "$lib" in
        */lib/R/site-library) ;;
        *)
            echo "install-optional.sh: R's first library is $lib, not the site library; refusing." >&2
            return 1
            ;;
        esac
        local cran=() pkg quoted
        for pkg in "${missing[@]}"; do
            case " ${R_PKGS[*]} " in *" $pkg "*) cran+=("\"$pkg\"") ;; esac
        done
        if [ ${#cran[@]} -gt 0 ]; then
            quoted=$(IFS=,; echo "${cran[*]}")
            run Rscript -e "install.packages(c(${quoted//,/, }))"
        fi
        if [[ " ${missing[*]} " == *" $R_ARCHIVE_PKG "* ]]; then
            run Rscript -e "install.packages(\"$R_ARCHIVE_URL\", repos = NULL, type = \"source\")"
        fi
        local bioc=()
        for pkg in "${missing[@]}"; do
            case " ${BIOC_PKGS[*]} " in *" $pkg "*) bioc+=("\"$pkg\"") ;; esac
        done
        if [ ${#bioc[@]} -gt 0 ]; then
            quoted=$(IFS=,; echo "${bioc[*]}")
            run Rscript -e "BiocManager::install(c(${quoted//,/, }), version = \"$BIOC_VERSION\", ask = FALSE, update = FALSE)"
        fi
        # install.packages() reports failures as warnings, so recheck on disk.
        mapfile -t missing < <(r_missing "${all[@]}")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "MISSING (r optional): ${missing[*]}" >&2
        echo "An install failure is reported as a warning above; look for the first 'cannot open URL'." >&2
        return 1
    fi
    echo "R optional set OK (${#all[@]} packages)"
}

tex_missing() {
    local db installed pkg
    db=$(find "$TEX_PREFIX" -mindepth 3 -maxdepth 3 -path '*/tlpkg/texlive.tlpdb' -print -quit)
    [ -n "$db" ] || { printf '%s\n' "${TEX_PKGS[@]}"; return; }
    installed=$(awk '$1 == "name" { print $2 }' "$db")
    for pkg in "${TEX_PKGS[@]}"; do
        grep -qxF "$pkg" <<<"$installed" || echo "$pkg"
    done
}

optional_tex() {
    echo "==> TeX optional set ($TEX_PREFIX), ${#TEX_PKGS[@]} items"
    local missing=() out
    mapfile -t missing < <(tex_missing)
    if [ "$VERIFY" -eq 0 ] && [ ${#missing[@]} -gt 0 ]; then
        # tlnet is rolling, so an old tlmgr may refuse until it updates itself.
        # Never `tlmgr update --all`: the base keeps its install-time versions.
        printf '+ %s\n' "tlmgr install ${missing[*]}"
        if ! out=$(tlmgr install "${missing[@]}" 2>&1); then
            echo "$out"
            grep -q 'tlmgr itself needs to be updated' <<<"$out" || return 1
            run tlmgr update --self
            run tlmgr install "${missing[@]}"
        else
            echo "$out"
        fi
        run tex-refresh
        mapfile -t missing < <(tex_missing)
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "MISSING (tex optional): ${missing[*]}" >&2
        return 1
    fi
    echo "TeX optional set OK (${#TEX_PKGS[@]} items)"
}

if [ "$VERIFY" -eq 0 ]; then
    mounts=()
    if [ "$DO_PYTHON" -eq 1 ]; then mounts+=(/opt/venv); fi
    if [ "$DO_R" -eq 1 ]; then mounts+=("$(Rscript -e 'cat(.libPaths()[1])')"); fi
    if [ "$DO_TEX" -eq 1 ]; then mounts+=("$TEX_PREFIX"); fi
    require_install_mode "${mounts[@]}"
fi

# Run every requested stack, then report: one failure should not hide another.
status=0
if [ "$DO_PYTHON" -eq 1 ]; then optional_python || status=1; fi
if [ "$DO_R" -eq 1 ]; then optional_r || status=1; fi
if [ "$DO_TEX" -eq 1 ]; then optional_tex || status=1; fi
if [ "$status" -ne 0 ]; then
    echo "Optional set incomplete; see MISSING above." >&2
    exit 1
fi
if [ "$VERIFY" -eq 0 ]; then
    echo 'Done. Back to YOLO mode: on the host, ybcode or bbe; ybox --stop --normie.'
else
    echo "Done."
fi
