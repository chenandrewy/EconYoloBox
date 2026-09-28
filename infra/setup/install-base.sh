#!/usr/bin/env bash
# Install the lean base: the Python, R and TeX stacks and the AI CLIs.
#
# Run, inside the devcontainer as ubuntu, from anywhere in this checkout:
#   In normie mode (on the host, `bbcode --normie` or `bbe --normie`):
#     bash infra/setup/install-base.sh                # python r tex cli (all)
#     bash infra/setup/install-base.sh tex            # TeX Live only
#     bash infra/setup/install-base.sh r --force      # reinstall present R packages
#   In any mode:
#     bash infra/setup/install-base.sh cli            # AI CLIs, always @latest
#     bash infra/setup/install-base.sh --verify       # check only; writes nothing
#   In the Dockerfile only (RUN as ubuntu, BuildKit bind-mounting this file):
#     bash install-base.sh --image-build         # python r tex into the image
#
# Inputs:  the package lists below; the dated P3M snapshot pinned in the image's
#          Rprofile.site (Dockerfile ARG CRAN_SNAPSHOT); PyPI; the rolling
#          TeX Live tlnet repository; npm.
# Outputs: python -> /opt/venv; r -> the R site library; tex -> TeX Live in
#          /usr/local/texlive (with install.log and the .yolobox-installed
#          marker there); cli -> NPM_CONFIG_PREFIX. Each target ends with an
#          "... OK" line or exits nonzero.
#
# Packages change only in normie mode, from inside (docs/journal/0926e). The
# devcontainer's own image is the builder, which matters: R packages link
# against its shared libraries and install from its Rprofile.site snapshot, so
# a volume must be built by the image that will consume it. The volumes are
# ubuntu-owned (the Dockerfile seeds them so), and everything here runs as ubuntu.
#
# python, r and tex refuse unless the container is in normie mode: run as
# ubuntu, their mounts writable and ubuntu-owned, and the firewall open (checked
# like install-optional.sh does, on the mounts and the firewall marker). An
# unmounted directory would install into a disposable image layer. cli needs
# only its own mount, the per-checkout npm-global volume, which is writable in
# every mode. --verify only checks (imports, library loads, the TeX marker, npm
# ls) and works in any mode. Outside a container everything refuses.
#
# --image-build is the Dockerfile's first-setup path (docs/journal/0926f). It
# installs python, r and tex into the image's own directories, and Docker seeds
# each empty volume from them the first time it is mounted, so a new checkout
# gets the base without a normie round trip. It requires the opposite of normie
# mode: the targets must NOT be mounts, which is true only during a build, so
# it refuses in any running container. Seeding happens once; a volume that
# holds anything is never touched again, and base changes still go through
# normie mode.
#
# Adding a package means editing a list here and re-running: python and r are
# idempotent (present packages are skipped unless --force), and tex adds
# whatever TEX_COLLECTIONS/TEX_PKGS name that the marked tree lacks. See
# docs/journal/0921a, 0925b, 0926d and 0926e.
#
# The lists are a lean base: what the yolobox's own tools and tests need, plus a
# small core. Everything else we use is the optional set, installed by the user
# into the same volumes with install-optional.sh, also in normie mode
# (docs/journal/0926a). Nothing here may depend on the optional set.
#
# Deliberately no user-level layering: one declared stack per language.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: install-base.sh [python] [r] [tex] [cli] [all] [--force] [--verify]

  python    install the Python stack into /opt/venv
  r         install the R stack into the site library
  tex       install minimal TeX Live, or add missing TEX_PKGS to it
  cli       install/update the Claude Code and Codex CLIs
  all       python r tex cli (the default)
  --force   reinstall present python/r packages (not accepted with tex;
            with no target, python r cli)
  --verify  check the named targets without installing anything
  --image-build
            the Dockerfile's path: python r tex into the image, whose
            directories seed fresh volumes; refuses in a running container

