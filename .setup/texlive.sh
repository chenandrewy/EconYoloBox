#!/usr/bin/env bash
# Run on the host: bash .setup/texlive.sh
# Inputs: Docker's selected daemon/platform; internet access; an empty
# texlive-2026-noble volume (created by Docker if absent). No arguments.
# Outputs: full TeX Live 2026 in that volume; installation log in its root.
# This installs once. It refuses nonempty volumes and never updates or deletes.
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo 'Usage: bash .setup/texlive.sh' >&2
  exit 2
fi

# Keep these in step with the literal mount and Dockerfile TEXLIVE_YEAR.
year=2026
volume=texlive-2026-noble
docker run --rm -i --mount "type=volume,source=$volume,target=/usr/local/texlive" \
  ubuntu:24.04 bash -s -- "$year" <<'BUILDER'
set -euo pipefail
year=$1
prefix=/usr/local/texlive
repository=https://mirror.ctan.org/systems/texlive/tlnet

if [ -n "$(find "$prefix" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo 'TeX volume is nonempty; refusing to overwrite or update it.' >&2
  echo 'If an earlier install failed, inspect install.log in the volume first.' >&2
  echo 'Retry/repair or volume recreation requires an explicit manual decision.' >&2
  exit 1
fi
case "$(dpkg --print-architecture)" in
  amd64) platform=x86_64-linux ;;
  arm64) platform=aarch64-linux ;;
  *) echo 'Unsupported Docker architecture' >&2; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
# XeTeX links to libfontconfig.so.1 even when only generating formats.
# Bare Ubuntu lacks it; keep this explicit so all full-scheme formats build.
apt-get install -y --no-install-recommends perl wget ca-certificates xz-utils libfontconfig1
work=$(mktemp -d)
cd "$work"
wget -q -O texlive.tlpdb.xz "$repository/tlpkg/texlive.tlpdb.xz"
xz -d texlive.tlpdb.xz
repository_year=$(awk '$1 == "depend" && $2 ~ /^release\/[0-9]+$/ {sub(/^release\//, "", $2); print $2; exit}' texlive.tlpdb)
if [ "$repository_year" != "$year" ]; then
  echo "Repository release '$repository_year' does not match requested $year." >&2
  exit 1
fi
wget -q -O install-tl.tar.gz "$repository/install-tl-unx.tar.gz"
tar -xzf install-tl.tar.gz
cat > texlive.profile <<PROFILE
selected_scheme scheme-full
binary_$platform 1
TEXDIR $prefix/$year
TEXMFLOCAL $prefix/texmf-local
TEXMFSYSCONFIG $prefix/$year/texmf-config
TEXMFSYSVAR $prefix/$year/texmf-var
TEXMFHOME ~/texmf
TEXMFCONFIG ~/.texlive$year/texmf-config
TEXMFVAR ~/.texlive$year/texmf-var
instopt_adjustpath 0
instopt_portable 0
PROFILE

# Preserve output even though the temporary builder container is removed.
# Preflight downloads above do not make an empty volume look installed.
(
  trap 'echo "Installation/check failed. Inspect /usr/local/texlive/install.log; the tree has been preserved." >&2' ERR
  perl ./install-tl-*/install-tl -profile "$work/texlive.profile" -repository "$repository"
  export PATH="$prefix/$year/bin/$platform:$PATH"
  fmtutil-sys --all
  updmap-sys
  printf '%s\n' '\documentclass{article}\begin{document}TeX Live smoke test: $x^2$.\end{document}' > smoke.tex
  for engine in pdflatex xelatex; do
    "$engine" -interaction=nonstopmode -halt-on-error -jobname="smoke-$engine" smoke.tex
    test -s "smoke-$engine.pdf"
  done
) 2>&1 | tee "$prefix/install.log"
BUILDER

echo 'TeX Live installed. In each consuming container, run: tex-refresh'
echo 'Reopen any already-running LyX before exporting. Do not update this volume while it is in use.'
