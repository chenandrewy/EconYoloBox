#!/bin/bash
# ABOUTME: The container's postStartCommand. Arms the firewall unless this is
# ABOUTME: the normie container, checks the checkout marker, seeds agent
# ABOUTME: guidance, installs missing AI CLIs, checks policy, the package
# ABOUTME: volumes and the VS Code extensions, prints the posture (YOLO or
# ABOUTME: normie), clears leftover VS Code relay files outside normie,
# ABOUTME: refreshes TeX.
#
# Run by devcontainer.json on every container start (not on a bare
# `docker restart`, which skips postStartCommand entirely).
# Inputs:  YOLOBOX_INTERNET (from the config file, fixed at creation);
#          LOCAL_CONTAINER_FOLDER (check-checkout.sh); the
#          package mounts; PID 1's seccomp mode; the workspace setup scripts.
# Outputs: firewall state, the firewall-open marker, the checkout marker (or a
#          refusal), agent setup, the AI CLIs in npm-global when either is
#          missing, a warning for each unbuilt package volume and each missing
#          VS Code extension, the posture line
#          (YOLO mode, normie mode, or custom), removal of leftover VS Code
#          credential-relay files in /tmp unless normie, TeX refresh.
#
# The switch is YOLOBOX_INTERNET in the container's environment, which each
# mode's config file hard-codes: "open" in normie/devcontainer.json,
# "firewalled" in devcontainer.json. Anything but "open" arms - the failure
# direction is closed. Like the package mounts and seccomp, it is fixed at
# creation; the two modes are two containers. This script and the configs are
# still in the writable workspace, so an agent that edits them can change what
# the next start or creation does; see docs/features.md.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The open side writes the marker and the armed side removes it; posture.sh,
# and through it shellrc.sh and the -yolo launchers, read it. SANDBOX_INTERNET
# is the pre-rename name, still set in containers created before it.
internet=${YOLOBOX_INTERNET:-${SANDBOX_INTERNET:-firewalled}}
case "$internet" in
    open)
        touch /tmp/FIREWALL-WINDOW-OPEN
        echo 'YOLOBOX_INTERNET=open (the normie container) - skipping init-firewall.sh, no network restrictions' >&2
        ;;
    firewalled)
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
    *)
        echo "post-start.sh: unexpected YOLOBOX_INTERNET '$internet' - arming" >&2
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
esac

# One checkout per basename per Docker daemon: the per-checkout volumes are
# shared by both modes and named for the basename. Checked after the firewall
# is armed and before anything is seeded or installed.
bash .devcontainer/check-checkout.sh

bash agents/seed-agent-guidelines.sh

# The AI CLIs live in the per-checkout npm-global volume, which starts empty
# and is writable in every mode; npm is on the firewall allowlist. So a first
# start installs them here rather than asking the user (docs/journal/0926f).
# Only when one is missing: updates stay a deliberate `install-base.sh cli`.
# A failure warns and moves on; shellrc.sh keeps reminding.
if ! command -v claude >/dev/null 2>&1 || ! command -v codex >/dev/null 2>&1; then
    echo "post-start.sh: installing the AI CLIs (first start of this checkout's npm-global volume)" >&2
    bash .devcontainer/setup/install-base.sh cli ||
        echo "post-start.sh: AI CLI install failed; in the container: bash .devcontainer/setup/install-base.sh cli" >&2
fi

if command -v test-agent-policy.sh >/dev/null; then
    test-agent-policy.sh --warn-only || true
fi

# Docker seeds each fresh R, Python and TeX volume from the image, which
# carries the base (docs/journal/0926f), so a new volume starts built. A volume
# created before that holds only a skeleton and is never reseeded. Test a
# sentinel, not emptiness. Importing (not just finding) the sentinels also
# catches a volume built for another image.
missing=()
python3 -c 'import pyfixest' >/dev/null 2>&1 || missing+=(python)
Rscript -e 'quit(status = !requireNamespace("fixest", quietly = TRUE))' >/dev/null 2>&1 || missing+=(r)
# .sandbox-installed is the marker's pre-rename name (install-base.sh).
[ -f /usr/local/texlive/.yolobox-installed ] || [ -f /usr/local/texlive/.sandbox-installed ] || missing+=(tex)
if [ ${#missing[@]} -gt 0 ]; then
    echo "post-start.sh: package volume not built or not loadable: ${missing[*]}" >&2
    echo "  in normie mode, in the container: bash .devcontainer/setup/install-base.sh ${missing[*]}" >&2
    echo "  or remove the volume on the host and ybox --rebuild to seed it (.devcontainer/setup/README.md)" >&2
fi

# The VS Code extensions are installed only from normie, into the shared
# extension volume (docs/journal/0928e). Name each missing one here; shellrc.sh
# repeats a one-line note in every shell.
if ! ext_report=$(bash .devcontainer/setup/install-vscode-extensions.sh --verify 2>&1); then
    echo "post-start.sh: VS Code extensions missing from the shared volume:" >&2
    grep -E '^(MISSING|Missing)' <<<"$ext_report" | sed 's/^/  /' >&2 || true
    echo "  in normie mode, from a VS Code terminal: bash .devcontainer/setup/install-vscode-extensions.sh" >&2
fi

# The declared container mode is checked against the live internet and PID 1
# seccomp state. Package access is reported for this process separately; it may
# be read-only inside an additional agent sandbox even in normie mode.
posture=$(bash .devcontainer/posture.sh)
case "${posture%% *}" in
    yolo)
        echo "YOLO mode: ${posture#* }"
        ;;
    normie)
        echo "Normie mode: ${posture#* }"
        echo "  supervised: install with install.packages(), pip install or tlmgr install,"
        echo "  or bash .devcontainer/setup/install-optional.sh. Back to YOLO mode: on the host,"
        echo "  ybcode or ybe; ybox --stop --normie stops this container."
        ;;
    *)
        echo "Custom posture, neither YOLO nor normie mode: ${posture#* }" >&2
        echo "  made before the per-mode configs? on the host: ybox --rebuild" >&2
        ;;
esac

# An attached VS Code window leaves credential-relay sockets and scripts in
# /tmp, which is not tmpfs here, so they outlive the restart that ends their
# relays. Clearing them outside normie means any relay file seen later in
# YOLO comes from an attach since this start (docs/journal/1006a). Normie
# keeps its files: GitHub access is allowed there.
if [ "${posture%% *}" != normie ]; then
    rm -f /tmp/vscode-remote-containers-* /tmp/vscode-ssh-auth-* /tmp/vscode-git-*
fi

tex-refresh || { echo "TeX/LyX refresh failed; see the message above" >&2; true; }
