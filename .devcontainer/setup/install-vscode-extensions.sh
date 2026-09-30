#!/usr/bin/env bash
# Run:    bash .devcontainer/setup/install-vscode-extensions.sh [--verify]
# Inputs: the normie container's VS Code `code` CLI for installation, and the
#         shared /home/ubuntu/.vscode-server/extensions volume. --verify reads
#         that volume in either mode and needs no VS Code process.
# Outputs: installs the listed extensions sequentially in normie mode, then
#          verifies every registry entry and package.json. --verify only checks.
#          Exits nonzero on a missing extension or failed install.

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
extensions_dir=/home/ubuntu/.vscode-server/extensions
registry=$extensions_dir/extensions.json
extensions=(
    dbaeumer.vscode-eslint
    esbenp.prettier-vscode
    tamasfe.even-better-toml
    james-yu.latex-workshop
    donjayamanne.githistory
    mhutchie.git-graph
    ms-python.python
    ms-python.vscode-pylance
    ikuyadeu.r-pack
    reditorsupport.r
    chenandrewy.aichatrender
    Catppuccin.catppuccin-vsc
)

if [[ $# -gt 1 || ( $# -eq 1 && $1 != --verify ) ]]; then
    echo "Usage: bash .devcontainer/setup/install-vscode-extensions.sh [--verify]" >&2
    exit 2
fi

if [[ $# -eq 0 ]]; then
    posture=$(bash "$script_dir/../posture.sh")
    if [[ $posture != normie\ * ]]; then
        echo "Install extensions in normie mode, with its writable extension volume." >&2
        exit 1
    fi
    if [[ ! -w $extensions_dir ]]; then
        echo "The extension volume is not writable from this process (an agent sandbox?)." >&2
        echo "Run this from a VS Code integrated terminal in the normie container." >&2
        exit 1
    fi
    if ! command -v code >/dev/null 2>&1; then
        echo "Run this from a VS Code integrated terminal in the normie container (the code CLI is missing)." >&2
        exit 1
    fi
    for extension in "${extensions[@]}"; do
        echo "Installing $extension in normie mode..."
        code --install-extension "$extension"
    done
fi

if [[ ! -f $registry ]]; then
    echo "Missing VS Code extension registry: $registry" >&2
    exit 1
fi

failures=0
for extension in "${extensions[@]}"; do
    location=$(jq -r --arg id "$extension" \
        '[.[] | select(.identifier.id | ascii_downcase == ($id | ascii_downcase))][0].location.path // empty' \
        "$registry")
    if [[ -z $location || ! -f $location/package.json ]]; then
        echo "MISSING: $extension" >&2
        failures=$((failures + 1))
    else
        echo "OK: $extension"
    fi
done

if (( failures )); then
    echo "$failures required VS Code extension(s) missing." >&2
    exit 1
fi
echo "All ${#extensions[@]} required VS Code extensions are installed."
