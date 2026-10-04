#!/usr/bin/env zsh
# Run: zsh .devcontainer/host/tests/test-agents.zsh
# Inputs: shared agent launchers; fake agents and ybox (no Docker or network).
# Outputs: pass/fail messages; nonzero status on failure.
setopt errexit nounset pipefail
root=${0:A:h:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/bin/agent" <<'MOCK'
#!/usr/bin/env zsh
# Run: via test-agents.zsh under an agent executable name.
# Inputs: literal agent argv. Outputs: executable name and argv, one per line.
print -rl -- "${0:t}" "$@"
MOCK
chmod +x "$tmp/bin/agent"
for agent in claude codex cchat-yolo gptchat-yolo; do
  ln -s agent "$tmp/bin/$agent"
done
export PATH="$tmp/bin:$PATH"
alias ybcc=false nbcodex=false
source "$root/.devcontainer/host/agents.zsh"
source "$root/.devcontainer/host/agents.zsh"
typeset -ga captured
typeset -gi mock_status=0 calls=0
ybox() { captured=("$@"); (( ++calls )); return $mock_status; }
fail() { print -u2 -- "FAIL: $*"; exit 1; }

for name mode executable in ybcc yolo cchat-yolo ybgpt yolo gptchat-yolo nbcc normie claude nbcodex normie codex; do
  "$name" 'project with spaces; $(false)' -- --model 'a model' || fail "$name"
  [[ "$captured[1]" == "--$mode" && "$captured[2]" == --shell && "$captured[3]" == --command && "$captured[5]" == -- && "$captured[6]" == 'project with spaces; $(false)' ]] || fail "$name routing"
  actual=$(zsh -fc "$captured[4]")
  case "$name" in
    ybcc|ybgpt) expected=$(print -rl -- "$executable" --model 'a model') ;;
    nbcc) expected=$(print -rl -- claude --permission-mode auto --model 'a model') ;;
    nbcodex) expected=$(print -rl -- codex --sandbox workspace-write --ask-for-approval on-request -c approvals_reviewer=auto_review --model 'a model') ;;
  esac
  [[ "$actual" == "$expected" ]] || fail "$name agent argv: $actual"
done
print 'ok - all four commands select the right container and permission arguments'

prompt='quotes " and '\''; $(touch SHOULD_NOT_EXIST) `false` *'
ybcc -- "$prompt" '' $'two\nlines'
[[ "$captured[6]" == . ]] || fail 'default directory'
actual=$(zsh -fc "$captured[4]")
expected=$(print -rl -- cchat-yolo "$prompt" '' $'two\nlines')
[[ "$actual" == "$expected" ]] || fail 'literal argument forwarding'
ybagent claude -- --resume
[[ "$captured[4]" == 'cchat-yolo --resume' ]] || fail 'claude alias'
nbagent codex -- resume --last
[[ "$captured[4]" == *'resume --last' ]] || fail 'codex subcommand'
print 'ok - prompts, empty arguments, newlines, and resume arguments survive shell quoting'

for name option in nbcc --permission-mode=bypassPermissions nbcodex --yolo nbcodex -sdanger-full-access nbcodex --config=approval_policy=never ybcc --settings=/tmp/settings.json; do
  before=$calls
  "$name" -- "$option" >/dev/null 2>&1 && fail "accepted $option"
  (( calls == before )) || fail 'invalid options reached ybox'
done
before=$calls
ybagent missing >/dev/null 2>&1 && fail 'unknown agent'
ybcc one two >/dev/null 2>&1 && fail 'two directories'
ybcc --normie >/dev/null 2>&1 && fail 'mode override'
ybcc --help >/dev/null
(( calls == before )) || fail 'usage/help reached ybox'
mock_status=37
ybcc && fail 'lost failure'
[[ $? == 37 ]] || fail 'wrong exit status'
print 'ok - invalid options stop before container startup; help and exit status work'
