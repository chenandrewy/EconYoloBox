#!/bin/bash
# ABOUTME: Writes stable host-local info to an env file consumed by the Dev
# ABOUTME: Container via runArgs --env-file.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCAL_CONTAINER_FOLDER=$(cd "$SCRIPT_DIR/.." && pwd)

ENV_FILE=/tmp/devcontainer-local.env
umask 077
{
    printf 'LOCAL_HOSTNAME=%s\n' "$(hostname)"
    printf 'LOCAL_CONTAINER_FOLDER=%s\n' "$LOCAL_CONTAINER_FOLDER"
} > "$ENV_FILE"
