#!/bin/bash
# ABOUTME: Prints this container's security posture, read from the container.
# ABOUTME: Shared by post-start.sh, shellrc.sh and the status line.
#
# Run:     bash .devcontainer/posture.sh [OPEN_MARKER] [PROC_STATUS] [PACKAGES]
# Inputs:  the firewall-open marker post-start.sh leaves, PID 1's seccomp mode,
#          and the package mounts (package-mode.sh). The optional arguments
#          stand in for them in tests; PACKAGES is a literal mode.
# Outputs: one line on stdout, the posture name then its three settings:
#            yolo internet=firewalled packages=readonly seccomp=builtin
#            normie internet=open packages=writable seccomp=unconfined
#          and any other combination as custom. Always exits 0.
#
# bbox on the host picks the posture when it creates the container (--yolo,
# the default, or --normie), and all three settings are fixed from then on, so
# this reads the container itself; no file in the workspace takes part.
#
# internet is post-start.sh's decision, recorded by its marker, not a network
# probe: dnsmasq and resolv.conf look "open" on init-firewall.sh's legitimate
# armed-but-dnsmasq-failed path, and iptables needs root. The open side writes
# the marker because /tmp is not tmpfs here: a stale "armed" marker would fail
# silent, whereas a stale open one only cries wolf. A bare `docker restart`
# skips postStartCommand and leaves whatever marker was there before.

open_marker=${1:-/tmp/FIREWALL-WINDOW-OPEN}
proc_status=${2:-/proc/1/status}
packages=${3:-$(bash "$(dirname "${BASH_SOURCE[0]}")/package-mode.sh")}

if [ -e "$open_marker" ]; then
    internet=open
else
    internet=firewalled
fi
# "mixed: ..." has spaces; one word keeps the line parseable.
case "$packages" in
    readonly | writable) ;;
    *) packages=mixed ;;
esac
case "$(sed -n -E 's/^Seccomp:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$proc_status" 2>/dev/null | head -n 1)" in
    2) seccomp=builtin ;;
    0) seccomp=unconfined ;;
    *) seccomp=unverified ;;
esac

settings="internet=$internet packages=$packages seccomp=$seccomp"
case "$settings" in
    "internet=firewalled packages=readonly seccomp=builtin") name=yolo ;;
    "internet=open packages=writable seccomp=unconfined") name=normie ;;
    *) name=custom ;;
esac
printf '%s %s\n' "$name" "$settings"
