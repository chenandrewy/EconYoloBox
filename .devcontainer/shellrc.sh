#!/bin/bash

export PATH="/workspace/.tools:$PATH"

alias cchat-yolo='claude --dangerously-skip-permissions'
alias hostname-local='echo "$LOCAL_HOSTNAME"'
alias container-folder-local='echo "$LOCAL_CONTAINER_FOLDER"'

gptchat-yolo() {
    codex --dangerously-bypass-approvals-and-sandbox "$@"
}

gptmini-yolo() {
    codex --model gpt-5.4-mini --dangerously-bypass-approvals-and-sandbox "$@"
}

loccode() {
    printf 'code -n %q\n' "$LOCAL_CONTAINER_FOLDER"
}

claude-yolo() {
    local fmt="${CLAUDE_OUTPUT:-text}"
    if [ "$fmt" = "stream-json" ]; then
        claude -p --verbose --output-format stream-json --dangerously-skip-permissions "$@" | jq -r '.result // .'
    elif [ "$fmt" = "none" ]; then
        claude -p --output-format text --dangerously-skip-permissions "$@" > /dev/null
    else
        claude -p --output-format "$fmt" --dangerously-skip-permissions "$@"
    fi
}

alias gitlog="git log --graph --oneline --decorate --pretty=format:'%C(auto)%h %ad %d %s' --date=format:'%Y-%m-%d %H:%M'"

# ai-sesh: cache/restore/fork agent seed sessions
# provides: sesh-grab, sesh-push, sesh-wipe, cc-fork, gpt-fork
export PATH="/workspace/.tools/ai-sesh:$PATH"
