#!/bin/bash
# ABOUTME: Prints one value from SANDBOX.toml. Shared by the host-side
# ABOUTME: write-local-env.sh and the in-container post-start.sh.
#
# Run:     bash .devcontainer/sandbox-setting.sh KEY [FILE]
# Inputs:  KEY, a bare TOML key; FILE defaults to SANDBOX.toml beside .devcontainer.
# Outputs: the value on stdout - a basic string's contents, or the bare word
#          true/false - or nothing if the key is absent, commented out, or
#          malformed. Exit 0 either way; a missing file is treated as empty.
#          Exits non-zero only if sed itself fails on a file that exists
#          (e.g. a Dropbox-evicted copy); callers must treat that as empty.
#
# Deliberately not a TOML parser: the file is flat `key = "value"` lines, and
# this has to run on the host (macOS bash 3.2, no guaranteed Python) and in the
# container before any stack is installed. Anything ambiguous yields nothing,
# and callers treat nothing as the safe default: a key that appears more than
# once (a stale line left beside a new one), a quoted boolean (`firewall =
# "false"` is a string, not false), or trailing junk (`firewall = false oops`).
# After the value, only whitespace or a # comment is allowed. String values
# must not contain double quotes. This matches seccomp-setting.sh's rejection
# of duplicate keys, so the two readers never disagree about one file.
set -euo pipefail

key=$1
file=${2:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/SANDBOX.toml"}

[ -r "$file" ] || exit 0
lhs="^[[:space:]]*${key}[[:space:]]*=[[:space:]]*"
rhs="[[:space:]]*(#.*)?$"
# Each match is tagged with its form (s: quoted string, b: bare boolean) so
# the checks below can tell `"false"` from `false`. The final pattern prints
# lines the substitutions did not consume, so a malformed duplicate still
# disqualifies the well-formed one: exactly one line may name the key.
lines=$(sed -n -E \
    -e "s/${lhs}\"([^\"]*)\"${rhs}/s:\1/p" \
    -e "s/${lhs}(true|false)${rhs}/b:\1/p" \
    -e "/${lhs}/p" \
    "$file")
[ -n "$lines" ] || exit 0
[ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" -eq 1 ] || exit 0
value=$(printf '%s\n' "$lines" | sed -n 1p)
case "$value" in
    s:true|s:false) exit 0 ;;
    s:*|b:*) printf '%s\n' "${value#??}" ;;
esac
