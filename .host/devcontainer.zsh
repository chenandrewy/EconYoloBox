# devcontainer.zsh — bring dev containers up and open a shell or editor inside
# the one enclosing a given directory.
#
# Source this from your interactive shell rc (zsh):
#   source /path/to/1-SANDBOX/.host/devcontainer.zsh
#
# Inputs:  none — no configuration, and nothing is exported.
# Outputs: dcu, dce, dccode. Requires: docker, the `devcontainer` CLI,
#   python3 (for dc-resolve.py), and the `code` CLI for dccode.
#
# Scope: navigation only. Launching and managing Claude Code sessions is a
# separate, personal concern that lives in the machine-settings repo
# (MacUser/Shell-rc/cc-remotes.zsh); nothing here knows about it.

# Directory holding this toolkit. Derived unconditionally from $0 — this file's
# own path at load time — so a second checkout sourced into the same shell can
# never make this one read the other's dc-resolve.py. Derived state, not config:
# do not switch this to `:=`. dc-resolve.py is a sibling of this file.
_DC_HOST_DIR="${0:A:h}"
_DC_RESOLVE_PY="$_DC_HOST_DIR/dc-resolve.py"

# == Bring one up ==
alias dcu='devcontainer up --workspace-folder .'

# == Dev container path resolution ==
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
