# Host-side toolkit

`.host/` is the supported host launcher for this sandbox,
[`.setup/`](../.setup/README.md) is host machine setup and maintenance, and
`.devcontainer/` defines the container.

The functions run on your **Mac**, before Docker creates the container. `bbox`
reads and validates this repo's `SANDBOX.toml`, passes the selected seccomp
policy to the Dev Containers CLI, and then optionally opens a shell or editor.
Launching and managing Claude Code sessions remains a separate personal concern.

## Layout

| File               | Contents                                                    |
|--------------------|-------------------------------------------------------------|
| `devcontainer.zsh` | `bbox`, compatibility wrappers, bring-up, and verification |
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
Reuse warns if Docker's recorded seccomp policy differs from `SANDBOX.toml`.
After either rebuild mode, a mismatch or failed inspection stops before
attachment. `--shell` and `--code` are mutually exclusive, as are the rebuild
flags; an action can be combined with either rebuild mode.

Changes to `seccomp` require `bbox --rebuild`; plain `bbox` may reuse a running
container. Direct **Dev Containers: Rebuild Container** in VS Code does not
inherit the launcher's environment and therefore uses the safe `builtin`
default, even if `SANDBOX.toml` selects `unconfined`. Use `bbox --code` for the
TOML-driven creation and attachment path.

`dcu`, `dce`, and `dccode` remain as deprecated wrappers around `bbox`,
`bbox --shell`, and `bbox --code`. They contain no separate bring-up logic.

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
the base name with `CC_SESSION_NAME`.

Host-side launchers that open a container *and* a Claude session in one command
(`cc-remote-sandbox`, `ccremotes`, plus `ccsessions` / `cckill` for listing and
terminating sessions) are personal configuration and are not shipped here. On
this system they live in `MacUser/Shell-rc/cc-remotes.zsh`.
