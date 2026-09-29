# dc-resolve.py — devcontainer path/URI helpers for the dc* shell functions
#
# Run:
#   python3 dc-resolve.py remote-path <devcontainer.json> <relative-dir>
#     Inputs:  path to a devcontainer.json (JSONC allowed), and the project
#              directory's path relative to the devcontainer root ("" for root).
#     Output:  prints the corresponding path inside the container, derived from
#              workspaceFolder (or workspaceMount's target= as fallback).
#
#   python3 dc-resolve.py folder-uri <devcontainer-dir> <config-file> <remote-path> <docker-context>
#     Inputs:  devcontainer root on the host, the config file (one per mode),
#              path inside the container, and the active docker context name.
#     Output:  prints the vscode-remote://dev-container+... folder URI that
#              opens <remote-path> in VS Code, in that config's container.
#
#   python3 dc-resolve.py up-container-id
#     Input:   `devcontainer up` JSON on stdin.
#     Output:  its exact containerId.
#
#   python3 dc-resolve.py posture
#     Input:   `docker inspect <container>` JSON on stdin.
#     Output:  the container's security posture, fixed at its creation:
#              "yolo", "normie" or "custom", then internet=, package_access= and
#              seccomp= words, e.g. "yolo internet=firewalled package_access=readonly
#              seccomp=builtin". Anything not verified reads as custom.
#
# Called by _dc_resolve/ybox in devcontainer.zsh; not meant to be run by hand.

import json
import pathlib
import posixpath
import re
import sys
import urllib.parse


def strip_jsonc(src):
    """Remove // and /* */ comments (outside strings) and trailing commas."""
    out = []
    i, n = 0, len(src)
    in_string = False
    while i < n:
        ch = src[i]
        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(src[i + 1])
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            out.append(ch)
        elif ch == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        elif ch == "/" and i + 1 < n and src[i + 1] == "*":
            i = src.find("*/", i + 2)
            if i == -1:
                break
            i += 2
            continue
        else:
            out.append(ch)
        i += 1
    return re.sub(r",\s*([}\]])", r"\1", "".join(out))


def remote_path(devcontainer_json, relative_dir):
    with open(devcontainer_json, encoding="utf-8") as fh:
        config = json.loads(strip_jsonc(fh.read()))

    workspace_folder = config.get("workspaceFolder")
    if not workspace_folder:
        workspace_mount = config.get("workspaceMount", "")
        match = re.search(r"(?:^|,)target=([^,]+)", workspace_mount)
        if not match:
            raise SystemExit(1)
        workspace_folder = match.group(1)

    workspace_folder = posixpath.normpath(workspace_folder)
    return workspace_folder if not relative_dir else posixpath.join(workspace_folder, relative_dir)


def folder_uri(devcontainer_dir, config_file, remote, docker_context):
    config = str(pathlib.Path(config_file))
    authority = {
        "hostPath": devcontainer_dir,
        "localDocker": False,
        "settings": {"context": docker_context},
        "configFile": {
            "$mid": 1,
            "fsPath": config,
            "external": "file://" + urllib.parse.quote(config),
            "path": config,
            "scheme": "file",
        },
    }
    authority_hex = json.dumps(authority, separators=(",", ":")).encode().hex()
    return f"vscode-remote://dev-container+{authority_hex}{urllib.parse.quote(remote, safe='/')}"


def up_container_id(src):
    """Extract containerId, tolerating incidental non-JSON stdout lines."""
    candidates = [src] + list(reversed(src.splitlines()))
    for candidate in candidates:
        try:
            value = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and value.get("containerId"):
            return value["containerId"]
    raise SystemExit("devcontainer up did not return a containerId")


# The two presets ybox creates (--yolo, the default, and --normie).
PRESETS = {
    "yolo": ("firewalled", "readonly", "builtin"),
    "normie": ("open", "writable", "unconfined"),
}


def security_policy(options):
    if not isinstance(options, list):
        return "unverified"
    policies = [item[len("seccomp="):] for item in options
                if isinstance(item, str) and item.startswith("seccomp=")]
    if policies in (["builtin"], ["unconfined"]):
        return policies[0]
    return "unverified"


def package_stack(target):
    if target == "/opt/venv":
        return "python"
    if re.fullmatch(r"/opt/R/[^/]+/lib/R/site-library", target):
        return "r"
    if target == "/usr/local/texlive":
        return "tex"
    return None


def package_access(mounts):
    if not isinstance(mounts, list):
        return "unverified"
    access = {}
    for mount in mounts:
        if isinstance(mount, dict):
            stack = package_stack(mount.get("Destination", ""))
            if stack:
                access[stack] = "writable" if mount.get("RW") else "readonly"
    modes = set(access.values())
    if sorted(access) != ["python", "r", "tex"] or len(modes) != 1:
        return "unverified"
    return modes.pop()


def internet_mode(env):
    """post-start.sh arms the firewall unless YOLOBOX_INTERNET is "open".

    A container created before the rename carries SANDBOX_INTERNET instead,
    which post-start.sh reads when YOLOBOX_INTERNET is absent."""
    if not isinstance(env, list):
        return "unverified"
    for name in ("YOLOBOX_INTERNET", "SANDBOX_INTERNET"):
        values = [item.split("=", 1)[1] for item in env
                  if isinstance(item, str) and item.startswith(name + "=")]
        if values:
            return "open" if values == ["open"] else "firewalled"
    return "firewalled"


def posture(src):
    try:
        inspected = json.loads(src)
    except json.JSONDecodeError:
        inspected = None
    if isinstance(inspected, list) and len(inspected) == 1:
        inspected = inspected[0]
    if not isinstance(inspected, dict):
        return "custom internet=unverified package_access=unverified seccomp=unverified"
    settings = (
        internet_mode((inspected.get("Config") or {}).get("Env")),
        package_access(inspected.get("Mounts")),
        security_policy((inspected.get("HostConfig") or {}).get("SecurityOpt")),
    )
    name = next((mode for mode, preset in PRESETS.items() if preset == settings), "custom")
    return "{} internet={} package_access={} seccomp={}".format(name, *settings)


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "remote-path":
        print(remote_path(sys.argv[2], sys.argv[3]))
    elif command == "folder-uri":
        print(folder_uri(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]))
    elif command == "up-container-id":
        print(up_container_id(sys.stdin.read()))
    elif command == "posture":
        print(posture(sys.stdin.read()))
    else:
        raise SystemExit(f"unknown command: {command}")
