#!/bin/bash
# Run:     bash .devcontainer/tests/test-git-identity.sh
# Inputs:  git-identity.sh and host/write-local-env.sh; each case runs with a
#          temporary HOME and GIT_CONFIG_GLOBAL, so the real ~/.gitconfig and
#          /tmp/devcontainer-local.env are untouched.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/.devcontainer/git-identity.sh"
writer="$root/.devcontainer/host/write-local-env.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tests=0

fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { tests=$((tests + 1)); printf 'ok %d - %s\n' "$tests" "$1"; }

# Each case gets a fresh global config; the host values come from arguments.
run_case() {
    name=$1 host_name=$2 host_email=$3
    export HOME="$tmp/$name" GIT_CONFIG_GLOBAL="$tmp/$name/.gitconfig"
    mkdir -p "$HOME"
    : >"$GIT_CONFIG_GLOBAL"
}
apply() { HOST_GIT_USER_NAME="$host_name" HOST_GIT_USER_EMAIL="$host_email" bash "$script" 2>"$HOME/stderr"; }
get() { git config --global "user.$1" || true; }

run_case fresh 'Jane Q. Doe' 'jane@example.com'
apply || fail 'fresh: exited nonzero'
[ "$(get name)" = 'Jane Q. Doe' ] && [ "$(get email)" = 'jane@example.com' ] || fail 'fresh: identity not set'
[ ! -s "$HOME/stderr" ] || fail 'fresh: unexpected warning'
pass 'sets name (with spaces) and email from the host'

run_case keep 'Host Name' 'host@example.com'
git config --global user.name 'Container Name'
git config --global credential.https://github.com.helper '!gh auth git-credential'
apply || fail 'keep: exited nonzero'
[ "$(get name)" = 'Container Name' ] || fail 'keep: overwrote an existing name'
[ "$(get email)" = 'host@example.com' ] || fail 'keep: missing email not filled'
[ "$(git config --global credential.https://github.com.helper)" = '!gh auth git-credential' ] ||
    fail 'keep: credential helper lost'
pass 'keeps existing values and other keys, fills only what is missing'

run_case rerun 'Jane Q. Doe' 'jane@example.com'
apply && apply || fail 'rerun: exited nonzero'
[ "$(git config --global --get-all user.name | wc -l)" -eq 1 ] || fail 'rerun: duplicated user.name'
pass 'idempotent across starts'

run_case none '' ''
apply || fail 'none: exited nonzero'
[ -z "$(get name)" ] && [ -z "$(get email)" ] || fail 'none: set something from nothing'
grep -q 'no global Git user.name/user.email' "$HOME/stderr" || fail 'none: no warning'
pass 'warns, without failing, when the host supplied nothing'

# The host side: write-local-env.sh writes a fixed path, so run a copy that
# writes into the temp directory instead.
run_case writer '' ''
git config --global user.name 'Jane Q. Doe'
git config --global user.email 'jane@example.com'
git config --global credential.helper osxkeychain
mkdir -p "$tmp/host"
sed "s|^ENV_FILE=.*|ENV_FILE=$tmp/host/local.env|" "$writer" >"$tmp/host/write-local-env.sh"
bash "$tmp/host/write-local-env.sh" || fail 'writer: exited nonzero'
grep -qx 'HOST_GIT_USER_NAME=Jane Q. Doe' "$tmp/host/local.env" || fail 'writer: no name line'
grep -qx 'HOST_GIT_USER_EMAIL=jane@example.com' "$tmp/host/local.env" || fail 'writer: no email line'
! grep -qi 'osxkeychain\|helper' "$tmp/host/local.env" || fail 'writer: leaked a credential helper'
pass 'host writer emits the identity and nothing else from gitconfig'

: >"$GIT_CONFIG_GLOBAL"
bash "$tmp/host/write-local-env.sh" || fail 'writer without identity: exited nonzero'
! grep -q '^HOST_GIT_USER_' "$tmp/host/local.env" || fail 'writer without identity: emitted empty lines'
pass 'host writer succeeds and omits the lines when the host has no identity'

printf '1..%d\n' "$tests"
