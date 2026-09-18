#!/usr/bin/env zsh
# Run:     zsh .host/tests/test-bbox.zsh
# Inputs:  host bbox implementation; mocks Docker, Dev Containers, and VS Code.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
setopt errexit nounset pipefail

root=${0:A:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log=$tmp/calls
typeset -g MOCK_POLICY=unconfined
typeset -g MOCK_CONTAINERS='' MOCK_VSCODE=0

alias dcu='devcontainer up --workspace-folder .'
dccode() { :; }
source "$root/.host/devcontainer.zsh"

devcontainer() {
  print -r -- "seccomp=${SANDBOX_SECCOMP:-}|$*" >>$log
  if [[ "$1" == up ]]; then
    print -r -- '{"outcome":"success","containerId":"container-123"}'
  fi
}
docker() {
  print -r -- "docker|$*" >>$log
  if [[ "$1" == inspect ]]; then
    case "$MOCK_POLICY" in
      inspect-fail) return 1 ;;
      custom) print -r -- '["seccomp=/tmp/custom.json"]' ;;
      *) print -r -- "[\"seccomp=$MOCK_POLICY\"]" ;;
    esac
  elif [[ "$1 $2" == 'context show' ]]; then
    print -r -- desktop-linux
  elif [[ "$1" == ps ]]; then
    if [[ -n "$MOCK_CONTAINERS" ]]; then print -l -- ${=MOCK_CONTAINERS}; fi
  elif [[ "$1" == exec ]]; then
    (( MOCK_VSCODE )) && return 0
    return 1
  fi
}
code() { print -r -- "code|$*" >>$log; }

fail() { print -r -- "not ok - $1"; exit 1; }
typeset -gi tests=0
pass() { (( ++tests )); print -r -- "ok $tests - $1"; }

(( ! $+aliases[dcu] )) || fail 'legacy dcu alias survived reload'
(( ! $+functions[dccode] )) || fail 'legacy dccode function survived reload'
(( $+functions[bbu] && $+functions[bbe] && $+functions[bbcode] )) || fail 'short wrappers missing after reload'
pass 'reload removes legacy dcu/dce/dccode names and defines bbu/bbe/bbcode'

: >$log
bbox "$root"
grep -q "seccomp=unconfined|up --workspace-folder $root" $log || fail 'ordinary up construction'
grep -q 'docker|inspect --format .* container-123' $log || fail 'exact returned container inspection'
pass 'ordinary up exports policy and inspects returned container'

original_resolve=$functions[_dc_resolve]
mkdir -p "$tmp/builtin-root/.devcontainer"
cp "$root/.devcontainer/seccomp-setting.sh" "$tmp/builtin-root/.devcontainer/"
printf '%s\n' 'seccomp = "builtin"' >"$tmp/builtin-root/SANDBOX.toml"
printf '%s\n' '{"workspaceFolder":"/workspace"}' >"$tmp/builtin-root/.devcontainer/devcontainer.json"
_dc_resolve() { print -r -- "$tmp/builtin-root"; print -r -- /workspace; }
MOCK_POLICY=builtin
: >$log
bbox "$tmp/builtin-root"
grep -q 'seccomp=builtin|up --workspace-folder' $log || fail 'builtin propagation'
pass 'builtin policy reaches the same host bring-up path'
functions[_dc_resolve]=$original_resolve
MOCK_POLICY=unconfined

: >$log
bbox --rebuild "$root" >/dev/null
grep -q -- '--remove-existing-container' $log || fail 'rebuild flag'
pass '--rebuild removes and recreates with cache'

: >$log
bbox --rebuild-without-cache "$root" >/dev/null
grep -q -- '--remove-existing-container --build-no-cache' $log || fail 'no-cache flags'
pass '--rebuild-without-cache adds both CLI flags'

if bbox --rebuild --rebuild-without-cache "$root" >/dev/null 2>&1; then fail 'rebuild conflict'; fi
pass 'rebuild flags conflict'
if bbox --shell --code "$root" >/dev/null 2>&1; then fail 'action conflict'; fi
pass 'shell and code conflict'
if bbox . "$root" >/dev/null 2>&1; then fail 'extra directory'; fi
pass 'more than one directory is rejected'

MOCK_POLICY=builtin
warning=$(bbox "$root" 2>&1) || fail 'reuse mismatch should continue'
[[ "$warning" == *'requested seccomp=unconfined'* && "$warning" == *'bbox --rebuild'* ]] || fail 'reuse mismatch message'
pass 'reuse mismatch warns and continues'

if bbox --rebuild "$root" >/dev/null 2>&1; then fail 'recreation mismatch should fail'; fi
pass 'recreation mismatch fails validation'
MOCK_POLICY=inspect-fail
if bbox --rebuild "$root" >/dev/null 2>&1; then fail 'recreation inspection failure should fail'; fi
pass 'recreation inspection failure fails validation'
MOCK_POLICY=custom
warning=$(bbox "$root" 2>&1) || fail 'custom reuse should continue'
[[ "$warning" == *'unverified (seccomp=/tmp/custom.json)'* ]] || fail 'custom policy warning'
pass 'custom policy is unverified'

MOCK_POLICY=unconfined
: >$log
bbox --shell "$root" >/dev/null
grep -q "|exec --workspace-folder $root" $log || fail 'shell attachment'
pass 'shell attachment follows the shared bring-up'
: >$log
bbox --code "$root" >/dev/null
grep -q '^code|--new-window --folder-uri ' $log || fail 'code attachment'
pass 'editor attachment follows the shared bring-up'

MOCK_CONTAINERS='old-1 old-2'
: >$log
bbox --rebuild "$root" >/dev/null
grep -q 'docker|rm -f old-1' $log && grep -q 'docker|rm -f old-2' $log || fail 'rebuild removes every labeled container'
pass 'rebuild removes every container labeled for the folder'
MOCK_VSCODE=1
: >$log
if err=$(bbox --rebuild "$root" 2>&1); then fail 'rebuild with VS Code attached should fail'; fi
[[ "$err" == *'VS Code is attached'* ]] || fail 'VS Code attached message'
grep -q 'docker|rm -f' $log && fail 'must not remove containers while VS Code is attached'
grep -q '|up --workspace-folder' $log && fail 'must not run devcontainer up while VS Code is attached'
pass 'rebuild refuses while VS Code is attached'
MOCK_VSCODE=0 MOCK_CONTAINERS=''

grep -q "'(\-\-rebuild-without-cache)--rebuild" "$root/.host/_bbox" || fail 'completion rebuild exclusion'
grep -q "'(\-\-code)--shell" "$root/.host/_bbox" || fail 'completion action exclusion'
pass 'completion encodes both mutual-exclusion pairs'
print -r -- "1..$tests"
