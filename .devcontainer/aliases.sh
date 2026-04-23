#!/bin/bash

alias cchat-yolo='claude --dangerously-skip-permissions'
alias gptchat-yolo="codex --sandbox danger-full-access"

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
