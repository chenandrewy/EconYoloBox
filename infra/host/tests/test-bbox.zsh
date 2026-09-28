#!/usr/bin/env zsh
# Run:     zsh infra/host/tests/test-bbox.zsh
# Inputs:  host bbox implementation; mocks Docker, Dev Containers, and VS Code.
# Outputs: TAP-like pass/fail lines and a nonzero status on failure.
setopt errexit nounset pipefail

root=${0:A:h:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log=$tmp/calls
yolo_config=$root/.devcontainer/devcontainer.json
normie_config=$root/.devcontainer/normie/devcontainer.json
# The mock daemon keeps one file per container, because bbox calls docker and
# devcontainer inside command substitutions, where variables do not survive:
#   $tmp/containers/<id>: "<config> <internet> <packages-rw> <seccomp> <state>"
store=$tmp/containers
mkdir -p $store
typeset -g MOCK_VSCODE=0 MOCK_WORKDIR=/yolobox MOCK_UP_POSTURE='' MOCK_UP_STRAY=0

# add_container <id> <config> <yolo|normie> [state]
add_container() {
  local posture
  case "$3" in
    yolo) posture='firewalled false builtin' ;;
    normie) posture='open true unconfined' ;;
  esac
  print -r -- "$2 $posture ${4:-running}" >$store/$1
}
reset_store() { rm -f $store/*(N); }
field() { local -a f; f=(${=$(<$store/$1)}); print -r -- ${f[$2]}; }

alias dcu='devcontainer up --workspace-folder .'
dccode() { :; }
source "$root/infra/host/devcontainer.zsh"

devcontainer() {
  print -r -- "devcontainer|$*" >>$log
  local sub=$1 config='' remove=0 id posture n
  shift
  while (( $# )); do
    case "$1" in
      --config) config=$2; shift ;;
      --remove-existing-container) remove=1 ;;
    esac
    shift
  done
  [[ "$sub" == up ]] || return 0
  for id in $store/*(N:t); do
    [[ "$(field $id 1)" == "$config" ]] || continue
    if (( remove )); then rm -f $store/$id; else
      print -r -- "{\"outcome\":\"success\",\"containerId\":\"$id\"}"; return 0
    fi
  done
  # Docker creates the posture the config hard-codes, unless a test says not.
  if [[ -n "$MOCK_UP_POSTURE" ]]; then posture=$MOCK_UP_POSTURE
  elif [[ "$config" == */normie/* ]]; then posture=normie
  else posture=yolo
  fi
  n=$(( $(ls $store | wc -l) + 1 ))
  id=${posture}-new-$n-0123456789abcdef
  add_container $id "$config" $posture
  (( MOCK_UP_STRAY )) && add_container stray-$n-0123456789abcdef "$config" $posture
  print -r -- "{\"outcome\":\"success\",\"containerId\":\"$id\"}"
}
docker() {
  print -r -- "docker|$*" >>$log
  local id folder='' config='' arg
  case "$1" in
    ps)
      for arg in "$@"; do
        case "$arg" in
          label=devcontainer.local_folder=*) folder=${arg#*=*=} ;;
          label=devcontainer.config_file=*) config=${arg#*=*=} ;;
        esac
      done
      [[ "$folder" == "$root" ]] || return 0
      for id in $store/*(N:t); do
        [[ -z "$config" || "$(field $id 1)" == "$config" ]] && print -r -- $id
      done
      return 0
      ;;
    inspect)
      if [[ "$2" == --format ]]; then
        id=$4
        [[ -f $store/$id ]] || return 1
        case "$3" in
          *WorkingDir*) print -r -- "$MOCK_WORKDIR" ;;
          *State.Status*) field $id 5 ;;
        esac
        return 0
      fi
      id=$2
      [[ -f $store/$id ]] || return 1
      print -r -- "[{\"Config\":{\"Env\":[\"YOLOBOX_INTERNET=$(field $id 2)\"]},\"HostConfig\":{\"SecurityOpt\":[\"seccomp=$(field $id 4)\"]},\"Mounts\":[{\"Destination\":\"/opt/venv\",\"RW\":$(field $id 3)},{\"Destination\":\"/opt/R/4.5.3/lib/R/site-library\",\"RW\":$(field $id 3)},{\"Destination\":\"/usr/local/texlive\",\"RW\":$(field $id 3)}]}]"
      ;;
    rm) rm -f $store/$3 ;;
    stop)
      local -a f
      f=(${=$(<$store/$2)})
      print -r -- "${f[1,4]} exited" >$store/$2
      ;;
    exec) (( MOCK_VSCODE )) && return 0; return 1 ;;
    context) print -r -- desktop-linux ;;
  esac
}
code() { print -r -- "code|$*" >>$log; }

fail() { print -r -- "not ok - $1"; exit 1; }
typeset -gi tests=0
pass() { (( ++tests )); print -r -- "ok $tests - $1"; }
run() { : >$log; bbox "$@" </dev/null; }
count() { ls $store | grep -c -- "$1" || true; }

(( ! $+aliases[dcu] )) || fail 'legacy dcu alias survived reload'
(( ! $+functions[dccode] )) || fail 'legacy dccode function survived reload'
(( $+functions[bbu] && $+functions[bbe] && $+functions[bbcode] )) || fail 'short wrappers missing after reload'
pass 'reload removes legacy dcu/dce/dccode names and defines bbu/bbe/bbcode'

# Each mode brings up its own config's container.
out=$(run --code "$root") || fail 'bbcode'
grep -qF "devcontainer|up --workspace-folder $root --config $yolo_config" $log || fail 'no flag must use the YOLO config'
[[ "$out" == *'YOLO mode container yolo-new-1'* ]] || fail 'YOLO report'
expected_uri=$(python3 "$root/infra/host/dc-resolve.py" folder-uri "$root" "$yolo_config" /yolobox desktop-linux)
grep -qF "code|--new-window --folder-uri $expected_uri" $log || fail 'VS Code must open the YOLO config'
pass 'no flag brings up the YOLO config and opens it in VS Code'
out=$(run --code --normie "$root") || fail 'bbcode --normie'
grep -qF "devcontainer|up --workspace-folder $root --config $normie_config" $log || fail '--normie must use the normie config'
grep -q -- '--remove-existing-container' $log && fail 'a second mode must not recreate anything'
grep -q 'docker|rm' $log && fail 'a second mode must not remove anything'
(( $(count yolo-new) == 1 && $(count normie-new) == 1 )) || fail 'both containers must exist'
expected_uri=$(python3 "$root/infra/host/dc-resolve.py" folder-uri "$root" "$normie_config" /yolobox desktop-linux)
grep -qF "code|--new-window --folder-uri $expected_uri" $log || fail 'VS Code must open the normie config'
[[ "$out" == *'normie mode container normie-new-2'* ]] || fail 'normie report'
pass '--normie brings up a second container beside the YOLO one'

out=$(run --status "$root") || fail 'status'
[[ "$out" == *'yolo: yolo-new-1-0 (running) internet=firewalled'* && "$out" == *'normie: normie-new-2 (running) internet=open'* ]] || fail 'status lists both'
grep -q 'devcontainer|' $log && fail 'status must not run devcontainer'
pass '--status reports both modes and changes nothing'

out=$(run "$root") || fail 'YOLO reuse'
grep -q -- '--remove-existing-container' $log && fail 'reuse must not recreate'
[[ "$out" == *'note: normie container normie-new-2 is also running, firewall open; bbox --stop --normie'* ]] || fail 'normie note'
pass 'a YOLO bring-up reuses its container and notes the running normie one'
out=$(run --normie "$root") || fail 'normie reuse'
[[ "$out" == *note:* ]] && fail 'a normie bring-up has no note'
pass 'a normie bring-up reuses its container'

run --shell --normie "$root/workspace" >/dev/null || fail 'bbe --normie'
grep -qF "devcontainer|exec --workspace-folder $root --config $normie_config zsh -c cd /yolobox/workspace && exec zsh" $log || fail 'shell must exec into the normie container'
run --shell --yolo "$root" >/dev/null || fail 'bbe --yolo'
grep -qF "devcontainer|exec --workspace-folder $root --config $yolo_config" $log || fail 'shell must exec into the YOLO container'
: >$log; bbe --normie "$root" </dev/null >/dev/null || fail 'bbe wrapper'
grep -qF -- "--config $normie_config" $log || fail 'bbe passes --normie through'
pass 'bbe and --shell exec into the chosen mode'"'"'s container'

out=$(run --stop --normie "$root") || fail 'stop'
[[ "$out" == *'stopped the normie mode container normie-new-2'* ]] || fail 'stop message'
[[ "$(field normie-new-2-0123456789abcdef 5)" == exited ]] || fail 'normie must be stopped'
[[ "$(field yolo-new-1-0123456789abcdef 5)" == running ]] || fail 'YOLO must keep running'
out=$(run "$root") || fail 'YOLO after stop'
[[ "$out" == *note:* ]] && fail 'no note once normie is stopped'
out=$(run --stop "$root") || fail 'stop YOLO'
[[ "$(field yolo-new-1-0123456789abcdef 5)" == exited ]] || fail 'no flag stops YOLO'
pass '--stop stops only the chosen mode'"'"'s container'

# Rebuild recreates both modes' containers and attaches to the chosen one.
reset_store
add_container yolo-a "$yolo_config" yolo
add_container normie-a "$normie_config" normie
out=$(run --rebuild --normie --code "$root") || fail 'normie rebuild'
grep -q 'docker|rm -f normie-a' $log || fail 'rebuild removes the normie container'
grep -q 'docker|rm -f yolo-a' $log || fail 'rebuild removes the YOLO container too'
grep -qF -- "--config $yolo_config --remove-existing-container" $log || fail 'YOLO rebuild flag'
grep -qF -- "--config $normie_config --remove-existing-container" $log || fail 'normie rebuild flag'
(( $(count yolo-new) == 1 && $(count normie-new) == 1 && $(count -a) == 0 )) || fail 'both containers must be new'
yolo_new=($store/yolo-new-*(N:t))
(( $#yolo_new == 1 )) && [[ "$(field $yolo_new[1] 5)" == running ]] || fail 'a running YOLO container stays running'
grep -q 'docker|stop' $log && fail 'nothing that was running is stopped'
expected_uri=$(python3 "$root/infra/host/dc-resolve.py" folder-uri "$root" "$normie_config" /yolobox desktop-linux)
grep -qF "code|--new-window --folder-uri $expected_uri" $log || fail 'the rebuild opens the chosen mode'
[[ "$(grep -c '^code|' $log)" == 1 ]] || fail 'only the chosen mode is opened'
[[ "$out" == *'recreating the YOLO mode container'*'recreating the normie mode container'* ]] || fail 'the chosen mode comes last'
pass '--rebuild --normie recreates both containers and opens the normie one'

reset_store
add_container yolo-a "$yolo_config" yolo
add_container normie-a "$normie_config" normie exited
out=$(run --rebuild-without-cache "$root") || fail 'no-cache rebuild'
grep -qF -- "--config $yolo_config --remove-existing-container --build-no-cache" $log || fail 'YOLO no-cache flags'
grep -qF -- "--config $normie_config --remove-existing-container --build-no-cache" $log || fail 'normie no-cache flags'
normie_new=($store/normie-new-*(N:t))
(( $#normie_new == 1 )) && [[ "$(field $normie_new[1] 5)" == exited ]] || fail 'a stopped normie container is stopped again'
[[ "$out" == *'stopped the normie mode container'*'as it was not running'* ]] || fail 'stop-again message'
[[ "$out" == *'also running'* ]] && fail 'no running-normie note after the rebuild'
pass '--rebuild-without-cache recreates both, leaving a stopped container stopped'

reset_store
add_container yolo-a "$yolo_config" yolo
run --rebuild "$root" >/dev/null || fail 'YOLO-only rebuild'
(( $(count normie) == 0 )) || fail 'a rebuild must not create a missing mode'
grep -qF -- "--config $normie_config" $log && fail 'no normie up without a normie container'
pass 'a rebuild does not create the other mode when it has no container'

reset_store
add_container yolo-a "$yolo_config" yolo
add_container normie-a "$normie_config" normie
MOCK_VSCODE=1
if err=$(run --rebuild "$root" 2>&1); then fail 'rebuild with VS Code attached should fail'; fi
[[ "$err" == *'VS Code is attached'* ]] || fail 'VS Code attached message'
grep -q 'docker|rm' $log && fail 'must not remove while VS Code is attached'
grep -q 'devcontainer|up' $log && fail 'must not run up while VS Code is attached'
pass 'a rebuild refuses while VS Code is attached, before removing either mode'
MOCK_VSCODE=0

# Duplicates of one mode.
reset_store
add_container yolo-a "$yolo_config" yolo
add_container yolo-b "$yolo_config" yolo
if err=$(run "$root" 2>&1); then fail 'two YOLO containers should fail'; fi
[[ "$err" == *'more than one container'* && "$err" == *'yolo-b'* ]] || fail 'duplicate message'
pass 'two containers for one mode are refused'
reset_store
MOCK_UP_STRAY=1
run --rebuild "$root" >/dev/null 2>&1 || fail 'rebuild with a stray'
(( $(count stray) == 0 )) || fail 'a stray from the rebuild must be removed'
MOCK_UP_STRAY=0
pass 'a stray appearing during a rebuild is removed'

# A container whose posture does not match its config, like the ones made
# before the per-mode configs, which all carry the YOLO config label.
reset_store
add_container legacy "$yolo_config" normie
if err=$(run "$root" 2>&1); then fail 'a mismatched container should be refused'; fi
[[ "$err" == *'expected YOLO mode'* && "$err" == *"bbox --rebuild $root"* ]] || fail 'mismatch message'
out=$(run --status "$root")
[[ "$out" == *'WARNING: that is normie mode, not YOLO mode'* ]] || fail 'status flags the mismatch'
reset_store
MOCK_UP_POSTURE=yolo
if err=$(run --normie "$root" 2>&1); then fail 'a wrong posture after up should fail'; fi
[[ "$err" == *'expected normie mode'* && "$err" == *"bbox --rebuild --normie $root"* ]] || fail 'normie mismatch hint'
MOCK_UP_POSTURE=''
pass 'a container not in its config'"'"'s posture is refused with the right rebuild'

# Containers with another config label are not bbox's.
reset_store
add_container other /elsewhere/devcontainer.json yolo
run --rebuild "$root" >/dev/null || fail 'rebuild beside a foreign container'
[[ -f $store/other ]] || fail 'a foreign container must be left alone'
out=$(run --status "$root")
[[ "$out" == *other* ]] && fail 'a foreign container is not listed'
pass 'containers from other configs are left alone and not listed'

# Layout.
reset_store
add_container yolo-a "$yolo_config" yolo
MOCK_WORKDIR=/sandbox
if err=$(run "$root" 2>&1); then fail 'stale mount target should fail'; fi
[[ "$err" == *'mounts the sandbox at /sandbox'* && "$err" == *'expects /yolobox'* ]] || fail 'stale mount message'
grep -q 'devcontainer|up' $log && fail 'stale mount target must be caught before up'
run --rebuild "$root" >/dev/null || fail 'rebuild should bypass the layout check'
MOCK_WORKDIR=/yolobox
pass 'a stale mount target fails before up; rebuild skips the check'

# Option errors.
for args in '--rebuild --rebuild-without-cache' '--shell --code' '--yolo --normie' '--status --shell' '--status --normie' '--status --rebuild' '--stop --rebuild' '--stop --code' ". $root"; do
  if run ${=args} "$root" >/dev/null 2>&1; then fail "accepted: $args"; fi
done
pass 'conflicting options and a second directory are rejected'

grep -q "'(\-\-rebuild-without-cache --status --stop)--rebuild" "$root/infra/host/_bbox" || fail 'completion rebuild exclusion'
grep -q "'(\-\-normie --status)--yolo" "$root/infra/host/_bbox" || fail 'completion mode exclusion'
grep -q "'(\-\-shell --code --status --rebuild --rebuild-without-cache)--stop" "$root/infra/host/_bbox" || fail 'completion stop exclusion'
pass 'completion encodes the mutual exclusions'
print -r -- "1..$tests"
