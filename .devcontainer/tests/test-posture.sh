#!/bin/bash
# Run:     bash .devcontainer/tests/test-posture.sh
# Inputs:  posture.sh, check-yolo-boundaries.sh, vscode-posture.sh and
#          devcontainer.json; creates temporary fixtures.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
# shellcheck disable=SC2016 # literal ${...} from devcontainer.json and VS Code titles
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
posture="$root/.devcontainer/posture.sh"
guard="$root/.devcontainer/check-yolo-boundaries.sh"
colors="$root/.devcontainer/vscode-posture.sh"
config="$root/.devcontainer/devcontainer.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tests=0

fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { tests=$((tests + 1)); printf 'ok %d - %s\n' "$tests" "$1"; }

printf 'Seccomp:\t2\n' >"$tmp/filtered.status"
printf 'Seccomp:\t0\n' >"$tmp/unfiltered.status"
printf 'Seccomp:\t9\n' >"$tmp/unexpected.status"
touch "$tmp/open-marker"

check_posture() {
    name=$1 expected=$2
    shift 2
    actual=$(bash "$posture" "$@") || fail "$name exited nonzero"
    [ "$actual" = "$expected" ] || fail "$name: expected '$expected', got '$actual'"
    pass "$name"
}
check_posture 'yolo preset' 'yolo internet=firewalled packages=readonly seccomp=builtin' \
    "$tmp/closed-marker" "$tmp/filtered.status" readonly
check_posture 'normie preset' 'normie internet=open packages=writable seccomp=unconfined' \
    "$tmp/open-marker" "$tmp/unfiltered.status" writable
check_posture 'open firewall alone is custom' 'custom internet=open packages=readonly seccomp=builtin' \
    "$tmp/open-marker" "$tmp/filtered.status" readonly
check_posture 'mixed package mounts are custom' 'custom internet=firewalled packages=mixed seccomp=builtin' \
    "$tmp/closed-marker" "$tmp/filtered.status" 'mixed: /opt/venv writable, /usr/local/texlive readonly'
check_posture 'unexpected seccomp mode is unverified' 'custom internet=firewalled packages=readonly seccomp=unverified' \
    "$tmp/closed-marker" "$tmp/unexpected.status" readonly
check_posture 'missing PID 1 status is unverified' 'custom internet=firewalled packages=readonly seccomp=unverified' \
    "$tmp/closed-marker" "$tmp/no-status" readonly

bash "$guard" test-yolo "$tmp/closed-marker" "$tmp/filtered.status" 2>"$tmp/guard.err" || fail 'filtered yolo guard should pass'
[ ! -s "$tmp/guard.err" ] || fail 'filtered yolo guard should be silent'
pass 'yolo allows filtered seccomp with firewall armed'
if bash "$guard" test-yolo "$tmp/open-marker" "$tmp/filtered.status" 2>"$tmp/guard.err"; then fail 'open firewall should refuse yolo'; fi
grep -q 'firewall is open' "$tmp/guard.err" || fail 'open firewall refusal diagnostic'
grep -q 'without --normie' "$tmp/guard.err" || fail 'open firewall recovery'
pass 'yolo refuses an open firewall'
if bash "$guard" test-yolo "$tmp/closed-marker" "$tmp/unfiltered.status" 2>"$tmp/guard.err"; then fail 'unconfined seccomp should refuse yolo'; fi
grep -q 'seccomp is unconfined' "$tmp/guard.err" || fail 'unconfined refusal diagnostic'
grep -q 'without --normie' "$tmp/guard.err" || fail 'unconfined recovery command'
pass 'yolo refuses unconfined seccomp'
if bash "$guard" test-yolo "$tmp/closed-marker" "$tmp/unexpected.status" 2>"$tmp/guard.err"; then fail 'unverified seccomp should refuse yolo'; fi
grep -q 'could not be verified' "$tmp/guard.err" || fail 'unverified refusal diagnostic'
pass 'yolo refuses unverified seccomp'
guard_calls=$(grep -c 'check-yolo-boundaries.sh' "$root/.devcontainer/shellrc.sh")
[ "$guard_calls" -eq 3 ] || fail 'all three yolo launchers must call the boundary guard'
pass 'all supplied yolo launchers use the boundary guard'

# Creation that bypasses bbox sees no variables and must land in YOLO mode.
grep -q 'seccomp=${localEnv:SANDBOX_SECCOMP:builtin}' "$config" || fail 'VS Code seccomp fallback'
[ "$(grep -c 'readonly=${localEnv:SANDBOX_PKG_READONLY:true}' "$config")" -eq 3 ] ||
    fail 'all three package mounts must follow SANDBOX_PKG_READONLY'
grep -q '"SANDBOX_INTERNET": "${localEnv:SANDBOX_INTERNET:firewalled}"' "$config" || fail 'VS Code internet fallback'
pass 'direct VS Code creation falls back to YOLO mode'

printf '{"window.title": "<${rootName}>", "workbench.colorCustomizations": {"editor.background": "#000000"}}\n' >"$tmp/settings.json"
cp "$tmp/settings.json" "$tmp/yolo.json"
bash "$colors" "$tmp/yolo.json" 'yolo internet=firewalled packages=readonly seccomp=builtin'
cmp -s "$tmp/settings.json" "$tmp/yolo.json" || fail 'yolo must leave VS Code settings alone'
pass 'yolo mode leaves the window alone'
bash "$colors" "$tmp/settings.json" 'normie internet=open packages=writable seccomp=unconfined'
bash "$colors" "$tmp/settings.json" 'normie internet=open packages=writable seccomp=unconfined'
[ "$(jq -r '."window.title"' "$tmp/settings.json")" = 'NORMIE MODE - <${rootName}>' ] || fail 'normie title, once'
[ "$(jq -r '."workbench.colorCustomizations"."titleBar.activeBackground"' "$tmp/settings.json")" = '#b91c1c' ] || fail 'normie title bar'
[ "$(jq -r '."workbench.colorCustomizations"."editor.background"' "$tmp/settings.json")" = '#000000' ] || fail 'other colors kept'
pass 'normie mode colors and titles the window once, keeping other settings'
bash "$colors" "$tmp/new/settings.json" 'custom internet=open packages=readonly seccomp=builtin'
[ "$(jq -r '."window.title"' "$tmp/new/settings.json")" = 'CUSTOM POSTURE - ${rootName}${separator}${activeEditorShort}' ] || fail 'custom title in a new file'
pass 'a custom posture is marked too, in a file that did not exist'
printf '{ // a comment\n}\n' >"$tmp/jsonc.json"
bash "$colors" "$tmp/jsonc.json" 'normie x' 2>"$tmp/colors.err" || fail 'unparseable settings must not fail'
grep -q 'could not parse' "$tmp/colors.err" || fail 'unparseable settings warning'
grep -q '// a comment' "$tmp/jsonc.json" || fail 'unparseable settings left alone'
pass 'settings jq cannot parse are left alone with a warning'

printf '1..%d\n' "$tests"
