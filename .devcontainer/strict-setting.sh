#!/bin/bash
# ABOUTME: Strictly validates flat SANDBOX.toml syntax and prints one enumerated
# ABOUTME: setting. Shared by the macOS host launcher and the container.
#
# Run:     bash .devcontainer/strict-setting.sh KEY "SAFE OTHER..." [FILE]
#          Usually through a wrapper: seccomp-setting.sh, packages-setting.sh.
# Inputs:  KEY, a bare TOML key; its allowed values, space-separated, the first
#          being the safe fallback; FILE defaults to SANDBOX.toml beside
#          .devcontainer.
# Outputs: one allowed value on stdout. Invalid, missing, unreadable, or
#          unsupported input warns on stderr and resolves to the safe value.
#
# Supported TOML is deliberately small: blank/comment lines and unique, bare
# `key = value` assignments, where value is true, false, or a double-quoted
# string without escapes, embedded double quotes, or control characters. Tables,
# arrays, dotted/quoted keys, multiline values, duplicate keys, and all other
# TOML constructs are rejected.
# This runs under macOS bash 3.2 and inside the container; it does not depend on
# Python or a platform TOML library.
set -u

key=$1
allowed=$2
safe=${allowed%% *}
file=${3:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SANDBOX.toml"}

warn_safe() {
    printf 'SANDBOX.toml: %s; using %s = "%s"\n' "$1" "$key" "$safe" >&2
    printf '%s\n' "$safe"
}

if [ ! -e "$file" ]; then
    warn_safe "missing $file"
    exit 0
fi
if [ ! -r "$file" ]; then
    warn_safe "cannot read $file"
    exit 0
fi

parsed=$(
    awk -v wanted="$key" '
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
            if (key == wanted) {
                value = line
                sub(/^[^=]*=[[:space:]]*/, "", value)
                if (value ~ /^"/) {
                    sub(/^"/, "", value)
                    sub(/"[[:space:]]*(#.*)?$/, "", value)
                } else {
                    sub(/[[:space:]]*(#.*)?$/, "", value)
                }
                result = value
                found = 1
            }
        }
        END {
            if (!found && !error) {
                if (NR || !found) printf "%s", "__MISSING__"
            } else if (found && !error) {
                printf "%s", result
            }
        }
    ' "$file"
)
status=$?

if [ "$status" -ne 0 ]; then
    warn_safe "${parsed:-could not parse $file}"
    exit 0
fi

if [ "$parsed" = __MISSING__ ]; then
    warn_safe "$key setting is missing"
    exit 0
fi
for value in $allowed; do
    if [ "$parsed" = "$value" ]; then
        printf '%s\n' "$parsed"
        exit 0
    fi
done
warn_safe "$key value '$parsed' is not one of: $allowed"
