# Interactive shell setup for the container: PATH, aliases, and functions.
# Sourced, not executed: the Dockerfile (via zsh-in-docker) appends
# "source /sandbox/.devcontainer/shellrc.sh" to ~/.zshrc, so every
# interactive shell picks this up. Currently only zsh sources it, but keep
# the syntax bash/zsh-portable so ~/.bashrc could source it too.
# Inputs: mounted workspace tools, installed toolchains, and container env.
# Outputs: shell PATH, aliases/functions, and local setup warnings.

# workspace tools on PATH, organized by topic (see .devcontainer/agents/SANDBOX-CLAUDE.md)
#   pdf:     pdf2md.py, rebookmark.py
#   latex:   sync-lyx.sh
#   lit:     citation lookup (cited_by.py, via OpenAlex)
#   ai-sesh: sesh-init, sesh-push, sesh-wipe, cc-fork, gpt-fork
export PATH="/sandbox/.tools/pdf:/sandbox/.tools/latex:/sandbox/.tools/lit:/sandbox/.tools/ai-sesh:$PATH"

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

# Same idea for the AI CLIs, which are also runtime-installed now (into the
# npm-global volume). This is the bootstrap path after a fresh volume: without
# it you would discover the absence by typing `claude` and getting nothing.
# Deliberately a local `command -v` and not a version check - the analysis-stack
# nag above tests a local absence, which is instant and cannot fail spuriously,
# whereas asking npm what `latest` is would put a network round-trip in front of
# every shell. Codex announces its own updates at launch; that is enough.
if ! command -v claude >/dev/null 2>&1 || ! command -v codex >/dev/null 2>&1; then
    echo "note: AI CLIs not installed - run .devcontainer/install-packages.sh cli"
fi

# Firewall window warning. post-start.sh skips init-firewall.sh when
# SANDBOX.toml says firewall = false, leaving the container on
# Docker's default ACCEPT policies - no network restrictions at all. Nothing
# else surfaces that state: startup looks entirely normal and the only symptom
# is that blocked hosts start answering.
#
# post-start.sh touches this marker on the open path and removes it on the
# armed one, so no network probe is needed here. Not inferred from dnsmasq or resolv.conf:
# both look "open" on init-firewall.sh's legitimate armed-but-dnsmasq-failed
# path, and iptables itself needs root. The open side writes the marker rather
# than the armed side because /tmp is not tmpfs here - a stale "armed" marker
# would fail silent, whereas a stale open one only cries wolf.
#
# Knows what devcontainer.json declared at the last container start, not the
# live kernel state: a bare `docker restart` skips postStartCommand entirely
# and leaves the container open with whatever marker was there before.
if [ -f /tmp/FIREWALL-WINDOW-OPEN ]; then
    if [ -t 1 ]; then
        _fw_hi=$'\033[1;3;38;5;214m'
        _fw_off=$'\033[0m'
    else
        _fw_hi=''
        _fw_off=''
    fi
    printf '%s\n' \
        "${_fw_hi}Warning: Firewall Open${_fw_off}" \
        "To close: set firewall = true in /sandbox/SANDBOX.toml, then rebuild container"
    unset _fw_hi _fw_off
fi

# Docker's outer seccomp filter is a separate safety boundary from the
# firewall. Each interactive shell compares current SANDBOX.toml with PID 1;
# config edits cannot alter an already-created container. PID 1 is used because
# an inner agent sandbox may add a filter to the checking process itself.
case $- in
    *i*) bash /sandbox/.devcontainer/check-seccomp.sh ;;
esac

# cchat-yolo [claude args...]
# Start Claude in the container, always under --remote-control so the session is
# visible to `ccsessions` / `cckill` on the host. The name is derived from the
# working directory rather than asked for, so starting a session is still one
# word: on host "MacBook.local", /sandbox/workspace/My-Project becomes
# "MacBook:My-Project#1". The sandbox root itself uses the host folder's
# name. Set CC_SESSION_NAME to override the project portion. Yolo needs no
# flag here because the container is the blast radius — host-side launchers
# that target a container pass the flag themselves. That premise requires both
# the firewall and Docker's seccomp filter, so every -yolo launcher checks the
# live container boundaries before bypassing agent permissions.
_cc_session_name() {
    local base host n=1 running
    # Strip the user-workspace prefix first, then the sandbox root, so both
    # /sandbox/workspace/Foo and /sandbox/.tools reduce to a short name.
    base="${CC_SESSION_NAME:-${PWD#/sandbox/workspace}}"
    base="${base#/sandbox}"
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
    bash /sandbox/.devcontainer/check-yolo-boundaries.sh cchat-yolo || return 1
    claude --dangerously-skip-permissions --remote-control "$(_cc_session_name)" "$@"
}

alias hostname-local='echo "$LOCAL_HOSTNAME"'
alias container-folder-local='echo "$LOCAL_CONTAINER_FOLDER"'

# Use standard codex for chaperoned everyday work; see README.md for the
# recommended approvals_reviewer="auto_review" user preference. Only YOLO needs a wrapper
# here, to refuse startup unless the container's outer boundaries are active.
gptchat-yolo() {
    bash /sandbox/.devcontainer/check-yolo-boundaries.sh gptchat-yolo || return 1
    codex --dangerously-bypass-approvals-and-sandbox "$@"
}

gptmini-yolo() {
    bash /sandbox/.devcontainer/check-yolo-boundaries.sh gptmini-yolo || return 1
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
export R_PROFILE_USER=/sandbox/.devcontainer/home/Rprofile

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
        echo "note: TeX unavailable - on the host run: bash .setup/texlive.sh"
        echo "      For a nonempty failed install, inspect the volume's install.log first."
    fi
fi
