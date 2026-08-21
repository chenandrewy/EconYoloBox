# Shared helpers for the ai-sesh scripts. Source, don't execute.

tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="/workspace"
data_root="$tools_dir/data"

claude_projects_root="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
codex_store="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
todos_store="${CLAUDE_TODOS_DIR:-$HOME/.claude/todos}"

# Machine id: AI_SESH_MACHINE override, else derived from the host name the
# devcontainer injects (write-local-env.sh -> LOCAL_HOSTNAME), e.g.
# "Mac-Studio.local" -> "mac-studio". Sets machine_id and self_root.
resolve_machine() {
  machine_id="${AI_SESH_MACHINE:-}"
  if [ -z "$machine_id" ] && [ -n "${LOCAL_HOSTNAME:-}" ]; then
    machine_id="$(printf '%s' "$LOCAL_HOSTNAME" \
      | sed 's/\.local$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"
  fi
  if [ -z "$machine_id" ]; then
    echo "ai-sesh: no machine id (need LOCAL_HOSTNAME or AI_SESH_MACHINE)" >&2
    return 1
  fi
  self_root="$data_root/$machine_id"
}

# Machines other than self that have a store under data/.
other_machines() {
  local d
  for d in "$data_root"/*/; do
    [ -d "$d" ] || continue
    d="$(basename "$d")"
    [ "$d" = "$machine_id" ] || printf '%s\n' "$d"
  done
}

# Claude stores sessions under the launch dir's path with / and , mapped to -.
claude_key_for_rel() {
  printf '%s' "$workspace_root/$1" | sed 's#[/,]#-#g'
}

# For commands that operate on "the current project" (the forks): derive
# everything from pwd. Run them from the directory where you run claude/codex.
require_project_cwd() {
  project_dir="$(pwd)"
  case "$project_dir" in
    "$workspace_root"/*) ;;
    *)
      echo "Run this from inside a /workspace project (current dir: $project_dir)" >&2
      exit 1
      ;;
  esac
  project_rel="${project_dir#"$workspace_root"/}"
  claude_store="${CLAUDE_PROJECT_DIR:-$claude_projects_root/$(claude_key_for_rel "$project_rel")}"
}

# sync_file SRC DEST SRC_MACHINE
# Install an append-only session log from another machine's store, using the
# size/prefix ladder (mtime is deliberately never consulted). Prints one of:
#   install       dest didn't exist; copied
#   skip          same size; assumed identical
#   fast-forward  dest was a byte-prefix of src; replaced with src
#   ahead         src is a byte-prefix of dest; dest already newer
#   DIVERGED      neither is a prefix; src quarantined next to dest
sync_file() {
  local src="$1" dest="$2" src_machine="$3" src_size dest_size
  if [ ! -f "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    install -m 600 "$src" "$dest"
    echo install
    return 0
  fi
  src_size="$(stat -c%s "$src")"
  dest_size="$(stat -c%s "$dest")"
  if [ "$src_size" -eq "$dest_size" ]; then
    echo skip
  elif [ "$src_size" -gt "$dest_size" ] && cmp -s -n "$dest_size" "$src" "$dest"; then
    install -m 600 "$src" "$dest"
    echo fast-forward
  elif [ "$src_size" -lt "$dest_size" ] && cmp -s -n "$src_size" "$src" "$dest"; then
    echo ahead
  else
    # True divergence: keep both. The quarantine name doesn't end in .jsonl,
    # so the agents' session scans ignore it; resolve by hand.
    cp -f "$src" "$dest.divergent-$src_machine"
    echo DIVERGED
  fi
}
