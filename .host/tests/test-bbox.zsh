#!/usr/bin/env zsh
# Run:     zsh .host/tests/test-bbox.zsh
# Inputs:  host bbox implementation; mocks Docker, Dev Containers, and VS Code.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
setopt errexit nounset pipefail

root=${0:A:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log=$tmp/calls
# The mocked container's posture lives in a file, not a variable: bbox calls
# docker and devcontainer inside command substitutions, so only a file lets
# the mocked `up` "create" a container that later inspections see.
state=$tmp/posture
# Containers already labeled for the folder; container-123 is what the mocked
# `up` returns, so listing it makes bbox treat the container as reused.
typeset -g MOCK_CONTAINERS='container-123' MOCK_VSCODE=0 MOCK_WORKDIR=/sandbox MOCK_UP_BROKEN=0

# set_posture <yolo|normie|custom|inspect-fail|garbage>
set_posture() {
  case "$1" in
    yolo) print -r -- 'firewalled false builtin' ;;
    normie) print -r -- 'open true unconfined' ;;
    custom) print -r -- 'open false builtin' ;;
    *) print -r -- "$1" ;;
  esac >$state
}

alias dcu='devcontainer up --workspace-folder .'
dccode() { :; }
source "$root/.host/devcontainer.zsh"

devcontainer() {
  print -r -- "internet=${SANDBOX_INTERNET:-} seccomp=${SANDBOX_SECCOMP:-} pkg_readonly=${SANDBOX_PKG_READONLY:-}|$*" >>$log
  if [[ "$1" == up ]]; then
    # Docker applies the posture only when it creates a container.
    if (( ! MOCK_UP_BROKEN )) && [[ -z "$MOCK_CONTAINERS" || "$*" == *--remove-existing-container* ]]; then
      local rw=true
      [[ "$SANDBOX_PKG_READONLY" == true ]] && rw=false
      print -r -- "$SANDBOX_INTERNET $rw $SANDBOX_SECCOMP" >$state
    fi
    print -r -- '{"outcome":"success","containerId":"container-123"}'
  fi
}
docker() {
  print -r -- "docker|$*" >>$log
  if [[ "$1" == inspect && "$*" == *WorkingDir* ]]; then
    print -r -- "$MOCK_WORKDIR"
  elif [[ "$1" == inspect && "$*" == *State.Status* ]]; then
    print -r -- running
  elif [[ "$1" == inspect ]]; then
    local internet rw seccomp
    read -r internet rw seccomp <$state
    case "$internet" in
      inspect-fail) return 1 ;;
      garbage) print -r -- 'not json'; return 0 ;;
    esac
    print -r -- "[{\"Config\":{\"Env\":[\"PATH=/usr/bin\",\"SANDBOX_INTERNET=$internet\"]},\"HostConfig\":{\"SecurityOpt\":[\"seccomp=$seccomp\"]},\"Mounts\":[{\"Destination\":\"/opt/venv\",\"RW\":$rw},{\"Destination\":\"/opt/R/4.5.3/lib/R/site-library\",\"RW\":$rw},{\"Destination\":\"/usr/local/texlive\",\"RW\":$rw},{\"Destination\":\"/sandbox\",\"RW\":true}]}]"
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
# Every bbox call reads stdin from /dev/null: bbox asks only on a terminal.
run() { : >$log; bbox "$@" </dev/null; }

yolo_up="internet=firewalled seccomp=builtin pkg_readonly=true|up --workspace-folder $root"
normie_up="internet=open seccomp=unconfined pkg_readonly=false|up --workspace-folder $root"

(( ! $+aliases[dcu] )) || fail 'legacy dcu alias survived reload'
(( ! $+functions[dccode] )) || fail 'legacy dccode function survived reload'
(( $+functions[bbu] && $+functions[bbe] && $+functions[bbcode] )) || fail 'short wrappers missing after reload'
pass 'reload removes legacy dcu/dce/dccode names and defines bbu/bbe/bbcode'

