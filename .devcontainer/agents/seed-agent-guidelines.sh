#!/bin/bash
# ABOUTME: Applies the canonical agent config in .devcontainer/agents/ to the
# ABOUTME: container's user-level Claude and Codex config on every start.
set -euo pipefail

AGENTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$HOME/.claude" "$HOME/.codex"

# Guidance: symlinked, so edits apply live without a container restart.
ln -sfn "$AGENTS_DIR/SANDBOX-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
ln -sfn "$AGENTS_DIR/SANDBOX-AGENTS.md" "$HOME/.codex/AGENTS.md"

# Keep Codex's @ autocomplete dedicated to files; Skills remain available via $.
codex features disable mentions_v2

# Settings: copied, not symlinked. Claude Code writes to its settings file
# (/config, /model, permission grants), and those writes belong in the volume,
# not the repo. Each container start re-applies the canonical settings.
cp "$AGENTS_DIR/SANDBOX-claude-settings.json" "$HOME/.claude/settings.json"
