#!/bin/bash
# ABOUTME: Strictly validates flat SANDBOX.toml syntax and prints its seccomp policy.
# ABOUTME: Shared by the macOS host launcher and interactive container shells.
#
# Run:     bash .devcontainer/seccomp-setting.sh [FILE]
# Inputs:  FILE defaults to SANDBOX.toml beside .devcontainer.
# Outputs: builtin or unconfined on stdout. Invalid, missing, unreadable, or
#          unsupported input warns on stderr and safely resolves to builtin.
#
# Supported TOML is deliberately small: blank/comment lines and unique, bare
# `key = value` assignments, where value is true, false, or a double-quoted
# string without escapes, embedded double quotes, or control characters. Tables,
# arrays, dotted/quoted keys, multiline values, duplicate keys, and all other
# TOML constructs are rejected.
# This runs under macOS bash 3.2 and inside the container; it does not depend on
# Python or a platform TOML library.
set -u

file=${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SANDBOX.toml"}

warn_builtin() {
    printf 'SANDBOX.toml: %s; using seccomp = "builtin"\n' "$1" >&2
    printf '%s\n' builtin
}

if [ ! -e "$file" ]; then
    warn_builtin "missing $file"
    exit 0
fi
if [ ! -r "$file" ]; then
    warn_builtin "cannot read $file"
    exit 0
fi

parsed=$(
    awk '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^[[:space:]]*($|#)/) next
            if (line !~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=[[:space:]]*(true|false|"[^"]*")[[:space:]]*(#.*)?$/) {
                printf "unsupported syntax on line %d", NR
                error = 1
                exit 2
            }
            string_value = line
            sub(/^[^=]*=[[:space:]]*/, "", string_value)
            if (string_value ~ /^"/) {
                sub(/^"/, "", string_value)
                sub(/"[[:space:]]*(#.*)?$/, "", string_value)
                if (string_value ~ /\\/ || string_value ~ /[[:cntrl:]]/) {
                    printf "unsupported string syntax on line %d", NR
                    error = 1
                    exit 2
                }
            }
            key = line
            sub(/[[:space:]]*=.*/, "", key)
            key = trim(key)
            if (seen[key]++) {
                printf "duplicate key %s", key
                error = 1
                exit 2
            }
            if (key == "seccomp") {
                value = line
                sub(/^[^=]*=[[:space:]]*/, "", value)
                if (value ~ /^"/) {
                    sub(/^"/, "", value)
                    sub(/"[[:space:]]*(#.*)?$/, "", value)
                } else {
                    sub(/[[:space:]]*(#.*)?$/, "", value)
                }
                seccomp = value
                found = 1
            }
        }
        END {
            if (!found && !error) {
                if (NR || !found) printf "%s", "__MISSING__"
            } else if (found && !error) {
                printf "%s", seccomp
            }
        }
    ' "$file"
)
status=$?

if [ "$status" -ne 0 ]; then
    warn_builtin "${parsed:-could not parse $file}"
    exit 0
fi

case "$parsed" in
    builtin|unconfined)
        printf '%s\n' "$parsed"
        ;;
    __MISSING__)
        warn_builtin 'seccomp setting is missing'
        ;;
    *)
        warn_builtin "seccomp value '$parsed' is not builtin or unconfined"
        ;;
esac