Several targets may be given. Runs only inside the devcontainer, as ubuntu.
python, r and tex install only in normie mode; cli and --verify work in any
mode. Re-runs skip what is installed.
USAGE
}

DO_PYTHON=0
DO_R=0
DO_TEX=0
DO_CLI=0
FORCE=0
VERIFY=0
IMAGE_BUILD=0
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
        DO_CLI=1
        ;;
    --force | -f) FORCE=1 ;;
    --verify) VERIFY=1 ;;
    --image-build) IMAGE_BUILD=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "install-base.sh: unknown argument '$arg'" >&2
        usage >&2
        exit 2
        ;;
    esac
done
if [ "$IMAGE_BUILD" -eq 1 ]; then
    # The CLIs stay out of the image (a baked @latest layer freezes; see the
    # Dockerfile), and a build has nothing to verify against.
    if [ "$DO_CLI" -eq 1 ] || [ "$VERIFY" -eq 1 ] || [ "$FORCE" -eq 1 ]; then
        echo "install-base.sh: --image-build takes only python, r and tex." >&2
        exit 2
    fi
    if [ $((DO_PYTHON + DO_R + DO_TEX)) -eq 0 ]; then
        DO_PYTHON=1
        DO_R=1
        DO_TEX=1
    fi
fi
# --force does not apply to TeX, so a bare --force leaves it out.
if [ $((DO_PYTHON + DO_R + DO_TEX + DO_CLI)) -eq 0 ]; then
    DO_PYTHON=1
    DO_R=1
    DO_CLI=1
    if [ "$FORCE" -eq 0 ]; then DO_TEX=1; fi
fi
if [ "$FORCE" -eq 1 ] && [ "$VERIFY" -eq 1 ]; then
    echo "install-base.sh: --force and --verify are mutually exclusive." >&2
    exit 2
fi
if [ "$FORCE" -eq 1 ] && [ "$DO_TEX" -eq 1 ]; then
    echo "install-base.sh: --force does not apply to tex; rebuilding TeX means a new volume." >&2
    echo "Run tex without --force, and python/r --force separately." >&2
    exit 2
fi

# Everything above is plain enough for macOS bash 3.2, so that on the host this
# refusal is what runs. A BuildKit RUN has neither marker; --image-build makes
# its own check below.
if [ "$IMAGE_BUILD" -eq 0 ] && [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ]; then
    echo "install-base.sh: runs only inside the devcontainer; nothing was installed." >&2
    echo "Switch to normie mode (see infra/setup/README.md), then in the container run:" >&2
    echo "  bash infra/setup/install-base.sh $*" >&2
    exit 1
fi

CLI_TARGET=/usr/local/share/npm-global
TEX_PREFIX=/usr/local/texlive

