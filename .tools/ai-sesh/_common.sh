# Shared helpers for the ai-sesh scripts. Source, don't execute.

tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="/workspace"
data_root="$tools_dir/data"

claude_projects_root="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
codex_store="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"

# Claude stores sessions under the launch dir's path with / and , mapped to -.
claude_key_for_rel() {
  printf '%s' "$workspace_root/$1" | sed 's#[/,]#-#g'
}

# For commands that operate on "the current project" (grab, fork): derive
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
  data_dir="$data_root/$project_rel"
  claude_cache="$data_dir/claude"
  codex_cache="$data_dir/codex"
}

# Print YYYY MM DD for a codex rollout file (from its name, else its content).
codex_date_parts() {
  local file="$1" base
  base="$(basename "$file")"
  if [[ "$base" =~ ^rollout-([0-9]{4})-([0-9]{2})-([0-9]{2})T.*\.jsonl$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    return 0
  fi
  python3 - "$file" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        payload = obj.get("payload") or {}
        timestamp = payload.get("timestamp") or obj.get("timestamp")
        if timestamp:
            print(*timestamp[:10].split("-"))
            break
PY
}

# Install one cached codex rollout into the dated home store.
install_codex_file() {
  local file="$1" year="" month="" day=""
  # || true: under set -e, read failing on empty output would exit before
  # the diagnostic below can print.
  read -r year month day < <(codex_date_parts "$file") || true
  if [ -z "${year:-}" ] || [ -z "${month:-}" ] || [ -z "${day:-}" ]; then
    echo "Could not determine Codex session date for: $file" >&2
    exit 1
  fi
  mkdir -p "$codex_store/$year/$month/$day"
  install -m 600 "$file" "$codex_store/$year/$month/$day/"
}

# Install the current project's cached sessions into the home stores.
# Requires require_project_cwd. Used by the fork commands before resuming.
install_cached_sessions() {
  local installed=false file
  if compgen -G "$claude_cache/*.jsonl" > /dev/null; then
    mkdir -p "$claude_store"
    install -m 600 "$claude_cache"/*.jsonl "$claude_store"/
    installed=true
    echo "Installed Claude seeds -> $claude_store"
  fi
  if compgen -G "$codex_cache/*.jsonl" > /dev/null; then
    for file in "$codex_cache"/*.jsonl; do
      install_codex_file "$file"
    done
    installed=true
    echo "Installed Codex seeds  -> $codex_store/YYYY/MM/DD"
  fi
  [ "$installed" = true ]
}
