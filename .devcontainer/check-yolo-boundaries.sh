#!/bin/bash
# Run:     bash .devcontainer/check-yolo-boundaries.sh [LAUNCHER] [OPEN_MARKER] [PROC_STATUS]
# Inputs:  launcher name for diagnostics; the firewall-open marker and PID 1
#          status file, defaulting to the live container paths.
# Outputs: nothing on success; a refusal reason and recovery command on stderr
#          when the firewall is open or PID 1 seccomp is not filtered.

set -u

launcher=${1:-yolo}
open_marker=${2:-/tmp/FIREWALL-WINDOW-OPEN}
proc_status=${3:-/proc/1/status}

if [ -e "$open_marker" ]; then
    printf '%s: firewall is open; refusing. This is not the YOLO container; on the host: bbcode or bbe\n' "$launcher" >&2
    exit 1
fi

mode=$(sed -n -E 's/^Seccomp:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$proc_status" 2>/dev/null | head -n 1)
if [ "$mode" = 2 ]; then
    exit 0
fi

if [ "$mode" = 0 ]; then
    detail='Docker seccomp is unconfined'
else
    detail='PID 1 seccomp mode could not be verified'
fi
printf '%s\n' \
    "$launcher: $detail; refusing YOLO mode." \
    'This is not the YOLO container; on the host: bbcode or bbe (bbox --rebuild if it persists)' >&2
exit 1
