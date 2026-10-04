# Run: source devcontainer.zsh; then ybcc/ ybgpt/ nbcc/ nbcodex [DIR] [-- ARGS...].
# Inputs: optional host project directory and literal agent arguments after --.
# Outputs: an agent session in the verified container, returning its exit status.
# Requires ybox from devcontainer.zsh; this file is sourced automatically there.

unalias ybagent nbagent ybcc ybgpt nbcc nbcodex 2>/dev/null || true

# One path through ybox keeps container selection, verification and cwd mapping
# identical to ybe. Quote every argument before passing it to the container zsh.
_yb_agent() {
  local mode="$1" agent="${2:-}" project_dir='.' arg shell_command
  local -a launch
  shift
  if [[ "$agent" == --help || "$agent" == -h || -z "$agent" ]]; then
    print -- 'Usage: ybagent|nbagent {cc|codex} [DIRECTORY] [-- AGENT_ARGS...]'
    [[ -n "$agent" ]] && return 0
    return 2
  fi
  shift
  case "$agent" in
    cc|claude) agent=cc ;;
    codex) ;;
    *) print -u2 -- "agent launcher: unknown agent: $agent (use cc or codex)"; return 2 ;;
  esac
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    print -- 'Usage: ybcc|ybgpt|nbcc|nbcodex [DIRECTORY] [-- AGENT_ARGS...]'
    return 0
  fi
  if (( $# )) && [[ "$1" != -- ]]; then
    [[ "$1" != -* ]] || { print -u2 -- 'agent launcher: put agent options after --'; return 2; }
    project_dir="$1"
    shift
  fi
  if (( $# )); then
    [[ "$1" == -- ]] || { print -u2 -- 'agent launcher: expected one directory, then -- before agent arguments'; return 2; }
    shift
  fi

  # These convenience commands own permission selection. Profiles/config files
  # can change it indirectly, so use ybe for bespoke permission configurations.
  for arg in "$@"; do
    case "$agent:$arg" in
      codex:--sandbox|codex:--sandbox=*|codex:-s*|codex:--ask-for-approval|codex:--ask-for-approval=*|codex:-a*|codex:--yolo|codex:--yolo=*|codex:--dangerously-bypass-approvals-and-sandbox*|codex:--full-auto|codex:--approve-for-me|codex:--config|codex:--config=*|codex:-c*|codex:--profile|codex:--profile=*|codex:-p*|cc:--permission-mode|cc:--permission-mode=*|cc:--dangerously-skip-permissions*|cc:--allow-dangerously-skip-permissions*|cc:--settings|cc:--settings=*)
        print -u2 -- "agent launcher: $arg can override the selected permission mode; use ybe for a custom launch"
        return 2
        ;;
    esac
  done

  case "$mode:$agent" in
    yolo:cc) launch=(cchat-yolo) ;;
    yolo:codex) launch=(gptchat-yolo) ;;
    normie:cc) launch=(command claude --permission-mode auto) ;;
    normie:codex) launch=(command codex --sandbox workspace-write --ask-for-approval on-request -c approvals_reviewer=auto_review) ;;
    *) print -u2 -- 'agent launcher: invalid container mode'; return 2 ;;
  esac
  launch+=("$@")
  shell_command="${(j: :)${(@q)launch}}"
  ybox "--$mode" --shell --command "$shell_command" -- "$project_dir"
}

ybagent() { _yb_agent yolo "$@"; }
nbagent() { _yb_agent normie "$@"; }
ybcc() { ybagent cc "$@"; }
ybgpt() { ybagent codex "$@"; }
nbcc() { nbagent cc "$@"; }
nbcodex() { nbagent codex "$@"; }

# Directory completion before --; leave agent-specific options to the agent.
_yb_agent_completion() {
  if (( ${words[(I)--]} )); then
    _files
  elif [[ "$words[1]" == (ybagent|nbagent) ]] && (( CURRENT == 2 )); then
    compadd cc codex
  else
    _files -/
  fi
}
if (( $+functions[compdef] )); then
  compdef _yb_agent_completion ybagent nbagent ybcc ybgpt nbcc nbcodex
fi
