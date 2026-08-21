#!/bin/bash
# ABOUTME: Writes stable host-local info to an env file consumed by the Dev
# ABOUTME: Container via runArgs --env-file.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOCAL_CONTAINER_FOLDER=$(cd "$SCRIPT_DIR/.." && pwd)

# Host IANA zone. $TZ is rarely set on macOS/desktop Linux (and VS Code launched
# from the Dock inherits no shell profile), so read the system setting directly.
# Falls back to the image's baked-in default by emitting nothing.
detect_tz() {
    if [ -n "${TZ:-}" ]; then
        printf '%s' "$TZ"
        return
    fi
    if command -v timedatectl >/dev/null 2>&1; then
        local tz
        tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
        if [ -n "$tz" ]; then
            printf '%s' "$tz"
            return
        fi
    fi
    # macOS: /var/db/timezone/zoneinfo/America/New_York; Linux: /usr/share/...
    if [ -L /etc/localtime ]; then
        local target
        target=$(readlink /etc/localtime)
        case "$target" in
            */zoneinfo/*) printf '%s' "${target##*/zoneinfo/}" ;;
        esac
    fi
}

# Stable host name. Plain `hostname` is the *transient* name on macOS: it is
# network-derived, so DHCP can hand back a truncated or generic value ("Mac")
# that then freezes into the container's env at create time. LocalHostName is
# the stable identity and carries no .local suffix.
detect_hostname() {
    local name
    if command -v scutil >/dev/null 2>&1; then
        name=$(scutil --get LocalHostName 2>/dev/null || true)
        if [ -n "$name" ]; then
            printf '%s' "$name"
            return
        fi
    fi
    hostname -s 2>/dev/null || hostname
}

ENV_FILE=/tmp/devcontainer-local.env
umask 077
{
    printf 'LOCAL_HOSTNAME=%s\n' "$(detect_hostname)"
    printf 'LOCAL_CONTAINER_FOLDER=%s\n' "$LOCAL_CONTAINER_FOLDER"
    HOST_TZ=$(detect_tz)
    [ -n "$HOST_TZ" ] && printf 'TZ=%s\n' "$HOST_TZ"
} > "$ENV_FILE"
