# Host-side toolkit

`.host/` is the supported host launcher for this sandbox,
[`.setup/`](../.setup/README.md) is provisioning you run by hand (package
volumes and AI CLIs, in the container), and `.devcontainer/` is
the container itself: its definition, its startup, and the tools baked into
it.

The functions run on your **Mac**, before Docker creates the container. `bbox`
picks the security posture (YOLO mode by default, normie mode with
`--normie`), passes it to the Dev Containers CLI, verifies the resulting
container, and then optionally opens a shell or editor.
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
| `bbox [dir]` | Bring up the enclosing sandbox in YOLO mode. |
| `bbox --normie [dir]` | Bring it up in normie mode. `--yolo` names the default explicitly. |
| `bbox --shell [dir]` | Bring it up, verify it, and open a shell at that path. |
| `bbox --code [dir]` | Bring it up, verify it, and open that path in VS Code. |
| `bbox --status [dir]` | Report the container's mode; change nothing. |
| `bbox --rebuild [dir]` | Recreate the container while retaining Docker's build cache. |
| `bbox --rebuild-without-cache [dir]` | Recreate it with `--build-no-cache`. |

`bbu`, `bbe`, and `bbcode` are short wrappers around `bbox`, `bbox --shell`,
and `bbox --code`, and take the same flags: `bbcode --normie`, `bbe --yolo`.
They contain no separate bring-up logic. The former `dcu`, `dce`, and
`dccode` names are removed on load.

The modes are two fixed presets, set when the container is created:

| Mode | Internet | Package volumes | Seccomp |
|---|---|---|---|
| YOLO (default, `--yolo`) | firewalled | read-only | `builtin` |
| normie (`--normie`) | open | writable | `unconfined` |

`bbox` exports them to `devcontainer up` as `SANDBOX_INTERNET`,
`SANDBOX_PKG_READONLY` and `SANDBOX_SECCOMP`, and reads a container's mode
back from `docker inspect` (its environment, mounts and security options).
`SANDBOX.toml` plays no part.

All modes walk up from `dir` (default: the current directory), resolve the
sandbox once, and inspect any container already labeled for it. If that
container is in another mode, `bbox` recreates it; the image and the named
volumes survive, but everything running in the container ends. With no flag,
that is a question, asked only on a terminal (elsewhere `bbox` refuses): the
flagless default is YOLO mode, so `bbe` into a normie container asks before
replacing it, and `bbe --normie` attaches to it as it is. An explicit flag is
the answer, so `bbcode --yolo` switches without asking. Either way, a switch
refuses while a VS Code window is connected to the container; close it first.

Then `bbox` calls `devcontainer up` and inspects the exact returned container.
If it is not in the requested mode, `bbox` stops before attachment. When it
is, `bbox` prints the mode.

Before a rebuild or a switch, the launcher refuses if a VS Code window is
connected to any container for the folder (the Dev Containers extension would
otherwise race `devcontainer up` and recreate a YOLO container), then
removes every container labeled for the folder so no duplicate survives. The
check looks for a live connection to the in-container VS Code server, which
itself lingers after the window closes. `--shell`, `--code` and `--status`
are mutually exclusive, as are the rebuild flags and the mode flags;
`--status` takes no other option.

Direct **Dev Containers: Rebuild Container** in VS Code does not inherit the
launcher's environment and therefore always gives YOLO mode. Use
`bbox --rebuild --normie --code` to rebuild in normie mode.

Inside the container, the mode stays visible outside YOLO mode: a red VS Code
title and status bar with `NORMIE MODE` in the window title, a `normie` tag
at the front of the zsh prompt and Claude's status line, and a banner in every
new shell.

`devcontainer.zsh` sources `_bbox`. Source it after your zsh completion setup;
if `compdef` was unavailable at that point, source `.host/_bbox` again after
`compinit`. Completion reads no configuration and never invokes Docker.

## Claude Code sessions

To start Claude on a project folder in this repo:

```zsh
bbe My-Project             # shell in the container, in that folder
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
