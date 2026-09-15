#!/bin/bash
# ABOUTME: Prints one value from SANDBOX.toml. Shared by the host-side
# ABOUTME: write-local-env.sh and the in-container post-start.sh.
#
# Run:     bash .devcontainer/sandbox-setting.sh KEY [FILE]
# Inputs:  KEY, a bare TOML key; FILE defaults to SANDBOX.toml beside .devcontainer.
# Outputs: the value on stdout - a basic string's contents, or the bare word
#          true/false - or nothing if the key is absent, commented out, or
#          malformed. Exit 0 either way; a missing file is treated as empty.
#
# Deliberately not a TOML parser: the file is flat `key = "value"` lines, and
# this has to run on the host (macOS bash 3.2, no guaranteed Python) and in the
# container before any stack is installed. Only the first uncommented match
# counts. After the value, only whitespace or a # comment is allowed, so
# `firewall = false oops` yields nothing rather than false - callers treat
# nothing as the safe default. String values must not contain double quotes.
set -euo pipefail

key=$1
file=${2:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SANDBOX.toml"}

[ -r "$file" ] || exit 0
lhs="^[[:space:]]*${key}[[:space:]]*=[[:space:]]*"
rhs="[[:space:]]*(#.*)?$"
sed -n -E \
    -e "s/${lhs}\"([^\"]*)\"${rhs}/\1/p" \
    -e "s/${lhs}(true|false)${rhs}/\1/p" \
    "$file" | head -n 1
