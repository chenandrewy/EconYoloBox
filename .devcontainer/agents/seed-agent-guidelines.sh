#!/bin/bash
# ABOUTME: Applies the canonical agent config in .devcontainer/agents/ to the
# ABOUTME: container's user-level Claude and Codex config on every start.
set -euo pipefail

AGENTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$HOME/.claude/skills" "$HOME/.codex" "$HOME/.agents/skills"

# Guidance: symlinked, so edits apply live without a container restart.
ln -sfn "$AGENTS_DIR/SANDBOX-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
ln -sfn "$AGENTS_DIR/SANDBOX-AGENTS.md" "$HOME/.codex/AGENTS.md"

# Shared skills: each canonical skill is linked into both agents' user-level
# discovery directory. Refuse to replace a same-named real directory.
for skill_dir in "$AGENTS_DIR"/skills/*; do
    [[ -d $skill_dir && -f $skill_dir/SKILL.md ]] || continue
    skill_name=${skill_dir##*/}

    for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
        skill_link="$skill_root/$skill_name"
        if [[ -e $skill_link && ! -L $skill_link ]]; then
            echo "Cannot seed shared skill '$skill_name': $skill_link already exists" >&2
            exit 1
        fi
        ln -sfn "$skill_dir" "$skill_link"
    done
done

# Keep Codex's @ autocomplete dedicated to files; Skills remain available via $.
codex features disable mentions_v2

# Settings: copied, not symlinked. Claude Code writes to its settings file
# (/config, /model, permission grants), and those writes belong in the volume,
# not the repo. Each container start re-applies the canonical settings.
cp "$AGENTS_DIR/SANDBOX-claude-settings.json" "$HOME/.claude/settings.json"