# Creation.
MOCK_CONTAINERS=''
set_posture yolo
out=$(run "$root") || fail 'creation without a flag'
grep -qF "$yolo_up" $log || fail 'no flag must create in YOLO mode'
grep -q 'docker|inspect container-123' $log || fail 'exact returned container inspection'
[[ "$out" == *'is in YOLO mode (internet=firewalled packages=readonly seccomp=builtin)'* ]] || fail 'mode report after creation'
pass 'no flag creates a YOLO container and reports the mode'
out=$(run --normie "$root") || fail 'creation with --normie'
grep -qF "$normie_up" $log || fail '--normie must export the normie posture'
[[ "$out" == *'is in normie mode'* ]] || fail 'normie report after creation'
pass '--normie creates a normie container'
MOCK_CONTAINERS='container-123'

# Reuse in the same posture.
set_posture yolo
run "$root" >/dev/null || fail 'yolo reuse'
grep -qF "$yolo_up" $log || fail 'yolo reuse up'
grep -q -- '--remove-existing-container' $log && fail 'reuse must not recreate'
grep -q 'docker|rm' $log && fail 'reuse must not remove'
pass 'a YOLO container is reused without a flag'
set_posture normie
run --normie "$root" >/dev/null || fail 'normie reuse'
grep -q -- '--remove-existing-container' $log && fail 'normie reuse must not recreate'
pass 'a normie container is reused with --normie'

# Switching.
set_posture normie
if err=$(run "$root" 2>&1); then fail 'no flag must not silently replace a normie container'; fi
[[ "$err" == *'is in normie mode'* && "$err" == *'add --normie'* && "$err" == *'add --yolo'* ]] || fail 'normie refusal message'
grep -q 'docker|rm' $log && fail 'refusal must not remove the container'
grep -q '|up ' $log && fail 'refusal must not run devcontainer up'
pass 'without a flag or a terminal, a normie container is left alone'
set_posture custom
if err=$(run "$root" 2>&1); then fail 'no flag must not silently replace a custom container'; fi
[[ "$err" == *'a custom posture'* ]] || fail 'custom refusal message'
[[ "$err" == *'add --normie'* ]] && fail 'a custom container cannot be attached with --normie'
pass 'a custom container (made before the flags) is left alone too'
set_posture normie
out=$(run --yolo "$root") || fail '--yolo switch'
grep -q 'docker|rm -f container-123' $log || fail '--yolo switch must clear the old container'
grep -qF "$yolo_up --remove-existing-container" $log || fail '--yolo switch must recreate in YOLO mode'
[[ "$out" == *'switching'*'from normie mode to YOLO mode'* ]] || fail 'switch message'
pass '--yolo recreates a normie container without asking'
set_posture yolo
run --normie "$root" >/dev/null || fail '--normie switch'
grep -qF "$normie_up --remove-existing-container" $log || fail '--normie switch must recreate in normie mode'
pass '--normie recreates a YOLO container'
set_posture inspect-fail
run --yolo "$root" >/dev/null 2>&1 || true
grep -q -- '--remove-existing-container' $log || fail 'an uninspectable container counts as another posture'
pass 'an uninspectable container is recreated on request'
set_posture normie
MOCK_VSCODE=1
if err=$(run --yolo "$root" 2>&1); then fail 'switch with VS Code attached should fail'; fi
[[ "$err" == *'VS Code is attached'* && "$err" == *'add --normie'* ]] || fail 'attached switch message'
grep -q 'docker|rm' $log && fail 'must not remove a container VS Code is attached to'
grep -q '|up ' $log && fail 'must not run up while VS Code is attached'
pass 'a switch refuses while VS Code is attached'
MOCK_VSCODE=0

# Verification after up.
set_posture normie
MOCK_UP_BROKEN=1
if err=$(run --yolo "$root" 2>&1); then fail 'a wrong posture after up should fail'; fi
[[ "$err" == *'ERROR: requested YOLO mode'* && "$err" == *'refusing attachment'* ]] || fail 'post-up mismatch message'
set_posture garbage
if run --rebuild "$root" >/dev/null 2>&1; then fail 'unparseable inspection after up should fail'; fi
pass 'a container not in the requested posture after up is refused'
MOCK_UP_BROKEN=0

