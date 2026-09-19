# Host-side toolkit

`.host/` is the supported host launcher for this sandbox,
[`.setup/`](../.setup/README.md) is host machine setup and maintenance, and
`.devcontainer/` defines the container.

The functions run on your **Mac**, before Docker creates the container. `bbox`
reads and validates this repo's `SANDBOX.toml`, passes the selected seccomp
policy to the Dev Containers CLI, and then optionally opens a shell or editor.
Launching and managing Claude Code sessions remains a separate personal concern.

## Setup

From the checkout root on the host, run:

```zsh
bash .host/setup.sh
exec zsh
bbox --code
```

Setup locates its own checkout and registers the launcher in
`${ZDOTDIR:-$HOME}/.zshrc`. It backs up existing configuration before changing
it, preserves unrelated shell configuration, and replaces its managed block
when rerun, including after a checkout move or rename. Simple source lines for
this launcher from the previous README are migrated into the managed block.
The block is appended after existing completion setup.

It checks for Python 3, zsh, Docker, the Dev Containers CLI, and the VS Code
`code` command, reporting missing prerequisites without installing software or
starting containers. Python 3 is required to edit the registration. For a custom
rc file or testing, use `bash .host/setup.sh --rc-file PATH`.

## Layout

| File               | Contents                                                    |
|--------------------|-------------------------------------------------------------|
| `setup.sh`         | host prerequisite checks and shell registration             |
| `devcontainer.zsh` | `bbox`, short wrappers, bring-up, and verification        |
| `_bbox`            | side-effect-free native zsh completion                     |
| `dc-resolve.py`    | container-path, CLI-output, and folder-URI helpers          |

Keep these files flat in `.host/`: `devcontainer.zsh` resolves its siblings from
its own path, so another checkout cannot redirect its helpers.

## Functions

| Command | What it does |
|---|---|
| `bbox [dir]` | Bring up the enclosing sandbox. |
| `bbox --shell [dir]` | Bring it up, verify it, and open a shell at that path. |
| `bbox --code [dir]` | Bring it up, verify it, and open that path in VS Code. |
| `bbox --rebuild [dir]` | Recreate the container while retaining Docker's build cache. |
| `bbox --rebuild-without-cache [dir]` | Recreate it with `--build-no-cache`. |

All modes walk up from `dir` (default: the current directory), resolve the
sandbox once, call `devcontainer up`, and inspect the exact returned container.
Reusing an existing container warns if Docker's recorded seccomp policy
differs from `SANDBOX.toml`; if `up` had to create the container, a mismatch
is an error instead, exactly as after a rebuild.
Before either rebuild mode, the launcher refuses if a VS Code window is
connected to any container for the folder (the Dev Containers extension would
otherwise race `devcontainer up` and recreate an `unconfined` container), then
removes every container labeled for the folder so no duplicate survives. The
check looks for a live connection to the in-container VS Code server, which
itself lingers after the window closes. After a rebuild, a mismatch or failed
inspection stops before attachment. `--shell` and `--code` are mutually
exclusive, as are the rebuild flags; an action can be combined with either
rebuild mode.

Changes to `seccomp` require `bbox --rebuild`; plain `bbox` may reuse a running
container. Direct **Dev Containers: Rebuild Container** in VS Code does not
inherit the launcher's environment and therefore uses the `builtin`
default. This matches the checked-in YOLO posture. When
`SANDBOX.toml` selects `unconfined`, use `bbox --rebuild` to apply it.

`bbu`, `bbe`, and `bbcode` are short wrappers around `bbox`, `bbox --shell`,
and `bbox --code`. They contain no separate bring-up logic. The former
`dcu`, `dce`, and `dccode` names are removed on load.

`devcontainer.zsh` sources `_bbox`. Source it after your zsh completion setup;
if `compdef` was unavailable at that point, source `.host/_bbox` again after
`compinit`. Completion reads no configuration and never invokes Docker.

## Claude Code sessions

To start Claude on a project folder in this repo:

```zsh
bbox --shell My-Project    # shell in the container, in that folder
cchat-yolo                 # Claude, remote-controlled, named for the folder
```

`cchat-yolo` is defined in `.devcontainer/shellrc.sh`, so it is available in
every container shell. It always passes `--remote-control` and derives the
session name from the working directory (`My-Project#1`), numbering
each session so a second one in the same folder stays distinguishable. Override
the base name with `CC_SESSION_NAME`. It refuses to start unless the firewall
is enabled and PID 1 has filtered seccomp mode.

Host-side launchers that open a container *and* a Claude session in one command
(`cc-remote-sandbox`, `ccremotes`, plus `ccsessions` / `cckill` for listing and
terminating sessions) are personal configuration and are not shipped here. On
this system they live in `MacUser/Shell-rc/cc-remotes.zsh`.
