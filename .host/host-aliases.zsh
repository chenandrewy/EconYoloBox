# host-aliases.zsh — host-side toolkit for the 1-SANDBOX dev container.
#
# Source this from your interactive shell rc (zsh):
#   source /path/to/1-SANDBOX/.host/host-aliases.zsh
# Optionally set target locations as plain shell globals BEFORE sourcing
# (see "Config" below); the sandbox target self-derives from this file's path.
#
# Inputs:  none at load time beyond the optional CC_* globals.
# Outputs: defines host-side aliases/functions in the current shell —
#   cc-remote-{sandbox,obs,dropbox}, ccremotes, ccsessions, cckill,
#   dcu, dce, dccode. Requires: docker, the `devcontainer` CLI, and a terminal
#   launcher (Terminal.app by default; override _cc_open_window for another).

# == Config ==
# Plain shell globals, NOT exported: they are only read inside the functions
# below (and baked literally into the window command), so nothing needs to leak
# into child environments. Override any of them from your own rc before sourcing.
#   CC_SANDBOX_DIR  — defaults to this repo (parent of .host/); no config needed.
#   CC_OBSIDIAN_DIR — the iCloud Obsidian vault to open in a container.
#   CC_DROPBOX_DIR  — Dropbox's real install folder (not a personal symlink).
: "${CC_SANDBOX_DIR:=${0:A:h:h}}"
: "${CC_OBSIDIAN_VAULT:=Main}"
: "${CC_OBSIDIAN_DIR:=$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/$CC_OBSIDIAN_VAULT}"
: "${CC_DROPBOX_DIR:=$HOME/Library/CloudStorage/Dropbox}"

# == Dev containers ==
alias dcu='devcontainer up --workspace-folder .'

# == Terminal launcher ==
# _cc_open_window <title> <command>
# Open a new terminal window running <command>, with its title pinned to
# <title>. Default: macOS Terminal.app via osascript. `do script` runs
# <command> in a fresh interactive shell, so your normal PATH is available (no
# wrapper needed) and `set custom title` pins the title so Claude's TUI can't
# overwrite it. Override this function in your own rc to drive a different
# terminal (Ghostty, iTerm, …); it receives the same two arguments.
_cc_open_window() {
  local title="$1" cmd="$2"
  osascript - "$title" "$cmd" <<'OSA'
on run argv
  set winTitle to item 1 of argv
  set winCmd to item 2 of argv
  tell application "Terminal"
    activate
    set newTab to do script winCmd
    set custom title of newTab to winTitle
  end tell
end run
OSA
}

# == Claude Code Remotes ==
# _cc_remote <mode:here|window> <target_env:container|local> <workspace-folder> <remote-name>
# target_env=container brings the devcontainer up and runs Claude inside it;
# target_env=local runs Claude directly on the host, cd'd into the folder.
#
# INVARIANT: --dangerously-skip-permissions (yolo) is set ONLY for
# target_env=container, where the container is the blast radius. target_env=local
# runs unsandboxed against real $HOME, so it gets default prompting. The flag is
# set once, from target_env, in $flags — do not hardcode it in a mode branch.
# mode=here runs in the current terminal (foreground); mode=window opens a new
# terminal window via _cc_open_window (so several can run at once). The command
# string is quoted with ${(q)...} so it survives being re-parsed by the shell
# that _cc_open_window spawns.
#
# NOTE: ccsessions (below) only discovers sessions via `docker ps`, so
# target_env=local sessions running on the bare host won't show up there.
_cc_remote() {
  local mode="$1" target_env="$2" folder="$3" name="$4"
  local -a flags=()

  case "$mode" in
    here|window) ;;
    *) echo "_cc_remote: invalid mode: $mode" >&2; return 2 ;;
  esac

  case "$target_env" in
    container)
      flags=(--dangerously-skip-permissions)
      devcontainer up --workspace-folder "$folder" || return 1
      if [[ "$mode" == window ]]; then
        _cc_open_window "CC,$name" \
          "exec devcontainer exec --workspace-folder ${(q)folder} claude ${(q)flags[@]} --remote-control ${(q)name}"
      else
        devcontainer exec --workspace-folder "$folder" claude "${flags[@]}" --remote-control "$name"
      fi
      ;;
    local)
      if [[ "$mode" == window ]]; then
        _cc_open_window "CC,$name" \
          "cd ${(q)folder} && exec claude ${(q)flags[@]} --remote-control ${(q)name}"
      else
        (cd "$folder" && exec claude "${flags[@]}" --remote-control "$name")
      fi
      ;;
    *) echo "_cc_remote: invalid target_env: $target_env" >&2; return 2 ;;
  esac
}

# Per-target wrappers — path/name/env defined once each; caller picks the mode.
_cc_obs()     { _cc_remote "$1" container "$CC_OBSIDIAN_DIR" Obsidian; }
_cc_sandbox() { _cc_remote "$1" container "$CC_SANDBOX_DIR" 1-SANDBOX; }
_cc_dropbox() { _cc_remote "$1" local "$CC_DROPBOX_DIR" Dropbox; }

