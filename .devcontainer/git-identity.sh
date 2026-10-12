#!/bin/bash
# ABOUTME: Sets the container user's global Git identity (user.name and
# ABOUTME: user.email) from the host's, without touching anything else.
#
# Run:     bash .devcontainer/git-identity.sh   (post-start.sh, every start)
# Inputs:  HOST_GIT_USER_NAME and HOST_GIT_USER_EMAIL, written on the host by
#          host/write-local-env.sh and fixed at container creation; the
#          current global Git config.
# Outputs: user.name and user.email in ~/.gitconfig when each is unset there
#          and the host supplied it; a note on stderr when neither is set.
#
# VS Code used to copy the host's whole ~/.gitconfig on attach, credential
# helper included. Agents now run through `devcontainer exec`, which copies
# nothing (docs/journal/1002a). This restores the identity alone: single keys
# are set, so normie's `gh auth setup-git` helper line survives, and a value
# set in the container wins over the host's.
set -euo pipefail

for key in name email; do
    var="HOST_GIT_USER_${key^^}"
    value=${!var:-}
    if [ -z "$(git config --global "user.$key" || true)" ] && [ -n "$value" ]; then
        git config --global "user.$key" "$value"
    fi
done

if [ -z "$(git config --global user.name || true)" ] || [ -z "$(git config --global user.email || true)" ]; then
    echo "git-identity.sh: no global Git user.name/user.email; set them on the host" >&2
    echo "  (git config --global ...) and yolobox --rebuild, or set them here" >&2
fi
