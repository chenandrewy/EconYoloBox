#!/usr/bin/env bash
# Run on the host, with Docker running, from anywhere in this checkout (bash 3.2+):
#   bash .setup/packages.sh                  # python r (the default)
#   bash .setup/packages.sh tex              # TeX Live only (opt-in)
#   bash .setup/packages.sh all              # python r tex
#   bash .setup/packages.sh r --force        # reinstall present R packages
# Inputs: this workspace's devcontainer (created by bbox, running or stopped),
#   whose exact image is the builder; the shared volume names in
#   .devcontainer/devcontainer.json; the package lists in
#   .devcontainer/install-packages.sh; network access from Docker's default
#   network (the devcontainer firewall does not apply here).
# Outputs: the named shared volumes, filled or updated in place by
#   install-packages.sh (the TeX volume also holds install.log). Consuming
#   containers see the change at the next R/Python session or tex-refresh.
#
# Why the devcontainer's own image: R packages link against the image's shared
# libraries and use its Rprofile.site snapshot, so the volume must be built by
# the image that will consume it. There is no fallback to another image.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: bash .setup/packages.sh [python] [r] [tex] [all] [--force]

With no target, builds python and r. tex is opt-in; all = python r tex.
--force reinstalls present python/r packages (not accepted with tex).
USAGE
}

targets=()
force=()
for arg in "$@"; do
    case "$arg" in
    python | r | tex) targets+=("$arg") ;;
    all) targets+=(python r tex) ;;
    --force | -f) force=(--force) ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "packages.sh: unknown argument '$arg' (cli is updated inside the container)" >&2
        usage >&2
        exit 2
        ;;
    esac
done
if [ ${#targets[@]} -eq 0 ]; then
    targets=(python r)
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
logical_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -L)
json="$root/.devcontainer/devcontainer.json"

# shellcheck source=SCRIPTDIR/../.devcontainer/find-python.sh
source "$root/.devcontainer/find-python.sh"
volumes=$("$PYTHON" "$root/.host/dc-resolve.py" package-volumes "$json")

# The devcontainer CLI labels the container with the host folder it was
# opened from. bbox resolves symlinks; another opener may not.
containers=$(docker ps -aq --no-trunc --filter "label=devcontainer.local_folder=$root")
if [ -z "$containers" ] && [ "$logical_root" != "$root" ]; then
    containers=$(docker ps -aq --no-trunc --filter "label=devcontainer.local_folder=$logical_root")
fi
count=$(printf '%s' "$containers" | grep -c . || true)
if [ "$count" -ne 1 ]; then
    echo "packages.sh: found $count devcontainers for $root; need exactly one to take its image from." >&2
    echo "Run bbox --rebuild first." >&2
    exit 1
fi
image=$(docker inspect -f '{{.Image}}' "$containers")
echo "Builder image: $image (from container ${containers:0:12})"

mounts=()
unique=()
seen=" "
for target in "${targets[@]}"; do
    case "$seen" in *" $target "*) continue ;; esac
    seen+="$target "
    unique+=("$target")
    line=$(awk -v s="$target" '$1 == s' <<<"$volumes")
    read -r _ volume path <<<"$line"
    echo "  $target -> $volume ($path)"
    mounts+=(--mount "type=volume,source=$volume,target=$path")
done

echo "Stop R, Python and TeX work in every container that mounts these volumes first."
docker run --rm --user root \
    -e PIP_ROOT_USER_ACTION=ignore \
    "${mounts[@]}" \
    --mount "type=bind,source=$root/.devcontainer,target=/setup,readonly" \
    "$image" bash /setup/install-packages.sh "${unique[@]}" ${force[@]+"${force[@]}"}

echo "Consumers: restart R/Python sessions; after a TeX change run tex-refresh and reopen LyX."
