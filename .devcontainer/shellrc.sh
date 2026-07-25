# Interactive shell setup for the container: PATH, aliases, and functions.
# Sourced, not executed: the Dockerfile (via zsh-in-docker) appends
# "source /workspace/.devcontainer/shellrc.sh" to ~/.zshrc, so every
# interactive shell picks this up. Currently only zsh sources it, but keep
# the syntax bash/zsh-portable so ~/.bashrc could source it too.

# workspace tools on PATH, organized by topic (see .devcontainer/agents/SANDBOX-CLAUDE.md)
#   pdf:     pdf2md.py, rebookmark.py
#   latex:   sync-lyx.sh
#   dev:     experimental scripts (cited_by.py)
#   ai-sesh: sesh-init, sesh-push, sesh-wipe, cc-fork, gpt-fork
export PATH="/workspace/.tools/pdf:/workspace/.tools/latex:/workspace/.tools/dev:/workspace/.tools/ai-sesh:$PATH"

# ai-sesh: keep the home session stores symlinked into the Dropbox-synced
# tree (idempotent; silent once the links exist — see .tools/ai-sesh/README.md)
sesh-init || true

# The Python and R analysis stacks are installed at runtime rather than baked
# into the image, so a freshly built container starts without them. Say so once
# per shell instead of letting the first import fail mysteriously.
# (find, not a glob: an unmatched glob is a hard error under zsh's nomatch.)
if [ -z "$(find /opt/venv/lib -maxdepth 3 -type d -name pandas -print -quit 2>/dev/null)" ] ||
    [ -z "$(find /opt/R -maxdepth 5 -type d -name fixest -print -quit 2>/dev/null)" ]; then
    echo "note: analysis stack not fully installed - run .devcontainer/install-packages.sh"
fi

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