# cc-remote-* — launch one remote in the CURRENT terminal.
cc-remote-obs()     { _cc_obs here; }
cc-remote-sandbox() { _cc_sandbox here; }
cc-remote-dropbox() { _cc_dropbox here; }

# ccremotes — launch all three, each in its own new terminal window.
ccremotes() { _cc_sandbox window && _cc_obs window && _cc_dropbox window; }

# ccsessions — list every claude --remote-control session across all running
# containers. Re-scans live each call (nothing is cached); running containers
# only, since stopped ones have no live process to list.
ccsessions() {
  printf '%-4s %-18s %-8s %-13s %s\n' '#' 'CONTAINER' 'PID' 'UPTIME' 'REMOTE'
  local n=0 id name pid up args remote
  for id in $(docker ps -q); do
    name=$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')
    # read splits on whitespace, absorbing ps's right-justified padding.
    while read -r pid up args; do
      n=$((n+1))
      remote=${args##*--remote-control }        # trailing arg after the flag
      printf '%-4s %-18s %-8s %-13s %s\n' "$n" "$name" "$pid" "$up" "$remote"
    done < <(docker exec "$id" ps -eo pid=,etime=,args= 2>/dev/null \
               | grep -- '--remote-control' | grep -v grep)
  done
  [[ $n -eq 0 ]] && echo "(no claude sessions found)" || true
}

# cckill — terminate every claude --remote-control session. Mirrors ccsessions'
# discovery: SIGTERM each matching PID inside every running container, plus any
# target_env=local sessions running on the bare host (which ccsessions can't
# see). grep -v excludes cckill's own grep from the match.
cckill() {
  local n=0 id name pid
  for id in $(docker ps -q); do
    name=$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')
    while read -r pid; do
      docker exec "$id" kill "$pid" 2>/dev/null && n=$((n+1)) \
        && echo "killed $name PID $pid"
    done < <(docker exec "$id" ps -eo pid=,args= 2>/dev/null \
               | grep -- '--remote-control' | grep -v grep | awk '{print $1}')
  done
  while read -r pid; do
    kill "$pid" 2>/dev/null && n=$((n+1)) && echo "killed local PID $pid"
  done < <(ps -eo pid=,args= \
             | grep -- 'claude.*--remote-control' | grep -v grep | awk '{print $1}')
  [[ $n -eq 0 ]] && echo "(no claude sessions found)" || echo "killed $n session(s)"
}

# == Dev container path resolution ==
# Python helper next to this file; $0 is the sourced file's path at load time.
_DC_RESOLVE_PY="${0:A:h}/dc-resolve.py"

# _dc_resolve [project_dir]
# Walks up from project_dir to find the enclosing .devcontainer/devcontainer.json,
# then prints two lines: the devcontainer root dir, and the container-side path
# corresponding to project_dir. Shared by dce and dccode.
_dc_resolve() {
  local project_dir devcontainer_dir devcontainer_json relative_dir remote_path

  project_dir="${1:-.}"
  project_dir="${project_dir:A}"
  devcontainer_dir="$project_dir"

  while [[ "$devcontainer_dir" != "/" && ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; do
    devcontainer_dir="${devcontainer_dir:h}"
  done

  if [[ ! -f "$devcontainer_dir/.devcontainer/devcontainer.json" ]]; then
    echo "Error: No enclosing .devcontainer/devcontainer.json found for $project_dir" >&2
    return 1
  fi

  if [[ "$project_dir" == "$devcontainer_dir" ]]; then
    relative_dir=""
  elif [[ "$project_dir" == "$devcontainer_dir/"* ]]; then
    relative_dir="${project_dir#$devcontainer_dir/}"
  else
    echo "Error: $project_dir is not inside devcontainer root $devcontainer_dir" >&2
    return 1
  fi

  devcontainer_json="$devcontainer_dir/.devcontainer/devcontainer.json"
  remote_path=$(python3 "$_DC_RESOLVE_PY" remote-path "$devcontainer_json" "$relative_dir") || return 1

  print -r -- "$devcontainer_dir"
  print -r -- "$remote_path"
}

# dce [project_dir]
# Opens an interactive zsh inside the enclosing dev container, cd'd into the
# subdirectory that corresponds to project_dir (default: current directory).
dce() {
  local resolved devcontainer_dir remote_path
  resolved=$(_dc_resolve "${1:-.}") || return 1
  devcontainer_dir="${resolved%%$'\n'*}"
  remote_path="${resolved#*$'\n'}"

  devcontainer exec --workspace-folder "$devcontainer_dir" zsh -c "cd ${(q)remote_path} && exec zsh"
}

# dccode [project_dir]
# Opens the subdirectory that corresponds to project_dir inside the enclosing
# dev container in VS Code (default: current directory).
dccode() {
  local resolved devcontainer_dir remote_path folder_uri docker_context
  resolved=$(_dc_resolve "${1:-.}") || return 1
  devcontainer_dir="${resolved%%$'\n'*}"
  remote_path="${resolved#*$'\n'}"
  docker_context=$(docker context show) || return 1

  folder_uri=$(python3 "$_DC_RESOLVE_PY" folder-uri "$devcontainer_dir" "$remote_path" "$docker_context") || return 1
  code --new-window --folder-uri "$folder_uri"
}
