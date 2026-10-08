# Run: source devcontainer.zsh; use yolobox --help for commands and shortcuts.
# Inputs: container mode, action, optional directory and literal agent arguments.
# Outputs: fixed-mode shortcuts and a quoted agent command for yolobox.

unalias ybcc ybgpt nbcc nbgpt 2>/dev/null || true

_yb_help() {
  cat <<'HELP'
Usage: yolobox [--yolo|--normie] [ACTION] [DIRECTORY] [-- AGENT_ARGS...]

Without an action, bring up and verify the selected container (default: YOLO).

Action          Purpose                         YOLO shortcut   Normie shortcut
--shell         Open a shell                    ybe             nbe
--code          Open VS Code                    ybcode          nbcode
--claude        Launch Claude                   ybcc            nbcc
--codex         Launch Codex                    ybgpt           nbgpt
--status        Report both containers
--stop          Stop the selected container

--rebuild                  Recreate both containers using the build cache
--rebuild-without-cache    Recreate both containers without the build cache
--command STRING          With --shell, run a command in the container shell
--help                    Show this help

Shortcuts select their action and mode; conflicting flags are rejected.
Agent arguments follow --; put DIRECTORY before --. Examples:
  yolobox --normie --codex My-Project -- resume --last
  nbgpt My-Project -- resume --last
  yolobox --status
HELP
}

_yb_shortcut() {
  local mode="$1" action="$2" arg after_separator=0 command_value=0
  local -a args
  shift 2
  for arg in "$@"; do
    if (( command_value )); then
      args+=("$arg")
      command_value=0
      continue
    fi
    if (( ! after_separator )); then
      case "$arg" in
        --) after_separator=1 ;;
        --command) command_value=1 ;;
        --yolo|--normie)
          [[ "$arg" == "--$mode" ]] || {
            print -u2 -- "launcher: this shortcut selects $mode; use the matching shortcut or yolobox"
            return 2
          }
          continue
          ;;
        --shell|--code|--claude|--codex|--status|--stop)
          print -u2 -- 'launcher: shortcuts select their action; use yolobox to choose another action'
          return 2
          ;;
      esac
    fi
    args+=("$arg")
  done
  yolobox "--$mode" "--$action" "${args[@]}"
}

_yb_agent_command() {
  local mode="$1" agent="$2" arg
  local -a launch
  shift 2
  # These convenience commands own permission selection. Profiles/config files
  # can change it indirectly, so use yolobox --shell --command for bespoke configurations.
  for arg in "$@"; do
    case "$agent:$arg" in
      codex:--sandbox|codex:--sandbox=*|codex:-s*|codex:--ask-for-approval|codex:--ask-for-approval=*|codex:-a*|codex:--yolo|codex:--yolo=*|codex:--dangerously-bypass-approvals-and-sandbox*|codex:--full-auto|codex:--approve-for-me|codex:--config|codex:--config=*|codex:-c*|codex:--profile|codex:--profile=*|codex:-p*|claude:--permission-mode|claude:--permission-mode=*|claude:--dangerously-skip-permissions*|claude:--allow-dangerously-skip-permissions*|claude:--settings|claude:--settings=*)
        print -u2 -- "agent launcher: $arg can override the selected permission mode; use yolobox --shell --command for a custom launch"
        return 2
        ;;
    esac
  done

  case "$mode:$agent" in
    yolo:claude) launch=(cchat-yolo) ;;
    yolo:codex) launch=(gptchat-yolo) ;;
    normie:claude) launch=(command claude --permission-mode auto) ;;
    normie:codex) launch=(command codex --sandbox workspace-write --ask-for-approval on-request -c approvals_reviewer=auto_review) ;;
    *) print -u2 -- 'agent launcher: invalid container mode'; return 2 ;;
  esac
  launch+=("$@")
  REPLY="${(j: :)${(@q)launch}}"
}

ybcc() { _yb_shortcut yolo claude "$@"; }
ybgpt() { _yb_shortcut yolo codex "$@"; }
nbcc() { _yb_shortcut normie claude "$@"; }
nbgpt() { _yb_shortcut normie codex "$@"; }

_yb_agent_completion() {
  if (( ${words[(I)--]} )); then
    _files
  else
    _arguments \
      '(--rebuild-without-cache)--rebuild[recreate both containers using the build cache]' \
      '(--rebuild)--rebuild-without-cache[recreate both containers without the build cache]' \
      '--help[show launcher help]' ':directory:_directories'
  fi
}
if (( $+functions[compdef] )); then
  compdef _yb_agent_completion ybcc ybgpt nbcc nbgpt
fi
