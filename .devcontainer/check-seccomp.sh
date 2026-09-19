#!/bin/bash
# ABOUTME: Compares SANDBOX.toml's requested seccomp policy with PID 1's mode.
# ABOUTME: Warns about disabled filtering and stale container settings.
#
# Run:     bash .devcontainer/check-seccomp.sh [TOML_FILE] [PROC_STATUS]
# Inputs:  SANDBOX.toml and /proc/1/status by default; optional paths aid tests.
# Outputs: diagnostics on stderr only; always exits zero so shell startup proceeds.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
toml=${1:-"$root/SANDBOX.toml"}
proc_status=${2:-/proc/1/status}
reader="$root/.devcontainer/seccomp-setting.sh"
host_root=${LOCAL_CONTAINER_FOLDER:-$root}

requested=$(bash "$reader" "$toml")
reader_status=$?
if [ "$reader_status" -ne 0 ]; then
    requested=builtin
    printf 'SANDBOX.toml: seccomp setting could not be checked; using seccomp = "builtin"\n' >&2
fi

mode=$(sed -n -E 's/^Seccomp:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$proc_status" 2>/dev/null | head -n 1)
case "$mode" in
    0) observed=unconfined ;;
    2) observed=filtered ;;
    *) observed=unverified ;;
esac

if [ "$observed" = unconfined ]; then
    highlight='' reset=''
    if [ -t 2 ]; then
        highlight=$'\033[1;3;38;5;214m'
        reset=$'\033[0m'
    fi
    printf '%s\n' \
        "${highlight}Warning: Seccomp Unconfined${reset}" \
        'To close: set seccomp = "builtin" in /workspace/SANDBOX.toml, then run bbox --rebuild on the host' >&2
fi

if { [ "$requested" = builtin ] && [ "$observed" = filtered ]; } ||
   { [ "$requested" = unconfined ] && [ "$observed" = unconfined ]; }; then
    exit 0
fi

if [ "$observed" = unverified ]; then
    detail="PID 1 seccomp mode could not be verified"
else
    detail="PID 1 is $observed"
fi
printf '%s\n' \
    "Warning: requested seccomp=$requested, but $detail." \
    'Seccomp is fixed when the container is created.' \
    "On the host, run: bbox --rebuild \"$host_root\"" >&2
exit 0