WORK_DIR=""
cleanup() {
    if [ -n "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT
WORK_DIR=$(mktemp -d)

# The same check as install-optional.sh: normie mode is the user's switch, the
# mounts writable, which only bbox --normie can arrange, at creation. Checked
# on the container itself. All of it before anything installs, so a refusal
# writes nothing.
require_install_mode() {
    local mount owner problems=()
    [ "$(id -un)" = ubuntu ] || problems+=("run as ubuntu, not $(id -un)")
    for mount in "$@"; do
        if ! mountpoint -q "$mount"; then
            problems+=("$mount is not a mounted volume; refusing to install into the image layer")
        elif findmnt -n -o OPTIONS -T "$mount" | tr ',' '\n' | grep -qx ro; then
            problems+=("$mount is mounted read-only")
        else
            owner=$(stat -c %U "$mount")
            if [ "$owner" != ubuntu ]; then
                problems+=("$mount is owned by $owner, not ubuntu (see infra/setup/README.md, \"Volume ownership\")")
            elif [ ! -w "$mount" ]; then
                problems+=("$mount is not writable by $(id -un)")
            fi
        fi
    done
    # post-start.sh leaves this marker when it skips the firewall. Armed, the
    # firewall blocks PyPI, P3M and CTAN, so every install fails.
    [ -f /tmp/FIREWALL-WINDOW-OPEN ] || problems+=("the firewall is armed; PyPI, P3M and CTAN are blocked")
    if [ ${#problems[@]} -gt 0 ]; then
        echo "install-base.sh: not in normie mode:" >&2
        printf '  - %s\n' "${problems[@]}" >&2
        echo 'Switch to normie mode: on the host, bbcode --normie (or bbe --normie),' >&2
        echo "then in the container: bash infra/setup/install-base.sh $STACK_TARGETS" >&2
        echo 'Back to YOLO mode afterwards: bbcode or bbe; bbox --stop --normie.' >&2
        echo 'The AI CLIs update in any mode: bash infra/setup/install-base.sh cli' >&2
        exit 1
    fi
}

# The CLI volume is writable in every mode; it only has to be mounted, or npm
# would install into a disposable image layer.
require_cli_mount() {
    if ! mountpoint -q "$CLI_TARGET"; then
        echo "install-base.sh: $CLI_TARGET is not a mounted volume; refusing to install into the image layer." >&2
        echo "Run bbox --rebuild on the host, then bash infra/setup/install-base.sh cli" >&2
        exit 1
    fi
}

# The inverse of require_install_mode: during an image build nothing is
# mounted, and in a running container every target is, so "no target is a
# mount" is what tells the two apart. The image's directories are ubuntu-owned
# (the Dockerfile makes them so), which is how the seeded volumes end up
# ubuntu-owned too.
require_image_build() {
    local dir problems=()
    for dir in "$@"; do
        if [ ! -d "$dir" ]; then
            problems+=("$dir does not exist; the Dockerfile creates it")
        elif mountpoint -q "$dir"; then
            problems+=("$dir is a mounted volume, so this is a running container, not an image build")
        elif [ ! -w "$dir" ]; then
            problems+=("$dir is not writable by ubuntu")
        fi
    done
    if [ ${#problems[@]} -gt 0 ]; then
        echo "install-base.sh: --image-build is for the Dockerfile only:" >&2
        printf '  - %s\n' "${problems[@]}" >&2
        echo "In a container, install in normie mode: bash infra/setup/install-base.sh" >&2
        exit 1
    fi
}

# Before anything else runs, so a host or a root build step gets a plain
# refusal rather than a missing-command error.
if [ "$IMAGE_BUILD" -eq 1 ] && [ "$(id -un)" != ubuntu ]; then
    echo "install-base.sh: --image-build runs as ubuntu in the Dockerfile only; nothing was installed." >&2
    exit 1
fi

R_LIB=""
if [ "$DO_R" -eq 1 ]; then R_LIB=$(Rscript -e 'cat(.libPaths()[1])'); fi

STACK_TARGETS=""
if [ "$IMAGE_BUILD" -eq 1 ]; then
    build_dirs=()
    if [ "$DO_PYTHON" -eq 1 ]; then build_dirs+=(/opt/venv); fi
    if [ "$DO_R" -eq 1 ]; then build_dirs+=("$R_LIB"); fi
    if [ "$DO_TEX" -eq 1 ]; then build_dirs+=("$TEX_PREFIX"); fi
    require_image_build "${build_dirs[@]}"
elif [ "$VERIFY" -eq 0 ]; then
    stack_mounts=()
    if [ "$DO_PYTHON" -eq 1 ]; then stack_mounts+=(/opt/venv) && STACK_TARGETS+=" python"; fi
    if [ "$DO_R" -eq 1 ]; then stack_mounts+=("$R_LIB") && STACK_TARGETS+=" r"; fi
    if [ "$DO_TEX" -eq 1 ]; then stack_mounts+=("$TEX_PREFIX") && STACK_TARGETS+=" tex"; fi
    STACK_TARGETS=${STACK_TARGETS# }
    if [ ${#stack_mounts[@]} -gt 0 ]; then require_install_mode "${stack_mounts[@]}"; fi
    if [ "$DO_CLI" -eq 1 ]; then require_cli_mount; fi
fi

PY_PKGS=(
    # yolobox tools (tools/pdf, tools/lit)
    requests
    PyMuPDF
    pikepdf
    openai
    mistralai
    # core; pyfixest is also the startup sentinel
    numpy
    pandas
    matplotlib
    statsmodels
    pyfixest
)

install_python() {
    echo "==> Python stack (/opt/venv), ${#PY_PKGS[@]} packages"
    if [ "$VERIFY" -eq 0 ]; then
        local args=(--no-cache-dir)
        if [ "$FORCE" -eq 1 ]; then
            args+=(--force-reinstall)
        fi
        # pip is already idempotent: satisfied requirements are skipped.
        pip install "${args[@]}" "${PY_PKGS[@]}"
    fi

    # A fresh interpreter, so a --force reinstall cannot pass from memory.
    python3 - "${PY_PKGS[@]}" <<'PYEOF'
import contextlib
import importlib
import io
import sys
import warnings
from importlib.metadata import PackageNotFoundError, distribution, packages_distributions

warnings.simplefilter("ignore")


def norm(name):
    return name.lower().replace("_", "-").replace(".", "-")


# Import every public top-level module each distribution provides, so the
# check needs no hand-kept dist->module map (scikit-learn/sklearn, PyMuPDF/fitz).
modules = {}
for module, dists in packages_distributions().items():
    if not module.startswith("_"):
        for dist in dists:
            modules.setdefault(norm(dist), set()).add(module)

missing, broken, imported = [], [], 0
for name in sys.argv[1:]:
    try:
        distribution(name)
    except PackageNotFoundError:
        missing.append(name)
        continue
    for module in sorted(modules.get(norm(name), ())):
        try:
            # Some packages print notices on import (PyMuPDF's fitz).
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                importlib.import_module(module)
            imported += 1
        except Exception as exc:
            broken.append("%s (%s): %s" % (module, name, exc))

if missing:
    print("MISSING (python): " + ", ".join(missing))
if broken:
    print("BROKEN (python):\n  " + "\n  ".join(broken))
if missing or broken:
    sys.exit(1)
print("Python stack OK (%d packages, %d modules import)" % (len(sys.argv) - 1, imported))
PYEOF
}

install_r() {
    echo "==> R stack ($R_LIB)"
    local r_script="$WORK_DIR/install-r.R"

    # Plain Rscript, not --vanilla: the site Rprofile is what pins the repo to
    # the dated P3M snapshot and sets the R-version user agent that makes P3M
    # serve prebuilt noble binaries instead of silently falling back to source.
    cat >"$r_script" <<'REOF'
mode <- commandArgs(trailingOnly = TRUE)[1]
reinstall <- identical(Sys.getenv("STACK_FORCE"), "1")

# Lean base. Everything else, including pryr (CRAN archive) and pcaMethods
# (Bioconductor), is in install-optional.sh.
#   languageserver  - the VS Code R extension
#   fixest          - the regressions; also the test and startup sentinel
#   modelsummary    - fixest models -> LaTeX/markdown/Word tables
#   sandwich+lmtest - robust/clustered SEs for base lm/glm
cran_pkgs <- c(
  "languageserver",
  "fixest",
  "data.table", "tidyverse",
  "modelsummary", "sandwich", "lmtest"
)

all_pkgs <- cran_pkgs

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

todo <- cran_pkgs[vapply(cran_pkgs, wanted, logical(1))]
if (length(todo)) {
  cat("Installing from P3M snapshot:", paste(todo, collapse = ", "), "\n")
  install.packages(todo)
} else {
  cat("CRAN packages already present\n")
}

# Fail loudly on a partial install rather than leaving a half-built stack.
missing <- all_pkgs[!vapply(all_pkgs, have, logical(1))]
if (length(missing)) {
  report_failure(missing, "R stack incomplete")
  quit(status = 1)
}
REOF

    if [ "$VERIFY" -eq 0 ]; then
        STACK_FORCE="$FORCE" Rscript "$r_script" install
    fi
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
TEX_MARKER="$TEX_PREFIX/.yolobox-installed"
# The marker's pre-rename name, still in volumes built before it.
TEX_OLD_MARKER="$TEX_PREFIX/.sandbox-installed"
TEX_LOG="$TEX_PREFIX/install.log"
TEX_REPOSITORY=https://mirror.ctan.org/systems/texlive/tlnet
TEX_COLLECTIONS=(
    # scheme-small's collections, minus collection-xetex
    collection-basic
    collection-latex
    collection-latexrecommended
    collection-metapost
    # additions
    collection-bibtexextra # biblatex, biber
)
TEX_EXCLUDED=(collection-xetex)
# Single packages on top of the collections. Adding a name here and re-running
# `install-base.sh tex` installs it with tlmgr. latexindent's Perl dependencies are
# in the Dockerfile; latexmk is LaTeX Workshop's default recipe. cm-super is
# the one package a default LyX export needs beyond the collections: LyX writes
# \usepackage[T1]{fontenc}, and without cm-super pdflatex falls back to
# bitmap EC fonts (found by mapping a default export's -recorder inputs to
# texlive.tlpdb; docs/journal/0926b). The rest of the old TeX stack
# (latexextra, pictures/TikZ, mathscience, fonts) is in install-optional.sh.
TEX_PKGS=(
    latexindent
    latexmk
    cm-super
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
\usepackage[T1]{fontenc}
\usepackage{amsmath}
\usepackage[backend=biber,style=authoryear]{biblatex}
\addbibresource{references.bib}
\begin{document}
TeX Live smoke test: $x^2$, see \autocite{knuth1984}.
\printbibliography
\end{document}
TEX
    pdflatex -interaction=nonstopmode -halt-on-error smoke.tex >/dev/null
    biber smoke >/dev/null
    pdflatex -interaction=nonstopmode -halt-on-error smoke.tex >/dev/null
    pdftotext smoke.pdf smoke.txt
    grep -q Knuth smoke.txt
    # T1 text in bitmap (Type 3) fonts means cm-super is missing.
    if pdffonts smoke.pdf | grep -q 'Type 3'; then
        echo "smoke.pdf uses bitmap fonts; is cm-super installed?" >&2
        return 1
    fi
    latexindent smoke.tex >/dev/null
    latexmk -v >/dev/null
    echo "pdflatex, biber, latexindent, latexmk OK"

    # LyX gets a private userdir, so the smoke test leaves ubuntu's ~/.lyx
    # alone; configure.py there is what tex-refresh runs afterwards.
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

# mirror.ctan.org redirects each request to a random mirror, and a few serve a
# certificate wget cannot verify (ctan.math.utah.edu, 2026-09-26). Pick
# one concrete mirror whose tlpdb downloads, retrying through the redirector,
# and use it for the whole fresh install; install-tl records it as tlmgr's
# repository, as it would a mirror it resolved itself. Prints the mirror.
tex_pick_mirror() {
    local attempt mirror
    for attempt in 1 2 3 4 5; do
        mirror=$(curl -s -o /dev/null -w '%{redirect_url}' "$TEX_REPOSITORY/tlpkg/texlive.tlpdb.xz") || mirror=""
        mirror=${mirror%/tlpkg/texlive.tlpdb.xz}
        [ -n "$mirror" ] || mirror=$TEX_REPOSITORY
        if wget --no-verbose -O texlive.tlpdb.xz "$mirror/tlpkg/texlive.tlpdb.xz" >&2; then
            echo "$mirror"
            return 0
        fi
        echo "TeX mirror $mirror failed (attempt $attempt of 5)" >&2
    done
    echo "No TeX mirror reachable through $TEX_REPOSITORY; nothing was written to the volume." >&2
    return 1
}

tex_fresh_install() {
    local year=$1 platform=$2 repository_year coll mirror
    cd "$WORK_DIR"
    mirror=$(tex_pick_mirror) || exit 1
    echo "TeX mirror: $mirror"
    xz -d texlive.tlpdb.xz
    repository_year=$(awk '$1 == "depend" && $2 ~ /^release\/[0-9]+$/ {sub(/^release\//, "", $2); print $2; exit}' texlive.tlpdb)
    if [ "$repository_year" != "$year" ]; then
        echo "Repository release '$repository_year' does not match the image's TeX Live $year." >&2
        echo "Bump TEXLIVE_YEAR in the Dockerfile and the volume name together." >&2
        exit 1
    fi
    wget --no-verbose -O install-tl.tar.gz "$mirror/install-tl-unx.tar.gz"
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
    # after this run. The preflight above writes nothing
    # there, so a failed download never makes the volume look installed.
    (
        set -o errtrace
        trap 'echo "Installation/check failed. Inspect $TEX_LOG; the tree has been preserved." >&2' ERR
        perl ./install-tl-*/install-tl -profile "$WORK_DIR/texlive.profile" -repository "$mirror"
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
    local bindir year platform installed
    bindir=$(readlink /usr/local/texlive-bin) # $TEX_PREFIX/<year>/bin/<platform>
    platform=${bindir##*/}
    year=${bindir#"$TEX_PREFIX"/}
    year=${year%%/*}
    echo "==> TeX Live $year ($TEX_PREFIX, $platform)"

    # A volume marked under the old name: verify reads it where it is (the
    # volume may be read-only); an install renames it.
    if [ ! -f "$TEX_MARKER" ] && [ -f "$TEX_OLD_MARKER" ]; then
        if [ "$VERIFY" -eq 1 ]; then
            TEX_MARKER=$TEX_OLD_MARKER
        else
            mv "$TEX_OLD_MARKER" "$TEX_MARKER"
        fi
    fi

    if [ "$VERIFY" -eq 1 ]; then
        if [ ! -f "$TEX_MARKER" ]; then
            echo "MISSING (tex): no $TEX_MARKER; in normie mode, in the container: bash infra/setup/install-base.sh tex" >&2
            return 1
        fi
        local absent=()
        mapfile -t absent < <(tex_missing "$year")
        if [ ${#absent[@]} -gt 0 ]; then
            echo "MISSING (tex): ${absent[*]}; in normie mode, in the container: bash infra/setup/install-base.sh tex" >&2
            return 1
        fi
        echo "TeX stack OK (marked; ${#TEX_COLLECTIONS[@]} collections, ${#TEX_PKGS[@]} extra packages present)"
        return 0
    fi

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
    local pkg
    if [ "$VERIFY" -eq 0 ]; then
        local pinned=()
        for pkg in "${CLI_PKGS[@]}"; do
            pinned+=("${pkg}@latest")
        done
        npm install -g "${pinned[@]}"
    fi

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

if [ "$IMAGE_BUILD" -eq 1 ]; then
    # No tex-refresh: it configures ubuntu's LyX userdir, which is a runtime
    # concern; post-start.sh runs it at every start.
    echo "Done. The image now carries the base; Docker seeds each empty volume from it."
elif [ "$VERIFY" -eq 0 ] && [ -n "$STACK_TARGETS" ]; then
    if [ "$DO_TEX" -eq 1 ]; then
        echo "+ tex-refresh"
        tex-refresh
    fi
    echo "Restart R/Python sessions in every container that mounts these volumes;"
    echo "after a TeX change run tex-refresh there too and reopen LyX."
    echo 'Done. Back to YOLO mode: on the host, bbcode or bbe; bbox --stop --normie.'
else
    echo "Done."
fi
