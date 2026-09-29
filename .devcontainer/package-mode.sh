#!/bin/bash
# ABOUTME: Prints how the R, Python and TeX package volumes are actually mounted.
# ABOUTME: Used by posture.sh and tests/test-packages.sh.
#
# Run:     bash .devcontainer/package-mode.sh
# Inputs:  the live mounts of /opt/venv, R's site library and /usr/local/texlive.
# Outputs: readonly, writable, or "mixed: <details>" on stdout; always exits 0.
#          A path that is not a mount point counts as writable, since the
#          container can write it (into its disposable image layer).
#
# The live mounts visible to this process. An agent sandbox may remount
# writable normie volumes read-only for its own commands.

site_library=$(find /opt/R -mindepth 4 -maxdepth 4 -type d -path '*/lib/R/site-library' -print -quit 2>/dev/null)
modes=()
for mount in /opt/venv "$site_library" /usr/local/texlive; do
    [ -n "$mount" ] || continue
    if findmnt -n -o OPTIONS -T "$mount" 2>/dev/null | tr ',' '\n' | grep -qx ro; then
        modes+=("$mount readonly")
    else
        modes+=("$mount writable")
    fi
done
unique=$(printf '%s\n' "${modes[@]}" | awk '{ print $2 }' | sort -u)
case "$unique" in
readonly | writable) echo "$unique" ;;
*) echo "mixed: $(printf '%s, ' "${modes[@]}" | sed 's/, $//')" ;;
esac
