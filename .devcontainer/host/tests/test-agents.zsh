#!/usr/bin/env zsh
# Run: zsh .devcontainer/host/tests/test-agents.zsh
# Inputs: real host parser and agent launchers; fake startup and agent executables.
# Outputs: pass/fail messages; no Docker, network, or real agent sessions.
setopt errexit nounset pipefail
test_root=${0:A:h:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/bin/agent" <<'MOCK'
#!/usr/bin/env zsh
# Run: by test-agents.zsh. Inputs: literal argv. Outputs: name and argv per line.
print -rl -- "${0:t}" "$@"
MOCK
chmod +x "$tmp/bin/agent"
for agent in claude codex cchat-yolo gptchat-yolo; do
  ln -s agent "$tmp/bin/$agent"
done
export PATH="$tmp/bin:$PATH"
alias ybcc=false nbgpt=false
source "$test_root/.devcontainer/host/devcontainer.zsh"
source "$test_root/.devcontainer/host/devcontainer.zsh"
typeset -ga captured
typeset -gi mock_status=0 calls=0
# Retain parser, command construction and quoting; mock external startup only.
_dc_resolve() { print -r -- "$1" >"$tmp/project"; print -rl -- "$test_root" .; }
_ybox_containers() { :; }
_ybox_up() { (( ++calls )); REPLY=mock; }
_ybox_note_normie() { :; }
devcontainer() { captured=("$@"); return $mock_status; }
fail() { print -u2 -- "FAIL: $*"; exit 1; }

for name mode action executable in ybcc yolo claude cchat-yolo ybgpt yolo codex gptchat-yolo nbcc normie claude claude nbgpt normie codex codex; do
  "$name" 'project with spaces; $(false)' -- --model 'a model' || fail "$name"
  [[ "$(cat "$tmp/project")" == 'project with spaces; $(false)' ]] || fail 'directory forwarding'
  [[ "$captured[5]" == "$(_ybox_config "$test_root" "$mode")" ]] || fail "$name mode"
  short_command="$captured[-1]"
  actual=$(zsh -fc "$short_command")
  case "$name" in
    ybcc|ybgpt) expected=$(print -rl -- "$executable" --model 'a model') ;;
    nbcc) expected=$(print -rl -- claude --permission-mode auto --model 'a model') ;;
    nbgpt) expected=$(print -rl -- codex --sandbox workspace-write --ask-for-approval on-request -c approvals_reviewer=auto_review --model 'a model') ;;
  esac
  [[ "$actual" == "$expected" ]] || fail "$name argv: $actual"
  yolobox "--$mode" "--$action" 'project with spaces; $(false)' -- --model 'a model'
  [[ "$captured[-1]" == "$short_command" ]] || fail "$name long form differs"
done
print 'ok - all agent shortcuts and long forms preserve modes, directories and permission arguments'

prompt='quotes " and '\''; $(touch SHOULD_NOT_EXIST) `false` *'
ybcc -- "$prompt" '' $'two\nlines'
[[ "$(cat "$tmp/project")" == . ]] || fail 'default directory'
actual=$(zsh -fc "$captured[-1]")
expected=$(print -rl -- cchat-yolo "$prompt" '' $'two\nlines')
[[ "$actual" == "$expected" ]] || fail 'literal argument forwarding'
yolobox --normie --codex -- resume --last
[[ "$captured[-1]" == *'resume --last' ]] || fail 'codex subcommand'
print 'ok - prompts, empty arguments, newlines and subcommands survive quoting'

for name option in nbcc --permission-mode=bypassPermissions nbgpt --yolo nbgpt -sdanger-full-access nbgpt --config=approval_policy=never ybcc --settings=/tmp/settings.json; do
  before=$calls
  "$name" -- "$option" >/dev/null 2>&1 && fail "accepted $option"
  (( calls == before )) || fail 'invalid options reached startup'
done
before=$calls
for name mode in ybe normie ybcode normie ybcc normie ybgpt normie nbe yolo nbcode yolo nbcc yolo nbgpt yolo; do
  "$name" "--$mode" >/dev/null 2>&1 && fail "$name mode override"
done
for args in '--claude --codex' '--codex --shell' '--codex --command false' '--codex one two' '--codex -- --yolo'; do
  yolobox ${=args} >/dev/null 2>&1 && fail "accepted $args"
done
ybcc one two >/dev/null 2>&1 && fail 'two directories'
ybcc --help >/dev/null
yolobox --help >/dev/null
(( calls == before )) || fail 'invalid arguments/help reached startup'
yolobox --codex -- --help
[[ "$captured[-1]" == *'gptchat-yolo --help' ]] || fail 'agent help forwarding'
nbe --command --yolo
[[ "$captured[-1]" == *'&& --yolo' ]] || fail 'shell command value parsed as mode flag'
nbe --normie
[[ "$captured[5]" == "$(_ybox_config "$test_root" normie)" ]] || fail 'redundant matching mode flag'
mock_status=37
nbgpt && fail 'lost failure'
[[ $? == 37 ]] || fail 'wrong exit status'
print 'ok - conflicts fail before startup; help and agent exit status work'
