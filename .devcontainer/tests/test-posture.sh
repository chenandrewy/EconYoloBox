#!/bin/bash
# Run:     bash .devcontainer/tests/test-posture.sh
# Inputs:  posture.sh, check-yolo-boundaries.sh, vscode-posture.sh,
#          check-checkout.sh and post-start.sh; creates temporary fixtures.
#          The two config files have their own test, test_config_twins.py.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
# shellcheck disable=SC2016 # literal ${...} in VS Code titles
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
posture="$root/.devcontainer/posture.sh"
guard="$root/.devcontainer/check-yolo-boundaries.sh"
colors="$root/.devcontainer/vscode-posture.sh"
checkout="$root/.devcontainer/check-checkout.sh"
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
grep -q 'not the YOLO container' "$tmp/guard.err" || fail 'open firewall recovery'
pass 'yolo refuses an open firewall'
if bash "$guard" test-yolo "$tmp/closed-marker" "$tmp/unfiltered.status" 2>"$tmp/guard.err"; then fail 'unconfined seccomp should refuse yolo'; fi
grep -q 'seccomp is unconfined' "$tmp/guard.err" || fail 'unconfined refusal diagnostic'
grep -q 'not the YOLO container' "$tmp/guard.err" || fail 'unconfined recovery command'
pass 'yolo refuses unconfined seccomp'
if bash "$guard" test-yolo "$tmp/closed-marker" "$tmp/unexpected.status" 2>"$tmp/guard.err"; then fail 'unverified seccomp should refuse yolo'; fi
grep -q 'could not be verified' "$tmp/guard.err" || fail 'unverified refusal diagnostic'
pass 'yolo refuses unverified seccomp'
guard_calls=$(grep -c 'check-yolo-boundaries.sh' "$root/.devcontainer/shellrc.sh")
[ "$guard_calls" -eq 3 ] || fail 'all three yolo launchers must call the boundary guard'
pass 'all supplied yolo launchers use the boundary guard'

# One checkout per basename: the first folder is recorded, a second refused.
bash "$checkout" "$tmp/checkout" /Users/me/1-SANDBOX 2>"$tmp/checkout.err" || fail 'first checkout should be recorded'
[ "$(cat "$tmp/checkout")" = /Users/me/1-SANDBOX ] || fail 'checkout marker content'
bash "$checkout" "$tmp/checkout" /Users/me/1-SANDBOX 2>"$tmp/checkout.err" || fail 'same checkout should pass'
[ ! -s "$tmp/checkout.err" ] || fail 'same checkout should be silent'
pass 'the first checkout is recorded and then accepted'
if bash "$checkout" "$tmp/checkout" /Users/me/test/1-SANDBOX 2>"$tmp/checkout.err"; then fail 'another checkout should be refused'; fi
grep -q 'REFUSING' "$tmp/checkout.err" && grep -q "rm $tmp/checkout" "$tmp/checkout.err" || fail 'refusal message'
[ "$(cat "$tmp/checkout")" = /Users/me/1-SANDBOX ] || fail 'refusal must not rewrite the marker'
pass 'a same-basename checkout elsewhere is refused, with the way to accept a move'
bash "$checkout" "$tmp/checkout" '' 2>"$tmp/checkout.err" || fail 'unknown folder should not refuse'
grep -q 'not checked' "$tmp/checkout.err" || fail 'unknown folder warning'
pass 'an unknown host folder warns and is not refused'
grep -q '^bash .devcontainer/check-checkout.sh$' "$root/.devcontainer/post-start.sh" || fail 'post-start must run the checkout guard'
pass 'post-start runs the checkout guard'

printf '{"window.title": "<${rootName}>", "workbench.colorCustomizations": {"editor.background": "#000000"}}\n' >"$tmp/settings.json"
cp "$tmp/settings.json" "$tmp/yolo.json"
bash "$colors" "$tmp/yolo.json" 'yolo internet=firewalled packages=readonly seccomp=builtin'
cmp -s "$tmp/settings.json" "$tmp/yolo.json" || fail 'yolo must leave VS Code settings alone'
pass 'yolo mode leaves the window alone'
bash "$colors" "$tmp/settings.json" 'normie internet=open packages=writable seccomp=unconfined'
bash "$colors" "$tmp/settings.json" 'normie internet=open packages=writable seccomp=unconfined'
[ "$(jq -r '."window.title"' "$tmp/settings.json")" = 'NORMIE:<${rootName}>' ] || fail 'normie title, once'
[ "$(jq -c '."workbench.colorCustomizations"' "$tmp/settings.json")" = '{"editor.background":"#000000"}' ] || fail 'normie must not color the window'
pass 'normie mode titles the window once, uncolored, keeping other settings'
printf '{"window.title": "NORMIE MODE - x", "workbench.colorCustomizations": {"titleBar.activeBackground": "#b91c1c", "statusBar.background": "#123456"}}\n' >"$tmp/old.json"
bash "$colors" "$tmp/old.json" 'normie internet=open packages=writable seccomp=unconfined'
[ "$(jq -r '."window.title"' "$tmp/old.json")" = 'NORMIE:x' ] || fail 'old title prefix replaced'
[ "$(jq -c '."workbench.colorCustomizations"' "$tmp/old.json")" = '{"statusBar.background":"#123456"}' ] || fail 'old colors removed, own colors kept'
pass 'earlier versions'"'"' title prefix and colors are replaced, the user'"'"'s own colors kept'
printf '{"window.title": "NORMIE - x"}\n' >"$tmp/dash.json"
bash "$colors" "$tmp/dash.json" 'normie internet=open packages=writable seccomp=unconfined'
[ "$(jq -r '."window.title"' "$tmp/dash.json")" = 'NORMIE:x' ] || fail 'dash prefix replaced'
pass 'the "NORMIE - " prefix becomes "NORMIE:"'
bash "$colors" "$tmp/new/settings.json" 'custom internet=open packages=readonly seccomp=builtin'
[ "$(jq -r '."window.title"' "$tmp/new/settings.json")" = 'CUSTOM:${rootName}${separator}${activeEditorShort}' ] || fail 'custom title in a new file'
pass 'a custom posture is marked too, in a file that did not exist'
printf '{ // a comment\n}\n' >"$tmp/jsonc.json"
bash "$colors" "$tmp/jsonc.json" 'normie x' 2>"$tmp/colors.err" || fail 'unparseable settings must not fail'
grep -q 'could not parse' "$tmp/colors.err" || fail 'unparseable settings warning'
grep -q '// a comment' "$tmp/jsonc.json" || fail 'unparseable settings left alone'
pass 'settings jq cannot parse are left alone with a warning'

printf '1..%d\n' "$tests"
