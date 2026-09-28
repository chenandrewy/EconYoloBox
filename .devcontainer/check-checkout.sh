#!/bin/bash
# ABOUTME: Enforces one checkout per basename per Docker daemon, for the
# ABOUTME: per-checkout volumes both modes share. Called by post-start.sh.
#
# Run:     bash .devcontainer/check-checkout.sh [MARKER] [FOLDER]
# Inputs:  MARKER, default /home/node/.claude/.yolobox-checkout (in the shared
#          ~/.claude volume); FOLDER, default $LOCAL_CONTAINER_FOLDER (the host
#          folder, from write-local-env.sh).
# Outputs: on first use, MARKER holding FOLDER. Exit 0 when MARKER matches or
#          was just written (or FOLDER is unknown, with a warning); exit 1 with
#          a refusal on stderr when MARKER names another folder.
#
# The per-checkout volumes (~/.claude, ~/.codex, npm-global, shell history) are
# named for the folder's basename alone, so the YOLO and normie containers
# share them (docs/journal/0927a). A second checkout with the same basename
# elsewhere would silently share the Claude and Codex tokens and the CLIs
# themselves; this makes it announce itself instead.

marker=${1:-/home/node/.claude/.yolobox-checkout}
# The default marker's pre-rename name, still in volumes from before it.
old_marker=/home/node/.claude/.sandbox-checkout
if [ -z "${1:-}" ] && [ ! -e "$marker" ] && [ -f "$old_marker" ]; then
    mv "$old_marker" "$marker"
fi
folder=${2:-${LOCAL_CONTAINER_FOLDER:-}}

if [ -z "$folder" ]; then
    echo "check-checkout.sh: the host folder is unknown (LOCAL_CONTAINER_FOLDER unset); not checked" >&2
    exit 0
fi
if [ ! -s "$marker" ]; then
    printf '%s\n' "$folder" >"$marker"
    exit 0
fi
recorded=$(cat "$marker")
[ "$recorded" = "$folder" ] && exit 0
{
    echo "check-checkout.sh: REFUSING: these volumes belong to the checkout at"
    echo "  $recorded"
    echo "but this container is for $folder. Two checkouts with the"
    echo "same folder name would share Claude/Codex logins and the AI CLIs."
    echo "Rename one checkout's folder. If this checkout was moved on purpose, accept"
    echo "the move in this container: rm $marker, then restart it."
} >&2
exit 1
