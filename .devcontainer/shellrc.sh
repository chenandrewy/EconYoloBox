# Interactive shell setup for the container: PATH, aliases, and functions.
# Sourced, not executed: the Dockerfile (via zsh-in-docker) appends
# "source /yolobox/.devcontainer/shellrc.sh" to ~/.zshrc, so every
# interactive shell picks this up. Currently only zsh sources it, but keep
# the syntax bash/zsh-portable so ~/.bashrc could source it too.
# Inputs: mounted workspace tools, installed toolchains, and container env.
# Outputs: shell PATH, aliases/functions, and local setup warnings.

# research tools on PATH, organized by topic (see /yolobox/agents/YOLOBOX-CLAUDE.md)
#   pdf:     pdf2md.py, rebookmark.py
#   latex:   sync-lyx.sh
#   lit:     citation lookup (cited_by.py, via OpenAlex)
#   ai-sesh: sesh-init, sesh-push, sesh-wipe, gpt-fork
export PATH="/yolobox/tools/pdf:/yolobox/tools/latex:/yolobox/tools/lit:/yolobox/tools/ai-sesh:$PATH"

# ai-sesh: keep the home session stores symlinked into the Dropbox-synced
# tree (idempotent; silent once the links exist — see tools/ai-sesh/README.md)
sesh-init || true

# The Python, R and TeX stacks live in shared volumes, read-only outside normie
# mode, so an unbuilt volume means no stack. Say so once per shell instead of
# letting the first import fail mysteriously. Test a sentinel, not emptiness:
# Docker seeds even a fresh read-only volume from the image, so an unbuilt venv
# still holds the bare skeleton. TeX's sentinel is the marker install-base.sh
# writes when a TeX install finishes. post-start.sh does the slower import check.
# (find, not a glob: an unmatched glob is a hard error under zsh's nomatch.)
_stacks_missing=""
if [ -z "$(find /opt/venv/lib -maxdepth 3 -type d -name pyfixest -print -quit 2>/dev/null)" ]; then
    _stacks_missing="python"
fi
if [ -z "$(find /opt/R -maxdepth 5 -type d -path '*/site-library/fixest' -print -quit 2>/dev/null)" ]; then
    _stacks_missing="${_stacks_missing:+$_stacks_missing }r"
fi
# .sandbox-installed is the TeX marker's pre-rename name (install-base.sh).
if [ ! -f /usr/local/texlive/.yolobox-installed ] && [ ! -f /usr/local/texlive/.sandbox-installed ]; then
    _stacks_missing="${_stacks_missing:+$_stacks_missing }tex"
fi
if [ -n "$_stacks_missing" ]; then
    echo "note: package volume not built ($_stacks_missing) - in normie mode, in the container: bash .devcontainer/setup/install-base.sh $_stacks_missing"
fi
unset _stacks_missing

# Same idea for the AI CLIs, which are also runtime-installed now (into the
# npm-global volume). This is the bootstrap path after a fresh volume: without
# it you would discover the absence by typing `claude` and getting nothing.
# Deliberately a local `command -v` and not a version check - the analysis-stack
# nag above tests a local absence, which is instant and cannot fail spuriously,
# whereas asking npm what `latest` is would put a network round-trip in front of
# every shell. Codex announces its own updates at launch; that is enough.
if ! command -v claude >/dev/null 2>&1 || ! command -v codex >/dev/null 2>&1; then
    echo "note: AI CLIs not installed - run .devcontainer/setup/install-base.sh cli"
fi

# VS Code extensions live in the shared extension volume, installed only from
# normie (docs/journal/0928e). A partial install is silent in the editor - a
# missing Pylance just means an empty Outline (0720c) - so check the registry
# in every shell. --verify only reads the volume (about 0.05s for 12).
if ! bash /yolobox/.devcontainer/setup/install-vscode-extensions.sh --verify >/dev/null 2>&1; then
    echo "note: VS Code extensions missing - in normie mode, from a VS Code terminal: bash .devcontainer/setup/install-vscode-extensions.sh"
fi

# Posture warning banner and prompt tag. Each mode has its own container,
# built from its own config file (ybcode or ybcode --normie on the host), so
# outside YOLO mode every shell warns what is loosened, and zsh's prompt
# carries a tag, so the mode stays in view. posture.sh checks the declared
# container mode against the firewall marker and PID 1's seccomp mode. It also
# reports package access for this process, which an agent sandbox may restrict.
_ybx_posture=$(bash /yolobox/.devcontainer/posture.sh)
_ybx_mode=${_ybx_posture%% *}
if [ "$_ybx_mode" != yolo ]; then
    if [ -t 1 ]; then
        _ybx_hi=$'\033[1;3;38;5;214m'
        _ybx_off=$'\033[0m'
    else
        _ybx_hi=''
        _ybx_off=''
    fi
    if [ "$_ybx_mode" = normie ]; then
        printf '%s\n' \
            "${_ybx_hi}Warning: Normie Mode${_ybx_off}" \
            'Firewall open, container package volumes writable, seccomp unconfined'
    else
        printf '%s\n' \
            "${_ybx_hi}Warning: Custom Posture${_ybx_off}" \
            "${_ybx_posture#* }; to fix, on the host: ybox --rebuild"
    fi
    unset _ybx_hi _ybx_off
