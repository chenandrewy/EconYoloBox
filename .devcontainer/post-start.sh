#!/bin/bash
# ABOUTME: The container's postStartCommand. Arms the firewall unless
# ABOUTME: SANDBOX.toml opts out, then seeds agent guidance, checks policy and
# ABOUTME: the package volumes, refreshes TeX.
#
# Run by devcontainer.json on every container start (not on a bare
# `docker restart`, which skips postStartCommand entirely).
# Inputs:  SANDBOX.toml `firewall`; the workspace setup scripts.
# Outputs: firewall state, the shell-warning marker, agent setup, a warning for
#          each unbuilt package volume, TeX refresh.
#
# The switch is `firewall` in SANDBOX.toml, read here at every start. Anything
# but a bare `false` (unreadable file, typo, trailing junk) arms - the failure
# direction is closed. It takes effect at the next container start: a stop +
# reopen or a Rebuild Container, both of which give init-firewall.sh the fresh
# network namespace it needs (see its header). There is no review gate in
# either path - SANDBOX.toml is in the writable workspace, like this script.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The open side writes the marker and the armed side removes it; shellrc.sh
# warns on every shell while it exists. See the comment there for why the
# marker, not the kernel state, is what gets checked.
# A reader failure (sed cannot read the file - a Dropbox-evicted copy, say)
# must arm, not abort the script before init-firewall.sh runs.
firewall=$(bash .devcontainer/sandbox-setting.sh firewall) || {
    echo "post-start.sh: could not read SANDBOX.toml - arming" >&2
    firewall=
}
case "${firewall:-true}" in
    false)
        touch /tmp/FIREWALL-WINDOW-OPEN
        echo 'SANDBOX.toml: firewall = false - skipping init-firewall.sh, no network restrictions' >&2
        ;;
    true)
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
    *)
        echo "post-start.sh: SANDBOX.toml firewall = '$firewall' is not true|false - arming" >&2
        rm -f /tmp/FIREWALL-WINDOW-OPEN
        sudo /usr/local/bin/init-firewall.sh
        ;;
esac

bash .devcontainer/agents/seed-agent-guidelines.sh

if command -v test-agent-policy.sh >/dev/null; then
    test-agent-policy.sh --warn-only || true
fi

# The R, Python and TeX volumes are read-only here and built on the host. Test a
# sentinel, not emptiness: Docker seeds even a fresh read-only volume from the
# image, so an unbuilt venv still holds the bare skeleton. Importing (not just
# finding) the sentinels also catches a volume built for another image.
missing=()
python3 -c 'import pyfixest' >/dev/null 2>&1 || missing+=(python)
Rscript -e 'quit(status = !requireNamespace("fixest", quietly = TRUE))' >/dev/null 2>&1 || missing+=(r)
[ -f /usr/local/texlive/.sandbox-installed ] || missing+=(tex)
if [ ${#missing[@]} -gt 0 ]; then
    echo "post-start.sh: package volume not built or not loadable: ${missing[*]}" >&2
    echo "  on the host run: bash .setup/packages.sh ${missing[*]}" >&2
fi

tex-refresh || { echo "TeX/LyX refresh failed; see the message above" >&2; true; }
