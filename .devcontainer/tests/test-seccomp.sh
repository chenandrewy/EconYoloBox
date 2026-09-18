#!/bin/bash
# Run:     bash .devcontainer/tests/test-seccomp.sh
# Inputs:  seccomp-setting.sh and check-seccomp.sh; creates temporary fixtures.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
reader="$root/.devcontainer/seccomp-setting.sh"
checker="$root/.devcontainer/check-seccomp.sh"
tmp=$(mktemp -d)
trap 'chmod -R u+rw "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
tests=0

fail() { printf 'not ok - %s\n' "$1"; exit 1; }
pass() { tests=$((tests + 1)); printf 'ok %d - %s\n' "$tests" "$1"; }

check_value() {
    name=$1 expected=$2 file=$3
    actual=$(bash "$reader" "$file" 2>"$tmp/err") || fail "$name exited nonzero"
    [ "$actual" = "$expected" ] || fail "$name: expected $expected, got $actual"
    pass "$name"
}

printf 'seccomp = "builtin"\n' >"$tmp/builtin.toml"
check_value 'accepts builtin' builtin "$tmp/builtin.toml"
printf 'seccomp = "unconfined" # needed for bwrap\n' >"$tmp/unconfined.toml"
check_value 'accepts unconfined' unconfined "$tmp/unconfined.toml"
printf 'firewall = false\n' >"$tmp/missing.toml"
check_value 'missing setting fails closed' builtin "$tmp/missing.toml"
grep -q 'setting is missing' "$tmp/err" || fail 'missing setting warning'
pass 'missing setting warns'

printf '[other]\nseccomp = "unconfined"\n' >"$tmp/table.toml"
check_value 'table-scoped value cannot authorize unconfined' builtin "$tmp/table.toml"
printf 'seccomp = "unconfined"\nseccomp = "builtin"\n' >"$tmp/duplicate-a.toml"
check_value 'duplicate unconfined then builtin fails closed' builtin "$tmp/duplicate-a.toml"
printf 'seccomp = "builtin"\nseccomp = "unconfined"\n' >"$tmp/duplicate-b.toml"
check_value 'duplicate builtin then unconfined fails closed' builtin "$tmp/duplicate-b.toml"
printf 'seccomp = ["unconfined"]\n' >"$tmp/array.toml"
check_value 'unsupported TOML fails closed' builtin "$tmp/array.toml"
printf 'seccomp = "unconfined"\ntimezone = "bad\\q"\n' >"$tmp/bad-escape.toml"
check_value 'invalid TOML escape cannot authorize unconfined' builtin "$tmp/bad-escape.toml"
grep -q 'unsupported string syntax on line 2' "$tmp/err" || fail 'invalid escape warning'
pass 'invalid TOML escape warns'
printf 'seccomp = "surprise"\n' >"$tmp/unknown.toml"
check_value 'unknown value fails closed' builtin "$tmp/unknown.toml"
check_value 'missing file fails closed' builtin "$tmp/no-such-file"
printf 'seccomp = "unconfined"\n' >"$tmp/unreadable.toml"
chmod 000 "$tmp/unreadable.toml"
if [ ! -r "$tmp/unreadable.toml" ]; then
    check_value 'unreadable file fails closed' builtin "$tmp/unreadable.toml"
else
    pass 'unreadable file check skipped for privileged test user'
fi

printf 'Seccomp:\t2\n' >"$tmp/filtered.status"
printf 'Seccomp:\t0\n' >"$tmp/unfiltered.status"
printf 'Seccomp:\t9\n' >"$tmp/unexpected.status"

bash "$checker" "$tmp/builtin.toml" "$tmp/filtered.status" 2>"$tmp/check.err"
[ ! -s "$tmp/check.err" ] || fail 'compatible builtin should be silent'
pass 'builtin with filtered PID 1 is silent'
bash "$checker" "$tmp/unconfined.toml" "$tmp/unfiltered.status" 2>"$tmp/check.err"
grep -q '^Warning: Seccomp Unconfined$' "$tmp/check.err" || fail 'unconfined posture warning'
grep -q 'bbox --rebuild on the host' "$tmp/check.err" || fail 'posture remediation'
if grep -q 'requested seccomp=' "$tmp/check.err"; then fail 'compatible unconfined is not a mismatch'; fi
pass 'compatible unconfined warns about posture without reporting a mismatch'
bash "$checker" "$tmp/builtin.toml" "$tmp/unfiltered.status" 2>"$tmp/check.err"
grep -q 'requested seccomp=builtin' "$tmp/check.err" || fail 'builtin mismatch warning'
grep -q '^Warning: Seccomp Unconfined$' "$tmp/check.err" || fail 'mismatch also needs posture warning'
pass 'builtin mismatch preserves both posture and consistency warnings'
bash "$checker" "$tmp/unconfined.toml" "$tmp/filtered.status" 2>"$tmp/check.err"
grep -q 'requested seccomp=unconfined' "$tmp/check.err" || fail 'unconfined mismatch warning'
pass 'unconfined mismatch warns'
bash "$checker" "$tmp/unknown.toml" "$tmp/filtered.status" 2>"$tmp/check.err"
grep -q "value 'surprise'" "$tmp/check.err" || fail 'invalid fallback diagnostic'
pass 'invalid config warns despite compatible fallback'
bash "$checker" "$tmp/builtin.toml" "$tmp/unexpected.status" 2>"$tmp/check.err"
grep -q 'could not be verified' "$tmp/check.err" || fail 'unexpected proc status warning'
pass 'unexpected PID 1 mode is unverified'
bash "$checker" "$tmp/builtin.toml" "$tmp/no-status" 2>"$tmp/check.err"
grep -q 'could not be verified' "$tmp/check.err" || fail 'unavailable proc status warning'
pass 'unavailable PID 1 status is unverified'

# The checker reads the file anew each time, so a bind-mounted edit is noticed.
printf 'seccomp = "builtin"\n' >"$tmp/edit.toml"
bash "$checker" "$tmp/edit.toml" "$tmp/filtered.status" 2>"$tmp/check.err"
[ ! -s "$tmp/check.err" ] || fail 'pre-edit compatibility'
printf 'seccomp = "unconfined"\n' >"$tmp/edit.toml"
bash "$checker" "$tmp/edit.toml" "$tmp/filtered.status" 2>"$tmp/check.err"
grep -q 'requested seccomp=unconfined' "$tmp/check.err" || fail 'post-edit recheck'
pass 'each check rereads SANDBOX.toml'

grep -q 'case \$- in' "$root/.devcontainer/shellrc.sh" || fail 'interactive startup guard'
pass 'shell startup wiring is interactive-only'
printf '1..%d\n' "$tests"
