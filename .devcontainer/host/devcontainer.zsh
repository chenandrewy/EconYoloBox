# devcontainer.zsh — create, verify, and enter this repo's dev containers.
#
# Source from an interactive host zsh:
#   source /path/to/EconYoloBox/.devcontainer/host/devcontainer.zsh
#
# Inputs:  --yolo (the default) or --normie, and an optional project directory.
# Outputs: ybox plus the ybe/ybcode wrappers, which take the same flags
#   (ybcode --normie, ybe --yolo). Requires docker, devcontainer, python3, and
#   (for --code) code.
#
# Each mode is its own container, built from its own config file:
#   YOLO    .devcontainer/devcontainer.json
#   normie  .devcontainer/normie/devcontainer.json
# The Dev Containers tooling keys a container on its folder and config file, so
# the two coexist, the flag only picks which one to bring up, and neither ever
# replaces the other (docs/journal/0927a).

# zsh sets $0 to the sourced file while evaluating it. Resolve siblings now so
# another checkout sourced later cannot redirect this toolkit's helpers.
_DC_HOST_DIR="${0:A:h}"
_DC_RESOLVE_PY="$_DC_HOST_DIR/dc-resolve.py"

# Remove old names and aliases before defining functions, including on reload.
unalias dcu dce dccode bbox bbcode bbu bbe ybox ybe ybcode 2>/dev/null || true
unfunction dcu dce dccode bbox bbcode _bbox _bbcode bbu bbe 2>/dev/null || true
if (( $+functions[compdef] )); then
  compdef -d bbox bbcode bbu bbe
fi

# _dc_resolve [project_dir]
# Prints the enclosing yolobox root and the project's path relative to it
# ("." for the root itself: an empty last line would not survive $(...)).
_dc_resolve() {
  local project_dir devcontainer_dir

  project_dir="${1:-.}"
  project_dir="${project_dir:A}"
  devcontainer_dir="$project_dir"
  while [[ "$devcontainer_dir" != "/" && ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; do
    devcontainer_dir="${devcontainer_dir:h}"
  done
  if [[ ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; then
    echo "ybox: no enclosing .devcontainer/devcontainer.json found for $project_dir" >&2
    return 1
  fi

  print -r -- "$devcontainer_dir"
  if [[ "$project_dir" == "$devcontainer_dir" ]]; then
    print -r -- .
  else
    print -r -- "${project_dir#$devcontainer_dir/}"
  fi
}

# _ybox_config <root> <yolo|normie>
# Prints the mode's config file.
_ybox_config() {
  case "$2" in
    normie) print -r -- "$1/.devcontainer/normie/devcontainer.json" ;;
    *) print -r -- "$1/.devcontainer/devcontainer.json" ;;
  esac
}

# _ybox_containers <root> <config>
# Prints the ids of the folder's containers built from that config. Docker
# ANDs label filters. Containers with any other config label are not ybox's.
_ybox_containers() {
  docker ps -aq --no-trunc --filter "label=devcontainer.local_folder=$1" --filter "label=devcontainer.config_file=$2"
}

# _ybox_posture <container>
# Prints the container's posture as dc-resolve.py's posture command reports
# it: yolo, normie or custom, then the three settings, as Docker created them.
_ybox_posture() {
  local inspected
  if ! inspected=$(docker inspect "$1"); then
    print -r -- 'custom internet=unverified packages=unverified seccomp=unverified (docker inspect failed)'
    return 0
  fi
  print -r -- "$inspected" | python3 "$_DC_RESOLVE_PY" posture ||
    print -r -- 'custom internet=unverified packages=unverified seccomp=unverified (inspection output could not be parsed)'
}

# _ybox_mode_name <yolo|normie|custom>
_ybox_mode_name() {
  case "$1" in
    yolo) print -r -- 'YOLO mode' ;;
    normie) print -r -- 'normie mode' ;;
    *) print -r -- 'a custom posture' ;;
  esac
}

# _ybox_rebuild_hint <yolo|normie> <root>
# Prints the command that recreates that mode's container.
_ybox_rebuild_hint() {
  if [[ "$1" == normie ]]; then
    print -r -- "ybox --rebuild --normie ${(q)2}"
  else
    print -r -- "ybox --rebuild ${(q)2}"
  fi
}