# Rebuild.
set_posture yolo
run --rebuild "$root" >/dev/null
grep -qF "$yolo_up --remove-existing-container" $log || fail 'rebuild flag'
pass '--rebuild recreates in YOLO mode with cache'
run --rebuild --normie "$root" >/dev/null
grep -qF "$normie_up --remove-existing-container" $log || fail 'rebuild in normie mode'
pass '--rebuild --normie recreates in normie mode'
run --rebuild-without-cache "$root" >/dev/null
grep -q -- '--remove-existing-container --build-no-cache' $log || fail 'no-cache flags'
pass '--rebuild-without-cache adds both CLI flags'
MOCK_CONTAINERS='old-1 old-2'
run --rebuild "$root" >/dev/null 2>&1
grep -q 'docker|rm -f old-1' $log && grep -q 'docker|rm -f old-2' $log || fail 'rebuild removes every labeled container'
pass 'rebuild removes every container labeled for the folder'
MOCK_VSCODE=1
if err=$(run --rebuild "$root" 2>&1); then fail 'rebuild with VS Code attached should fail'; fi
[[ "$err" == *'VS Code is attached'* ]] || fail 'VS Code attached message'
grep -q 'docker|rm -f' $log && fail 'must not remove containers while VS Code is attached'
grep -q '|up --workspace-folder' $log && fail 'must not run devcontainer up while VS Code is attached'
pass 'rebuild refuses while VS Code is attached'
MOCK_VSCODE=0 MOCK_CONTAINERS='container-123'

# Option errors.
for args in '--rebuild --rebuild-without-cache' '--shell --code' '--yolo --normie' '--status --shell' '--status --normie' '--status --rebuild' ". $root"; do
  if run ${=args} "$root" >/dev/null 2>&1; then fail "conflict accepted: $args"; fi
done
pass 'conflicting options and a second directory are rejected'

# Layout.
set_posture yolo
MOCK_WORKDIR=/workspace
if err=$(run "$root" 2>&1); then fail 'stale mount target should fail'; fi
[[ "$err" == *'mounts the sandbox at /workspace'* && "$err" == *'expects /sandbox'* && "$err" == *'bbox --rebuild'* ]] || fail 'stale mount message'
grep -q '|up ' $log && fail 'stale mount target must be caught before devcontainer up'
pass 'reused container with a stale mount target fails before up'
run --rebuild "$root" >/dev/null || fail 'rebuild should bypass the layout check'
pass 'rebuild skips the layout check'
MOCK_WORKDIR=/sandbox

# Status.
set_posture normie
out=$(run --status "$root") || fail 'status'
[[ "$out" == *'container-12'*'(running) is in normie mode: internet=open packages=writable seccomp=unconfined'* ]] || fail 'status report'
grep -q '|up ' $log && fail 'status must not run devcontainer up'
grep -q 'docker|rm' $log && fail 'status must not remove anything'
MOCK_CONTAINERS=''
out=$(run --status "$root") || fail 'status without a container'
[[ "$out" == *'has no container'* ]] || fail 'status without a container message'
MOCK_CONTAINERS='container-123'
pass '--status reports the posture and changes nothing'

# Attachment and wrappers.
set_posture yolo
run --shell "$root" >/dev/null
grep -q "|exec --workspace-folder $root" $log || fail 'shell attachment'
pass 'shell attachment follows the shared bring-up'
run --code "$root" >/dev/null
grep -q '^code|--new-window --folder-uri ' $log || fail 'code attachment'
pass 'editor attachment follows the shared bring-up'
set_posture normie
: >$log
bbe --normie "$root" </dev/null >/dev/null || fail 'bbe --normie'
grep -q "|exec --workspace-folder $root" $log || fail 'bbe --normie attachment'
: >$log
bbcode --normie "$root" </dev/null >/dev/null || fail 'bbcode --normie'
grep -q '^code|--new-window' $log || fail 'bbcode --normie attachment'
grep -q -- '--remove-existing-container' $log && fail 'wrappers must reuse a matching container'
pass 'bbe and bbcode pass the mode flags through'

grep -q "'(\-\-rebuild-without-cache --status)--rebuild" "$root/.host/_bbox" || fail 'completion rebuild exclusion'
grep -q "'(\-\-code --status)--shell" "$root/.host/_bbox" || fail 'completion action exclusion'
grep -q "'(\-\-normie --status)--yolo" "$root/.host/_bbox" || fail 'completion mode exclusion'
pass 'completion encodes the mutual exclusions'
print -r -- "1..$tests"
