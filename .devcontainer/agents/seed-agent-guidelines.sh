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
# discovery directory. Only links this seeder owns — those already pointing into
# the canonical skill tree — are refreshed. A same-named real directory, or a
# symlink pointing somewhere else, is the user's and is treated as a conflict.
#
# Conflicts are collected here rather than exiting on the spot, so that one bad
# name does not cost us the rest of the seed (the settings copy below, in
# particular). Reported together at the end of the script; the exit is still
# non-zero.
conflicts=()

for skill_dir in "$AGENTS_DIR"/skills/*; do
    [[ -d $skill_dir && -f $skill_dir/SKILL.md ]] || continue
    skill_name=${skill_dir##*/}

    for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
        skill_link="$skill_root/$skill_name"
        if [[ -L $skill_link ]]; then
            # A symlink: ours to refresh only if it points into the canonical
            # tree. Anything else is the user's own link -- record it and leave
            # it alone. 'continue' skips just this root, so the same skill can
            # still be seeded into the other agent's directory.
            case "$(readlink "$skill_link")" in
                "$AGENTS_DIR"/skills/*) ;;
                *)
                    conflicts+=("$skill_link (symlink outside $AGENTS_DIR/skills)")
                    continue
                    ;;
            esac
        elif [[ -e $skill_link ]]; then
            # Exists but is not a symlink: a real file or directory. Never ours.
            conflicts+=("$skill_link (already exists, not a symlink)")
            continue
        fi
        ln -sfn "$skill_dir" "$skill_link"
    done
done

# Remove stale links previously managed by this seeder. Preserve real
# directories and symlinks whose targets are outside the canonical skill tree.
for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    for skill_link in "$skill_root"/*; do
        [[ -L $skill_link ]] || continue
        skill_target=$(readlink "$skill_link")

        case "$skill_target" in
            "$AGENTS_DIR"/skills/*)
                if [[ ! -f $skill_target/SKILL.md ]]; then
                    unlink "$skill_link"
                fi
                ;;
        esac
    done
done

# NOTE: `codex features disable mentions_v2` used to run here. It was the only
# step that shelled out to an agent binary, and once the CLIs moved out of the
# image into a volume that starts empty, a fresh container had no `codex` - so
# `set -e` killed the seed at 127, before the settings copy below. It is now
# baked into /etc/codex/requirements.toml instead. Keep this script declarative:
# every step should be repo-to-$HOME file plumbing that works on a bare
# container, with no dependency on anything installed at runtime.

# Settings: copied, not symlinked. Claude Code writes to its settings file
# (/config, /model, permission grants), and those writes belong in the volume,
# not the repo. Each container start re-applies the canonical settings.
cp "$AGENTS_DIR/SANDBOX-claude-settings.json" "$HOME/.claude/settings.json"

# Everything above has now run. Report any skill names we refused to touch, all
# of them at once, and fail the start so the message is not missed. Each listed
# path is a file the user must move or rename by hand.
if ((${#conflicts[@]})); then
    printf 'Cannot seed shared skill: %s\n' "${conflicts[@]}" >&2
    exit 1
fi