# _ybox_verify_layout <root> <expected-folder> <container>...
# A reused container mounts the yolobox wherever its config said when it was
# created. If workspaceFolder has since moved (for example /sandbox to
# /yolobox), devcontainer up would start it and then fail postStartCommand
# with an opaque "chdir to cwd ... no such file or directory". Catch that
# first: a stale mount target cannot be worked around, so it is an error, and
# only a rebuild fixes it. An inspect failure is left for devcontainer up to
# report.
_ybox_verify_layout() {
  local root="$1" expected="$2" container actual
  shift 2
  for container in "$@"; do
    [[ -n "$container" ]] || continue
    actual=$(docker inspect --format '{{.Config.WorkingDir}}' "$container" 2>/dev/null) || continue
    [[ "$actual" == "$expected" ]] && continue
    print -u2 -- "ybox: ERROR: existing container $container mounts the yolobox at $actual, but its config now expects $expected."
    print -u2 -- "ybox: it predates a layout change and cannot start; on the host run: ybox --rebuild ${(q)root}"
    return 1
  done
  return 0
}

# _ybox_vscode_attached <container>
# True when a VS Code window is connected. The in-container server lingers
# after the window closes, so test for an established TCP connection owned by
# the server process rather than for the process itself.
_ybox_vscode_attached() {
  docker exec "$1" sh -c '
    pids=$(pgrep -f "vscode-server/.*/server-main.js" | paste -sd "|" -)
    [ -n "$pids" ] || exit 1
    ss -Htnp state established 2>/dev/null | grep -qE "pid=($pids),"
  ' >/dev/null 2>&1
}

# _ybox_refuse_attached <root> <config>...
# On rebuild, refuse while VS Code is attached to any container of those
# configs, before anything is removed, so a refusal leaves both modes as they
# were.
_ybox_refuse_attached() {
  local root="$1" config container listed
  shift
  for config in "$@"; do
    listed=$(_ybox_containers "$root" "$config") || return 1
    for container in ${(f)listed}; do
      [[ -n "$container" ]] || continue
      if _ybox_vscode_attached "$container"; then
        print -u2 -- "ybox: ERROR: VS Code is attached to container ${container:0:12} for $root."
        print -u2 -- 'ybox: close that VS Code window (or Dev Containers: Close Remote Connection), then rerun the rebuild.'
        return 1
      fi
    done
  done
}

# _ybox_clear_containers <root> <config>
# Remove every container of that config, so no duplicate survives
# --remove-existing-container. An extension that recreates in the meantime
# uses the same config, so at worst it makes a duplicate of the same mode,
# which _ybox_check_duplicates removes.
_ybox_clear_containers() {
  local root="$1" config="$2" container listed

  listed=$(_ybox_containers "$root" "$config") || return 1
  for container in ${(f)listed}; do
    [[ -n "$container" ]] || continue
    docker rm -f "$container" >/dev/null || return 1
  done
}

