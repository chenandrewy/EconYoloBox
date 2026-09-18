# devcontainer.zsh — create, verify, and enter this repo's dev container.
#
# Source from an interactive host zsh:
#   source /path/to/EconYoloBox/.host/devcontainer.zsh
#
# Inputs:  SANDBOX.toml and an optional project directory.
# Outputs: bbox plus deprecated dcu/dce/dccode wrappers. Requires docker,
#   devcontainer, python3, and (for --code) code.

# zsh sets $0 to the sourced file while evaluating it. Resolve siblings now so
# another checkout sourced later cannot redirect this toolkit's helpers.
_DC_HOST_DIR="${0:A:h}"
_DC_RESOLVE_PY="$_DC_HOST_DIR/dc-resolve.py"

# _dc_resolve [project_dir]
# Prints the enclosing sandbox root and corresponding container path.
_dc_resolve() {
  local project_dir devcontainer_dir devcontainer_json relative_dir remote_path

  project_dir="${1:-.}"
  project_dir="${project_dir:A}"
  devcontainer_dir="$project_dir"
  while [[ "$devcontainer_dir" != "/" && ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; do
    devcontainer_dir="${devcontainer_dir:h}"
  done
  if [[ ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; then
    echo "bbox: no enclosing .devcontainer/devcontainer.json found for $project_dir" >&2
    return 1
  fi

  if [[ "$project_dir" == "$devcontainer_dir" ]]; then
    relative_dir=""
  else
    relative_dir="${project_dir#$devcontainer_dir/}"
  fi
  devcontainer_json="$devcontainer_dir/.devcontainer/devcontainer.json"
  remote_path=$(python3 "$_DC_RESOLVE_PY" remote-path "$devcontainer_json" "$relative_dir") || return 1
  print -r -- "$devcontainer_dir"
  print -r -- "$remote_path"
}

_bbox_verify_policy() {
  local container_id="$1" requested="$2" recreated="$3" root="$4"
  local security_options actual

  if ! security_options=$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "$container_id"); then
    actual='unverified (docker inspect failed)'
  else
    actual=$(python3 "$_DC_RESOLVE_PY" security-policy "$security_options") || actual='unverified (inspection output could not be parsed)'
  fi

  if [[ "$actual" == "$requested" ]]; then
    return 0
  fi
  if (( recreated )); then
    print -u2 -- "bbox: ERROR: recreated container requested seccomp=$requested; actual policy is $actual."
    print -u2 -- 'bbox: refusing attachment because recreation could not be validated.'
    return 1
  fi
  print -u2 -- "bbox: WARNING: requested seccomp=$requested; running container policy is $actual."
  print -u2 -- "bbox: seccomp is fixed at creation; on the host run: bbox --rebuild ${(q)root}"
  return 0
}

# bbox [--rebuild|--rebuild-without-cache] [--shell|--code] [DIRECTORY]
bbox() {
  local action='' project_dir='.' rebuild=0 positional_seen=0 arg resolved root remote_path
  local seccomp up_output container_id docker_context folder_uri
  local -a up_args

  while (( $# )); do
    arg="$1"
    shift
    case "$arg" in
      --rebuild)
        (( rebuild )) && { print -u2 -- 'bbox: rebuild flags are mutually exclusive'; return 2; }
        rebuild=1
        up_args+=(--remove-existing-container)
        ;;
      --rebuild-without-cache)
        (( rebuild )) && { print -u2 -- 'bbox: rebuild flags are mutually exclusive'; return 2; }
        rebuild=1
        up_args+=(--remove-existing-container --build-no-cache)
        ;;
      --shell|--code)
        [[ -n "$action" ]] && { print -u2 -- 'bbox: --shell and --code are mutually exclusive'; return 2; }
        action="${arg#--}"
        ;;
      --)
        (( $# > 1 )) && { print -u2 -- 'bbox: expected at most one directory'; return 2; }
        if (( $# == 1 )); then
          (( positional_seen )) && { print -u2 -- 'bbox: expected at most one directory'; return 2; }
          project_dir="$1"
        fi
        break
        ;;
      -*)
        print -u2 -- "bbox: unknown option: $arg"
        return 2
        ;;
      *)
        (( positional_seen )) && { print -u2 -- 'bbox: expected at most one directory'; return 2; }
        project_dir="$arg"
        positional_seen=1
        ;;
    esac
  done

  resolved=$(_dc_resolve "$project_dir") || return 1
  root="${resolved%%$'\n'*}"
  remote_path="${resolved#*$'\n'}"
  seccomp=$(bash "$root/.devcontainer/seccomp-setting.sh" "$root/SANDBOX.toml") || return 1

  if (( rebuild )); then
    print -- "bbox: recreating $root with seccomp=$seccomp"
  fi
  up_output=$(SANDBOX_SECCOMP="$seccomp" devcontainer up --workspace-folder "$root" "${up_args[@]}") || return 1
  container_id=$(print -r -- "$up_output" | python3 "$_DC_RESOLVE_PY" up-container-id) || return 1
  _bbox_verify_policy "$container_id" "$seccomp" "$rebuild" "$root" || return 1

  case "$action" in
    shell)
      devcontainer exec --workspace-folder "$root" zsh -c "cd ${(q)remote_path} && exec zsh"
      ;;
    code)
      docker_context=$(docker context show) || return 1
      folder_uri=$(python3 "$_DC_RESOLVE_PY" folder-uri "$root" "$remote_path" "$docker_context") || return 1
      code --new-window --folder-uri "$folder_uri"
      ;;
  esac
}

# Deprecated compatibility names. All creation and resolution stays in bbox.
# The previous launcher shipped dcu as an alias. Remove legacy aliases first so
# this file can be sourced again in an already-running host shell.
unalias dcu dce dccode 2>/dev/null || true
dcu() { bbox "$@"; }
dce() { bbox --shell "$@"; }
dccode() { bbox --code "$@"; }

# Completion initialization belongs to the user's zsh setup.
source "$_DC_HOST_DIR/_bbox"
