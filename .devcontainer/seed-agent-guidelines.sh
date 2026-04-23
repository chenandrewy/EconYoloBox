#!/bin/bash
# ABOUTME: Seeds persistent user-level Claude and Codex guidance from the
# ABOUTME: sandbox's canonical markdown files when the targets are missing.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SANDBOX_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

seed_if_missing() {
    local src=$1
    local dst=$2

    mkdir -p "$(dirname "$dst")"
    if [ ! -s "$dst" ]; then
        cp "$src" "$dst"
    fi
}

seed_if_missing "$SANDBOX_ROOT/SANDBOX-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
seed_if_missing "$SANDBOX_ROOT/SANDBOX-AGENTS.md" "$HOME/.codex/AGENTS.md"
