#!/bin/bash
# Run:     bash .devcontainer/tests/test-internet.sh
# Inputs:  internet-setting.sh and temporary SANDBOX.toml fixtures.
# Outputs: pass/fail lines and nonzero status on failure.
set -eu

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
reader="$root/.devcontainer/internet-setting.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check_mode() {
    expected=$1 content=$2
    printf '%s\n' "$content" >"$tmp/SANDBOX.toml"
    actual=$(bash "$reader" "$tmp/SANDBOX.toml" 2>"$tmp/warning")
    [ "$actual" = "$expected" ] || {
        printf 'expected %s, got %s for %s\n' "$expected" "$actual" "$content" >&2
        exit 1
    }
}

check_mode firewalled 'internet = "firewalled"'
[ ! -s "$tmp/warning" ]
check_mode open 'internet = "open"'
[ ! -s "$tmp/warning" ]
check_mode firewalled 'firewall = false'
[ -s "$tmp/warning" ]
check_mode firewalled 'internet = "other"'
[ -s "$tmp/warning" ]
check_mode firewalled $'internet = "firewalled"\ninternet = "open"'
[ -s "$tmp/warning" ]
check_mode firewalled 'internet = "open" trailing junk'
[ -s "$tmp/warning" ]

printf 'internet modes and safe fallback: ok\n'
