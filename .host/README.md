# Host-side toolkit

Shell functions that run on your **Mac** (not inside the container) to navigate
the dev containers in this repo. Everything the container needs at runtime lives
in `.devcontainer/`; this folder is only the host-side convenience layer, kept
here so the sandbox can be shared standalone.

Scope is deliberately narrow: **navigation only**. These functions take no
configuration, name no personal paths, and work against any repo with a
`.devcontainer/devcontainer.json` — not just this one. Launching and managing
Claude Code sessions (`cc-remote-*`, `ccsessions`, `cckill`) is a personal,
machine-level concern and lives in the machine-settings repo instead; see
"Claude Code sessions" below.

## Layout

| File               | Contents                                                    |
|--------------------|-------------------------------------------------------------|
| `devcontainer.zsh` | `dcu`, `dce`, `dccode`, and the shared `_dc_resolve`        |
| `dc-resolve.py`    | container-path / folder-URI resolution helper               |

Keep these two files flat in `.host/`: `devcontainer.zsh` derives `$_DC_HOST_DIR`
from its own `$0` and expects `dc-resolve.py` as a sibling. Deriving it that way
(rather than from a caller) means a second checkout sourced into the same shell
can never make this one read the other's helper.

## Functions

| Command        | What it does                                                  |
|----------------|---------------------------------------------------------------|
| `dcu`          | `devcontainer up` for the current directory.                  |
| `dce [dir]`    | Open an interactive shell inside the enclosing dev container, cd'd to the subfolder matching `dir`. |
| `dccode [dir]` | Open that same subfolder in VS Code inside the container.     |

Both `dce` and `dccode` walk *up* from `dir` (default: the current directory) to
the enclosing `.devcontainer/devcontainer.json`, then map the host path to its
container-side equivalent — so they work from anywhere in the tree, with no
manual "Reopen in Container" and no navigating after attach.

## Claude Code sessions

To start Claude on a project folder in this repo:

```zsh
dce My-Project             # shell in the container, in that folder
cchat-yolo                 # Claude, remote-controlled, named for the folder
```

`cchat-yolo` is defined in `.devcontainer/shellrc.sh`, so it is available in
every container shell. It always passes `--remote-control` and derives the
session name from the working directory (`My-Project#1`), numbering
each session so a second one in the same folder stays distinguishable. Override
the base name with `CC_SESSION_NAME`.

Host-side launchers that open a container *and* a Claude session in one command
(`cc-remote-sandbox`, `ccremotes`, plus `ccsessions` / `cckill` for listing and
terminating sessions) are personal configuration and are not shipped here. On
this system they live in `MacUser/Shell-rc/cc-remotes.zsh`.
