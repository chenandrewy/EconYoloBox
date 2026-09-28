# Host-side toolkit

`infra/host/` is the supported host launcher for this yolobox,
[`infra/setup/`](../setup/README.md) is provisioning you run by hand (package
volumes and AI CLIs, in the container), and `.devcontainer/` is
the container itself: its definition, its startup, and the tools baked into
it.

The functions run on your **Mac**, before Docker creates the container. `ybox`
picks the mode's container (YOLO by default, normie with `--normie`), brings
it up with the Dev Containers CLI, verifies it, and then optionally opens a
shell or editor.
Launching and managing Claude Code sessions remains a separate personal concern.

## Setup

From the checkout root on the host, run:

```zsh
bash infra/host/setup.sh
exec zsh
ybox --code
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
rc file or testing, use `bash infra/host/setup.sh --rc-file PATH`.

## Layout

| File               | Contents                                                    |
|--------------------|-------------------------------------------------------------|
| `setup.sh`         | host prerequisite checks and shell registration             |
| `devcontainer.zsh` | `ybox`, short wrappers, bring-up, and verification        |
| `_ybox`            | side-effect-free native zsh completion                     |
| `_ybcode`          | zsh completion for the VS Code wrapper                     |
| `dc-resolve.py`    | container-path, CLI-output, and folder-URI helpers          |

Keep these files flat in `infra/host/`: `devcontainer.zsh` resolves its siblings from
its own path, so another checkout cannot redirect its helpers.

## Functions

| Command | What it does |
|---|---|
| `ybox [dir]` | Bring up the enclosing yolobox's YOLO container. |
| `ybox --normie [dir]` | Bring up its normie container. `--yolo` names the default explicitly. |
| `ybox --shell [dir]` | Bring it up, verify it, and open a shell at that path. |
| `ybox --code [dir]` | Bring it up, verify it, and open that path in VS Code. |
| `ybox --stop [dir]` | Stop the mode's container (`--normie` for the normie one). |
| `ybox --status [dir]` | Report both containers and their modes; change nothing. |
| `ybox --rebuild [dir]` | Recreate both modes' containers, keeping Docker's build cache, then bring up the chosen mode's. |
| `ybox --rebuild-without-cache [dir]` | The same with `--build-no-cache`. |

`bbu`, `bbe`, and `ybcode` are short wrappers around `ybox`, `ybox --shell`,
and `ybox --code`, and take the same flags: `ybcode --normie`, `bbe --yolo`.
They contain no separate bring-up logic. The former `dcu`, `dce`, and
`dccode`, `bbox`, and `bbcode` names are removed on load.

Each mode is its own container, built from its own config file, which
hard-codes its posture:

| Mode | Config | Internet | Package volumes | Seccomp |
|---|---|---|---|---|
| YOLO (default, `--yolo`) | `.devcontainer/devcontainer.json` | firewalled | read-only | `builtin` |
| normie (`--normie`) | `.devcontainer/normie/devcontainer.json` | open | writable | `unconfined` |

The Dev Containers tooling keys a container on its folder and config file
(the `devcontainer.local_folder` and `devcontainer.config_file` labels), so
the two coexist: the flag only picks which one `ybox` brings up and attaches
to, and neither ever replaces the other. `ybox` passes `--config` to
`devcontainer up` and `devcontainer exec`, and the same config goes into the VS
Code folder URI. A VS Code **Rebuild Container** or **Reopen in Container**
therefore rebuilds the same mode. Containers for the folder with any other
config label are not `ybox`'s and are left alone. The two containers share
one set of per-checkout volumes (logins, the AI CLIs, shell history), which
is why a checkout's folder name must be unique on the Docker daemon (see the
[container README](../.devcontainer/README.md#working-modes)).

All modes walk up from `dir` (default: the current directory) and resolve the
yolobox once. `ybox` then calls `devcontainer up` for the mode's config and
inspects the exact returned container. If another container of the same mode
exists, it refuses (a rebuild removes the extra). If the container is not in
its config's posture, as with containers made before the per-mode configs,
it stops before attachment and names the rebuild that fixes it. Otherwise it
prints the mode, and a YOLO bring-up also mentions a running normie
container, whose firewall is open until something stops it.

A rebuild recreates both modes' containers, since the configs are twins and
a change that needs one rebuilt needs the other too; a container left on the
old config fails later, and confusingly. The mode flag only picks the one
brought up and attached to at the end. The other mode is recreated first, and
only if it has a container: a rebuild never creates a mode you have not used.
If that container was not running, it is stopped again afterwards, so a
rebuild never leaves an idle normie container running with its firewall open.
Before removing anything, the launcher refuses if a VS Code window is
connected to a container of either mode. The check looks for a live
connection to the in-container VS Code server, which itself lingers after the
window closes. VS Code's own **Rebuild Container** still rebuilds only the
window's mode.
`--shell`, `--code`, `--stop` and `--status` are mutually exclusive, as are
the rebuild flags and the mode flags; `--status` takes no other option, and
`--stop` only a mode flag.

In the normie container the mode stays visible: `normie:` at the front of the
VS Code window title, a `normie` tag at the front of the zsh prompt and
Claude's status line, and a warning banner in every new shell.

`devcontainer.zsh` sources `_ybox` and `_ybcode`. Source it after your zsh
completion setup; if `compdef` was unavailable at that point, source both
completion files again after `compinit`. Completion reads no configuration and
never invokes Docker.

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
