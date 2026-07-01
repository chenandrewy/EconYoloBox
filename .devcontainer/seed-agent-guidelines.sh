#!/bin/bash
# ABOUTME: Links persistent user-level Claude and Codex guidance to the
# ABOUTME: sandbox's canonical markdown files so edits apply without a rebuild.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SANDBOX_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

link_guidelines() {
    local src=$1
    local dst=$2

    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
}

link_guidelines "$SANDBOX_ROOT/SANDBOX-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_guidelines "$SANDBOX_ROOT/SANDBOX-AGENTS.md" "$HOME/.codex/AGENTS.md"