# _ybox_check_duplicates <root> <config> <container_id> <rebuild>
# The clear before up is not enough: a container can appear for the mode while
# up runs (a rebuild without cache takes minutes). On rebuild, every other one
# predates the new image, so remove it. Otherwise refuse, since the other one
# may be in use.
_ybox_check_duplicates() {
  local root="$1" config="$2" keep="$3" rebuild="$4" listed container
  local -a others

  listed=$(_ybox_containers "$root" "$config") || return 1
  for container in ${(f)listed}; do
    [[ -n "$container" && "$container" != "$keep" ]] && others+=("$container")
  done
  (( ${#others} )) || return 0
  if (( rebuild )); then
    for container in "${others[@]}"; do
      print -u2 -- "ybox: removing stray container ${container:0:12} for $root (started during the rebuild)"
      docker rm -f "$container" >/dev/null || return 1
    done
    return 0
  fi
  print -u2 -- "ybox: ERROR: more than one container for $root from ${config#$root/}; ybox is using ${keep:0:12}."
  print -u2 -- 'ybox: remove the others with docker rm -f <id>, or rebuild this mode with ybox --rebuild:'
  for container in "${others[@]}"; do
    print -u2 -- "  ${container:0:12}"
  done
  return 1
}

# _ybox_note_normie <root>
# After a YOLO bring-up, mention a running normie container: its firewall is
# open, and nothing stops it but the user. A note, not a question.
_ybox_note_normie() {
  local root="$1" container listed
  listed=$(_ybox_containers "$root" "$(_ybox_config "$root" normie)") || return 0
  for container in ${(f)listed}; do
    [[ -n "$container" ]] || continue
    [[ "$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)" == running ]] || continue
    print -- "ybox: note: normie container ${container:0:12} is also running, firewall open; ybox --stop --normie"
  done
}

# _ybox_up <root> <yolo|normie> <rebuild> [devcontainer up options...]
# Brings up the mode's container, handles duplicates, refuses one not in its
# config's posture, and reports it. Sets REPLY to the container id.
_ybox_up() {
  local root="$1" mode="$2" rebuild="$3" config up_output container_id actual
  shift 3
  config=$(_ybox_config "$root" "$mode")
  up_output=$(devcontainer up --workspace-folder "$root" --config "$config" "$@") || return 1
  container_id=$(print -r -- "$up_output" | python3 "$_DC_RESOLVE_PY" up-container-id) || return 1
  _ybox_check_duplicates "$root" "$config" "$container_id" "$rebuild" || return 1
  # The config fixes the posture, so a mismatch means a container from before
  # the two configs (docs/journal/0927a) or a hand-edited config.
  actual=$(_ybox_posture "$container_id")
  if [[ "${actual%% *}" != "$mode" ]]; then
    print -u2 -- "ybox: ERROR: expected $(_ybox_mode_name "$mode"), but container ${container_id:0:12} has ${actual#* }."
    print -u2 -- "ybox: refusing attachment; on the host run: $(_ybox_rebuild_hint "$mode" "$root")"
    return 1
  fi
  print -- "ybox: $(_ybox_mode_name "$mode") container ${container_id:0:12} (${actual#* })"
  REPLY=$container_id
}

# _ybox_rebuild_other <root> <yolo|normie> [devcontainer up options...]
# The two configs are twins, so a change that needs one mode rebuilt needs
# both. Recreate the other mode's container too, if it has one, and stop it
# again unless it was running: a rebuild must not leave an idle normie
# container running with its firewall open.
_ybox_rebuild_other() {
  local root="$1" mode="$2" other config listed container running=0
  shift 2
  [[ "$mode" == yolo ]] && other=normie || other=yolo
  config=$(_ybox_config "$root" "$other")
  listed=$(_ybox_containers "$root" "$config") || return 1
  [[ -n "$listed" ]] || return 0
  for container in ${(f)listed}; do
    [[ "$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)" == running ]] && running=1
  done
  _ybox_clear_containers "$root" "$config" || return 1
  print -- "ybox: recreating the $(_ybox_mode_name "$other") container for $root"
  _ybox_up "$root" "$other" 1 "$@" || return 1
  if (( ! running )); then
    docker stop "$REPLY" >/dev/null || return 1
    print -- "ybox: stopped the $(_ybox_mode_name "$other") container ${REPLY:0:12} again, as it was not running"
  fi
}

# ybox [--yolo|--normie] [--rebuild|--rebuild-without-cache] [--shell|--code] [DIRECTORY]
# ybox [--yolo|--normie] --stop [DIRECTORY]
# ybox --status [DIRECTORY]
#
# The flag picks the mode's container; no flag means YOLO:
#   --yolo (the default)  internet=firewalled packages=readonly seccomp=builtin
#   --normie              internet=open packages=writable seccomp=unconfined
# Both containers can exist and run at once. --rebuild recreates both modes'
# containers (the other only if it exists) and then attaches to the chosen
# one; --stop acts on the chosen mode's container only; --status reports both.
ybox() {
  local action='' mode='' project_dir='.' rebuild=0 positional_seen=0 arg resolved root relative_dir
  local config remote_path existing listed container actual state container_id docker_context folder_uri m REPLY
  local -a up_args

  while (( $# )); do
    arg="$1"
    shift
    case "$arg" in
      --yolo|--normie)
        [[ -n "$mode" ]] && { print -u2 -- 'ybox: --yolo and --normie are mutually exclusive'; return 2; }
        mode="${arg#--}"
        ;;
      --rebuild)
        (( rebuild )) && { print -u2 -- 'ybox: rebuild flags are mutually exclusive'; return 2; }
        rebuild=1
        up_args+=(--remove-existing-container)
        ;;
      --rebuild-without-cache)
        (( rebuild )) && { print -u2 -- 'ybox: rebuild flags are mutually exclusive'; return 2; }
        rebuild=1
        up_args+=(--remove-existing-container --build-no-cache)
        ;;
      --shell|--code|--status|--stop)
        [[ -n "$action" ]] && { print -u2 -- 'ybox: --shell, --code, --status and --stop are mutually exclusive'; return 2; }
        action="${arg#--}"
        ;;
      --)
        (( $# > 1 )) && { print -u2 -- 'ybox: expected at most one directory'; return 2; }
        if (( $# == 1 )); then
          (( positional_seen )) && { print -u2 -- 'ybox: expected at most one directory'; return 2; }
          project_dir="$1"
        fi
        break
        ;;
      -*)
        print -u2 -- "ybox: unknown option: $arg"
        return 2
        ;;
      *)
        (( positional_seen )) && { print -u2 -- 'ybox: expected at most one directory'; return 2; }
        project_dir="$arg"
        positional_seen=1
        ;;
    esac
  done
  if [[ "$action" == status ]] && { (( rebuild )) || [[ -n "$mode" ]]; }; then
    print -u2 -- 'ybox: --status reports both modes; it takes no other option'
    return 2
  fi
  if [[ "$action" == stop ]] && (( rebuild )); then
    print -u2 -- 'ybox: --stop takes only a mode flag'
    return 2
  fi

  resolved=$(_dc_resolve "$project_dir") || return 1
  root="${resolved%%$'\n'*}"
  relative_dir="${resolved#*$'\n'}"
  [[ "$relative_dir" == . ]] && relative_dir=''

  if [[ "$action" == status ]]; then
    for m in yolo normie; do
      config=$(_ybox_config "$root" "$m")
      listed=$(_ybox_containers "$root" "$config") || return 1
      if [[ -z "$listed" ]]; then
        print -- "ybox: $m: no container"
        continue
      fi
      for container in ${(f)listed}; do
        state=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || print unknown)
        actual=$(_ybox_posture "$container")
        print -- "ybox: $m: ${container:0:12} ($state) ${actual#* }"
        [[ "${actual%% *}" == "$m" ]] ||
          print -- "ybox:   WARNING: that is $(_ybox_mode_name "${actual%% *}"), not $(_ybox_mode_name "$m"); fix: $(_ybox_rebuild_hint "$m" "$root")"
      done
    done
    return 0
  fi

  [[ -n "$mode" ]] || mode=yolo
  config=$(_ybox_config "$root" "$mode")
  if [[ ! -f "$config" ]]; then
    print -u2 -- "ybox: no config for $(_ybox_mode_name "$mode") at $config"
    return 1
  fi

  if [[ "$action" == stop ]]; then
    listed=$(_ybox_containers "$root" "$config") || return 1
    if [[ -z "$listed" ]]; then
      print -- "ybox: $root has no $(_ybox_mode_name "$mode") container"
      return 0
    fi
    for container in ${(f)listed}; do
      docker stop "$container" >/dev/null || return 1
      print -- "ybox: stopped the $(_ybox_mode_name "$mode") container ${container:0:12}"
    done
    return 0
  fi

  remote_path=$(python3 "$_DC_RESOLVE_PY" remote-path "$config" "$relative_dir") || return 1
  existing=$(_ybox_containers "$root" "$config") || return 1
  if (( rebuild )); then
    _ybox_refuse_attached "$root" "$(_ybox_config "$root" yolo)" "$(_ybox_config "$root" normie)" || return 1
    _ybox_rebuild_other "$root" "$mode" "${up_args[@]}" || return 1
    _ybox_clear_containers "$root" "$config" || return 1
    print -- "ybox: recreating the $(_ybox_mode_name "$mode") container for $root"
  elif [[ -n "$existing" ]]; then
    _ybox_verify_layout "$root" "$(python3 "$_DC_RESOLVE_PY" remote-path "$config" "")" ${(f)existing} || return 1
  fi

  _ybox_up "$root" "$mode" "$rebuild" "${up_args[@]}" || return 1
  container_id=$REPLY
  [[ "$mode" == yolo ]] && _ybox_note_normie "$root"

  case "$action" in
    shell)
      devcontainer exec --workspace-folder "$root" --config "$config" zsh -c "cd ${(q)remote_path} && exec zsh"
      ;;
    code)
      docker_context=$(docker context show) || return 1
      folder_uri=$(python3 "$_DC_RESOLVE_PY" folder-uri "$root" "$config" "$remote_path" "$docker_context") || return 1
      code --new-window --folder-uri "$folder_uri"
      ;;
  esac
}

# Short names. All creation and resolution stays in ybox.
ybe() { ybox --shell "$@"; }
ybcode() { ybox --code "$@"; }

# Completion initialization belongs to the user's zsh setup.
source "$_DC_HOST_DIR/_ybox"
source "$_DC_HOST_DIR/_ybcode"
