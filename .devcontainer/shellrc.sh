# Interactive shell setup for the container: PATH, aliases, and functions.
# Sourced, not executed: the Dockerfile (via zsh-in-docker) appends
# "source /workspace/.devcontainer/shellrc.sh" to ~/.zshrc, so every
# interactive shell picks this up. Currently only zsh sources it, but keep
# the syntax bash/zsh-portable so ~/.bashrc could source it too.

# workspace tools on PATH, organized by topic (see .devcontainer/agents/SANDBOX-CLAUDE.md)
#   pdf:     pdf2md.py, rebookmark.py
#   latex:   sync-lyx.sh
#   lit:     citation lookup (cited_by.py, via OpenAlex)
#   ai-sesh: sesh-init, sesh-push, sesh-wipe, cc-fork, gpt-fork
export PATH="/workspace/.tools/pdf:/workspace/.tools/latex:/workspace/.tools/lit:/workspace/.tools/ai-sesh:$PATH"

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

# cchat-yolo [claude args...]
# Start Claude in the container, always under --remote-control so the session is
# visible to `ccsessions` / `cckill` on the host. The name is derived from the
# working directory rather than asked for, so starting a session is still one
# word: on host "MacBook.local", /workspace/Live,Risk-vs-Writing becomes
# "MacBook:Live,Risk-vs-Writing#1". /workspace itself uses the host folder's
# name. Set CC_SESSION_NAME to override the project portion. Yolo is
# unconditional here because the container is the blast radius — host-side
# launchers that target a container pass the flag themselves.
_cc_session_name() {
    local base host n=1 running
    base="${CC_SESSION_NAME:-${PWD#/workspace}}"
    base="${base#/}"
    base="${base:-${LOCAL_CONTAINER_FOLDER##*/}}"
    host="${LOCAL_HOSTNAME:-}"
    host="${host%.local}"
    if [ -n "$host" ]; then
        base="${host}:${base}"
    fi
    # Number every session, so a second one in the same folder is still
    # distinguishable. Snapshot ps ONCE and match in-shell rather than piping to
    # grep per attempt: a grep in that pipeline carries the pattern in its own
    # argv, which ps then reports, so every number would look taken and the loop
    # would never end. The needle is quoted so it matches literally — a folder
    # name is not a pattern. A prefix hit (#1 against an existing #10) can only
    # skip a free number, never hand back a taken one. ([[ ]] rather than [ ]:
    # both bash and zsh have it, and it is the only readable substring test.)
    running=$(ps -eo args=)
    while [[ "$running" == *"--remote-control $base#$n"* ]]; do
        n=$((n + 1))
    done
    printf '%s#%s' "$base" "$n"
}

cchat-yolo() {
    claude --dangerously-skip-permissions --remote-control "$(_cc_session_name)" "$@"
}

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

alias gitlog="git log --graph --oneline --decorate --pretty=format:'%C(auto)%h %ad %d %s' --date=format:'%Y-%m-%d %H:%M'"
