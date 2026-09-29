#!/bin/bash
# ABOUTME: Reports the container mode and the calling process's package access.
# ABOUTME: Shared by post-start.sh, shellrc.sh and the status line.
#
# Run:     bash .devcontainer/posture.sh [OPEN_MARKER] [PROC_STATUS] [PACKAGE_ACCESS]
# Inputs:  YOLOBOX_MODE from the container config, the firewall-open marker,
#          PID 1's seccomp mode, and package mounts visible to this process
#          (package-mode.sh). Optional arguments replace the last three in tests.
# Outputs: one line on stdout: mode, internet, package_access and seccomp.
#          "custom" means the declared mode conflicts with the live settings,
#          or, with no declared mode, the settings match neither older preset.
#          Exits 0.
#
# A Codex command sandbox can see read-only package mounts in a normie
# container. The mode comes from containerEnv; package_access stays the live
# mount view, so callers can distinguish the container from their own access.
# Existing containers without YOLOBOX_MODE retain the old classification until
# recreated, so their extension installer and shell prompt keep working.
#
# Caveat, internet: this reports what post-start.sh decided at the last start,
# not the live iptables rules. post-start.sh creates /tmp/FIREWALL-WINDOW-OPEN
# when it leaves the internet open and deletes it when it arms the firewall;
# no marker reads as firewalled. A network probe is not used because iptables
# needs root and init-firewall.sh has a legitimate armed-but-dnsmasq-failed
# path that would look open. The marker is kept on the open side so an
# unexpected leftover marker errs toward a false "open" alarm, never a false
# "firewalled". /tmp is not tmpfs here, so the marker survives restarts, and a
# bare `docker restart` skips post-start.sh: after one, the marker describes
# the previous start and the firewall rules may be gone. Restart through ybox
# or VS Code so post-start.sh runs.

open_marker=${1:-/tmp/FIREWALL-WINDOW-OPEN}
proc_status=${2:-/proc/1/status}
package_access=${3:-$(bash "$(dirname "${BASH_SOURCE[0]}")/package-mode.sh")}

if [ -e "$open_marker" ]; then
    internet=open
else
    internet=firewalled
fi
# "mixed: ..." has spaces; one word keeps the line parseable.
case "$package_access" in
    readonly | writable) ;;
    *) package_access=mixed ;;
esac
case "$(sed -n -E 's/^Seccomp:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$proc_status" 2>/dev/null | head -n 1)" in
    2) seccomp=builtin ;;
    0) seccomp=unconfined ;;
    *) seccomp=unverified ;;
esac

# The configured mode describes the container; package access describes this
# process. Keep live boundary checks so a mislabeled container reports custom.
if [ -n "${YOLOBOX_MODE:-}" ]; then
    case "$YOLOBOX_MODE:$internet:$seccomp:$package_access" in
        normie:open:unconfined:*) name=normie ;;
        yolo:firewalled:builtin:readonly) name=yolo ;;
        *) name=custom ;;
    esac
else
    # Containers created before YOLOBOX_MODE keep their previous behavior.
    case "$internet:$seccomp:$package_access" in
        open:unconfined:writable) name=normie ;;
        firewalled:builtin:readonly) name=yolo ;;
        *) name=custom ;;
    esac
fi
printf '%s internet=%s package_access=%s seccomp=%s\n' \
    "$name" "$internet" "$package_access" "$seccomp"
