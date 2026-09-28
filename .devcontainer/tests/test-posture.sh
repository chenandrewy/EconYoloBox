#!/bin/bash
# Run:     bash .devcontainer/tests/test-posture.sh
# Inputs:  posture.sh, check-yolo-boundaries.sh, check-checkout.sh and
#          post-start.sh; creates temporary fixtures.
#          The two config files have their own test, test_config_twins.py.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
posture="$root/.devcontainer/posture.sh"
guard="$root/.devcontainer/check-yolo-boundaries.sh"
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

printf '1..%d\n' "$tests"
