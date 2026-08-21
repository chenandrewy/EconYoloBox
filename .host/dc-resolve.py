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
# Called by _dc_resolve/dccode in devcontainer.zsh; not meant to be run by hand.

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


command = sys.argv[1]
if command == "remote-path":
    print(remote_path(sys.argv[2], sys.argv[3]))
elif command == "folder-uri":
    print(folder_uri(sys.argv[2], sys.argv[3], sys.argv[4]))
else:
    raise SystemExit(f"unknown command: {command}")