fi
# The powerlevel10k prompt: no user segment (it only ever says ubuntu), and
# outside YOLO mode a mode segment at the front. This
# file is sourced before oh-my-zsh, and ~/.zshrc sets the element list after
# it, so a one-time precmd hook edits the list once it is final.
if [ -n "${ZSH_VERSION:-}" ]; then
    typeset -g _YBX_MODE=$_ybx_mode
    prompt_yolobox_mode() {
        if [ "$_YBX_MODE" = normie ]; then
            p10k segment -b 1 -f 15 -t normie
        else
            p10k segment -b 3 -f 0 -t custom
        fi
    }
    _ybx_prompt_segment() {
        POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[@]:#(user|yolobox_mode)})
        if [ "$_YBX_MODE" != yolo ]; then
            POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(yolobox_mode ${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[@]})
        fi
        add-zsh-hook -d precmd _ybx_prompt_segment
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _ybx_prompt_segment
fi
unset _ybx_posture _ybx_mode

# cchat-yolo [claude args...]
# Start Claude in the container, always under --remote-control so the session is
# visible to `ccsessions` / `cckill` on the host. The name is derived from the
# working directory rather than asked for, so starting a session is still one
# word: on host "MacBook.local", /yolobox/<folder>/My-Project becomes
# "MacBook:My-Project#1". The yolobox root itself uses the host folder's
# name. Set CC_SESSION_NAME to override the project portion. Yolo needs no
# flag here because the container is the blast radius — host-side launchers
# that target a container pass the flag themselves. That premise requires both
# the firewall and Docker's seccomp filter, so every -yolo launcher checks the
# live container boundaries before bypassing agent permissions: in normie mode
# they refuse.
_cc_session_name() {
    local base host n=1 running
    # Strip the top-level folder first, whatever it is named, then the yolobox
    # root, so both /yolobox/<folder>/Foo and /yolobox/tools reduce to a short
    # name.
    base="${CC_SESSION_NAME:-${PWD#/yolobox/*/}}"
    base="${base#/yolobox}"
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
    bash /yolobox/.devcontainer/check-yolo-boundaries.sh cchat-yolo || return 1
    claude --dangerously-skip-permissions --remote-control "$(_cc_session_name)" "$@"
}

alias hostname-local='echo "$LOCAL_HOSTNAME"'
alias container-folder-local='echo "$LOCAL_CONTAINER_FOLDER"'

# Everyday work is the -yolo launchers. Standard codex is the sandboxed mode,
# which needs unconfined seccomp (normie mode); see README.md for the recommended
# approvals_reviewer="auto_review" user preference. Only YOLO needs a wrapper
# here, to refuse startup unless the container's outer boundaries are active.
gptchat-yolo() {
    bash /yolobox/.devcontainer/check-yolo-boundaries.sh gptchat-yolo || return 1
    codex --dangerously-bypass-approvals-and-sandbox "$@"
}

gptmini-yolo() {
    bash /yolobox/.devcontainer/check-yolo-boundaries.sh gptmini-yolo || return 1
    codex --model gpt-5.4-mini --dangerously-bypass-approvals-and-sandbox "$@"
}

loccode() {
    printf 'code -n %q\n' "$LOCAL_CONTAINER_FOLDER"
}

alias gitlog="git log --graph --oneline --decorate --pretty=format:'%C(auto)%h %ad %d %s' --date=format:'%Y-%m-%d %H:%M'"

# R user config lives in the tracked repo, not ~/.Rprofile: the home dir is not
# a persisted volume, so a home-level profile would be wiped on every rebuild.
# R_PROFILE_USER points R at .devcontainer/home/Rprofile instead (see that file
# for what it sets, e.g. suppressing the stray Rplots.pdf). Add a home/Renviron
# and R_ENVIRON_USER here alongside it if env-style R settings are ever needed.
export R_PROFILE_USER=/yolobox/.devcontainer/home/Rprofile

# Never prompt to save the workspace image (.RData) on exit from an interactive
# R session. There is no R option for this - it is a front-end flag - so an
# alias is the standard fix. Rscript never prompts, so only interactive R is
# affected; --no-save is accepted before CMD, so `R CMD BATCH` still works.
alias R='R --no-save'

# No downloads at shell startup: an empty or wrong-platform mount needs host setup.
# During migration, a container built from the old image may still have distro
# TeX on PATH even though the new mounted installation is not active.
if [ ! -x /usr/local/texlive-bin/pdflatex ]; then
    if command -v pdflatex >/dev/null 2>&1; then
        echo "note: mounted TeX Live 2026 is not active; using $(command -v pdflatex)"
        echo "      Rebuild this container to activate the recent TeX-volume change."
    else
        echo "note: TeX unavailable - in normie mode, in the container: bash .devcontainer/setup/install-base.sh tex"
        echo "      For a nonempty failed install, inspect the volume's install.log first."
    fi
elif [ ! -f /usr/local/texlive/.yolobox-installed ] && [ ! -f /usr/local/texlive/.sandbox-installed ]; then
    echo "note: TeX volume has no install marker - in normie mode, in the container: bash .devcontainer/setup/install-base.sh tex"
    echo "      If it refuses, an earlier install failed: see .devcontainer/setup/README.md."
fi
