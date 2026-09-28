#!/usr/bin/env bash
# Run inside the container as node: tex-refresh
# Inputs: read-only TeX volume via /usr/local/texlive-bin; installed LyX.
# Outputs: regenerated converter/layout detection and logs in ~/.lyx.
set -euo pipefail

if [ "$(id -un)" != node ]; then
  echo 'Run tex-refresh as node inside the devcontainer.' >&2
  exit 1
fi
if [ ! -x /usr/local/texlive-bin/pdflatex ] || ! /usr/local/texlive-bin/pdflatex --version >/dev/null 2>&1; then
  echo 'TeX unavailable or incompatible. In normie mode, in the container: bash .setup/install-base.sh tex' >&2
  echo 'For a nonempty failed installation, inspect the volume install.log first.' >&2
  exit 1
fi

# This image uses LyX's default Unix user directory (no -userdir override).
mkdir -p "$HOME/.lyx"
cd "$HOME/.lyx"
python3 /usr/local/share/lyx/configure.py
echo 'LyX configuration refreshed. Reopen any already-running LyX before exporting.'
