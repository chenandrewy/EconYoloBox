#!/bin/bash
# ABOUTME: The container's postStartCommand. Arms the firewall unless
# ABOUTME: SANDBOX.toml opts out, then seeds agent guidance, installs missing AI
# ABOUTME: CLIs, checks policy and the package volumes, prints the posture (YOLO
# ABOUTME: or normie), refreshes TeX.
#
# Run by devcontainer.json on every container start (not on a bare
# `docker restart`, which skips postStartCommand entirely).
# Inputs:  SANDBOX.toml `internet` and `packages`; the package mounts; PID 1's
#          seccomp mode; the workspace setup scripts.
# Outputs: firewall state, the shell-warning marker, agent setup, the AI CLIs
#          in npm-global when either is missing, a warning for
#          each unbuilt package volume, the posture line (YOLO mode, normie
#          mode, or custom; see SANDBOX.toml), TeX refresh.
#
# The switch is `internet` in SANDBOX.toml, read here at every start. Anything
# but `"open"` (unreadable file, typo, trailing junk) arms - the failure
# direction is closed. It takes effect at the next container start: a stop +
# reopen or a Rebuild Container, both of which give init-firewall.sh the fresh
# network namespace it needs (see its header). There is no review gate in
# either path - SANDBOX.toml is in the writable workspace, like this script.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The open side writes the marker and the armed side removes it; shellrc.sh
# warns on every shell while it exists. See the comment there for why the
# marker, not the kernel state, is what gets checked.
# A reader failure (the file cannot be read - a Dropbox-evicted copy, say)
# must arm, not abort the script before init-firewall.sh runs.
internet=$(bash .devcontainer/internet-setting.sh) || {
    echo "post-start.sh: could not read SANDBOX.toml - arming" >&2
    internet=firewalled
}
case "$internet" in
    open)
        touch /tmp/FIREWALL-WINDOW-OPEN
        echo 'SANDBOX.toml: internet = "open" - skipping init-firewall.sh, no network restrictions' >&2
        ;;
    firewalled)
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
    *)
        echo "post-start.sh: unexpected internet mode '$internet' - arming" >&2
        internet=firewalled
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
esac

bash .devcontainer/agents/seed-agent-guidelines.sh

# The AI CLIs live in the per-checkout npm-global volume, which starts empty
# and is writable in every mode; npm is on the firewall allowlist. So a first
# start installs them here rather than asking the user (docs/journal/0926f).
# Only when one is missing: updates stay a deliberate `install-base.sh cli`.
# A failure warns and moves on; shellrc.sh keeps reminding.
if ! command -v claude >/dev/null 2>&1 || ! command -v codex >/dev/null 2>&1; then
    echo "post-start.sh: installing the AI CLIs (first start of this checkout's npm-global volume)" >&2
    bash .setup/install-base.sh cli ||
        echo "post-start.sh: AI CLI install failed; in the container: bash .setup/install-base.sh cli" >&2
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
[ -f /usr/local/texlive/.sandbox-installed ] || missing+=(tex)
if [ ${#missing[@]} -gt 0 ]; then
    echo "post-start.sh: package volume not built or not loadable: ${missing[*]}" >&2
    echo "  in normie mode, in the container: bash .setup/install-base.sh ${missing[*]}" >&2
    echo "  or remove the volume on the host and bbox --rebuild to seed it (.setup/README.md)" >&2
fi

# The posture. internet is as armed above. packages and seccomp are fixed at
# creation by bbox, so they are read from the container (the mounts, PID 1),
# not from SANDBOX.toml, which may have changed since. Only the two presets in
# SANDBOX.toml are named; any other combination is reported as custom.
packages=$(bash .devcontainer/package-mode.sh)
case "$(sed -n -E 's/^Seccomp:[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' /proc/1/status 2>/dev/null)" in
    2) seccomp=builtin ;;
    0) seccomp=unconfined ;;
    *) seccomp=unverified ;;
esac
posture="internet=$internet packages=$packages seccomp=$seccomp"
case "$posture" in
    "internet=firewalled packages=readonly seccomp=builtin")
        echo "YOLO mode: $posture"
        ;;
    "internet=open packages=writable seccomp=unconfined")
        echo "Normie mode: $posture"
        echo "  supervised: install with install.packages(), pip install or tlmgr install,"
        echo "  or bash .setup/install-optional.sh. Back to YOLO mode: the preset"
        echo "  in SANDBOX.toml, then bbox --rebuild on the host."
        ;;
    *)
        echo "Custom posture, neither YOLO nor normie mode: $posture" >&2
        echo "  the presets are in SANDBOX.toml; apply one with bbox --rebuild on the host" >&2
        ;;
esac
requested=$(bash .devcontainer/packages-setting.sh 2>/dev/null) || requested="readonly"
case "$packages" in
"$requested" | mixed*) ;;
*) echo "post-start.sh: SANDBOX.toml asks for packages = \"$requested\", but they are mounted $packages; on the host run: bbox --rebuild" >&2 ;;
esac

tex-refresh || { echo "TeX/LyX refresh failed; see the message above" >&2; true; }
