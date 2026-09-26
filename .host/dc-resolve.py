# dc-resolve.py — devcontainer path/URI helpers for the dc* shell functions
#
# Run:
#   python3 dc-resolve.py remote-path <devcontainer.json> <relative-dir>
#     Inputs:  path to a devcontainer.json (JSONC allowed), and the project
#              directory's path relative to the devcontainer root ("" for root).
#     Output:  prints the corresponding path inside the container, derived from
#              workspaceFolder (or workspaceMount's target= as fallback).
#
#   python3 dc-resolve.py folder-uri <devcontainer-dir> <remote-path> <docker-context>
#     Inputs:  devcontainer root on the host, path inside the container, and
#              the active docker context name.
#     Output:  prints the vscode-remote://dev-container+... folder URI that
#              opens <remote-path> in VS Code.
#
#   python3 dc-resolve.py up-container-id
#     Input:   `devcontainer up` JSON on stdin.
#     Output:  its exact containerId.
#
#   python3 dc-resolve.py security-policy <docker-security-options-json>
#     Input:   Docker inspect's HostConfig.SecurityOpt JSON array.
#     Output:  builtin, unconfined, or an unverified description.
#
#   python3 dc-resolve.py package-access <docker-mounts-json>
#     Input:   Docker inspect's .Mounts JSON array.
#     Output:  readonly or writable when the python, r and tex package mounts
#              all agree, else an unverified description.
#
#   python3 dc-resolve.py package-volumes <devcontainer.json>
#     Input:   path to a devcontainer.json (JSONC allowed).
#     Output:  one "<stack> <volume> <target>" line each for python, r and tex:
#              the shared package volumes .setup/packages.sh builds. A
#              `// packages.sh: <mount>` comment line stages a volume and
#              overrides the live mount with the same target.
#
# Called by _dc_resolve/bbox in devcontainer.zsh and by .setup/packages.sh;
# not meant to be run by hand.

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


def folder_uri(devcontainer_dir, remote, docker_context):
    config = str(pathlib.Path(devcontainer_dir, ".devcontainer/devcontainer.json"))
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


def security_policy(src):
    try:
        options = json.loads(src)
    except json.JSONDecodeError:
        return "unverified (invalid Docker inspection output)"
    if not isinstance(options, list):
        return "unverified (no explicit seccomp option)"
    policies = [item[len("seccomp="):] for item in options
                if isinstance(item, str) and item.startswith("seccomp=")]
    if policies == ["builtin"]:
        return "builtin"
    if policies == ["unconfined"]:
        return "unconfined"
    if not policies:
        return "unverified (no explicit seccomp option)"
    return "unverified (seccomp=" + ", seccomp=".join(policies) + ")"


def package_stack(target):
    if target == "/opt/venv":
        return "python"
    if re.fullmatch(r"/opt/R/[^/]+/lib/R/site-library", target):
        return "r"
    if target == "/usr/local/texlive":
        return "tex"
    return None


def package_access(src):
    try:
        mounts = json.loads(src)
    except json.JSONDecodeError:
        return "unverified (invalid Docker inspection output)"
    if not isinstance(mounts, list):
        return "unverified (no mounts)"
    access = {}
    for mount in mounts:
        if isinstance(mount, dict):
            stack = package_stack(mount.get("Destination", ""))
            if stack:
                access[stack] = "writable" if mount.get("RW") else "readonly"
    absent = [stack for stack in ("python", "r", "tex") if stack not in access]
    if absent:
        return "unverified (no " + ", ".join(absent) + " package mount)"
    modes = set(access.values())
    if len(modes) == 1:
        return modes.pop()
    return "unverified (mixed: " + ", ".join(f"{s} {access[s]}" for s in ("python", "r", "tex")) + ")"


def parse_mount(spec):
    return dict(part.split("=", 1) for part in spec.split(",") if "=" in part)


def package_volumes(devcontainer_json):
    with open(devcontainer_json, encoding="utf-8") as fh:
        src = fh.read()
    live = [m for m in json.loads(strip_jsonc(src)).get("mounts", []) if isinstance(m, str)]
    staged = re.findall(r"^\s*//\s*packages\.sh:\s*(\S+)\s*$", src, re.MULTILINE)
    volumes = {}
    for spec in live + staged:  # staged last, so it wins
        mount = parse_mount(spec)
        stack = package_stack(mount.get("target", ""))
        if stack and mount.get("type") == "volume":
            volumes[stack] = (mount.get("source", ""), mount["target"])
    lines = []
    for stack in ("python", "r", "tex"):
        if stack not in volumes:
            raise SystemExit(f"package-volumes: no {stack} volume mount in {devcontainer_json}")
        source, target = volumes[stack]
        # A per-devcontainer name is not a shared volume the host should fill.
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", source):
            raise SystemExit(f"package-volumes: {stack} volume {source!r} is not a literal shared name")
        lines.append(f"{stack} {source} {target}")
    return "\n".join(lines)


command = sys.argv[1]
if command == "remote-path":
    print(remote_path(sys.argv[2], sys.argv[3]))
elif command == "folder-uri":
    print(folder_uri(sys.argv[2], sys.argv[3], sys.argv[4]))
elif command == "up-container-id":
    print(up_container_id(sys.stdin.read()))
elif command == "security-policy":
    print(security_policy(sys.argv[2]))
elif command == "package-access":
    print(package_access(sys.argv[2]))
elif command == "package-volumes":
    print(package_volumes(sys.argv[2]))
else:
    raise SystemExit(f"unknown command: {command}")
