# Host-side toolkit

This directory implements the host `yolobox` command and its eight shortcuts.
For the command table, examples, agent permissions, and container management,
see the [Yolobox command guide](../../docs/commands.md). The
[root README](../../README.md#one-interface-two-modes) introduces the interface.

## Setup

From the checkout root on the host, run:

```zsh
bash .devcontainer/host/setup.sh
exec zsh
yolobox --code
```

Setup locates its own checkout and registers the launcher in
`${ZDOTDIR:-$HOME}/.zshrc`. It backs up existing configuration before changing
it, preserves unrelated shell configuration, and replaces its managed block
when rerun, including after a checkout move or rename. Simple source lines for
this launcher from the previous README are migrated into the managed block.
This includes the former `infra/host/` registration. After this directory move,
rerun setup and open a new shell before using the launcher.
The block is appended after existing completion setup.

It checks for Python 3, zsh, Docker, the Dev Containers CLI, and the VS Code
`code` command, reporting missing prerequisites without installing software or
starting containers. Python 3 is required to edit the registration. For a custom
rc file or testing, use `bash .devcontainer/host/setup.sh --rc-file PATH`.

## Layout

| File | Responsibility |
|---|---|
| `setup.sh` | Check host prerequisites and register the launcher in zsh. |
| `devcontainer.zsh` | Parse `yolobox` arguments, resolve directories, start and verify containers, and define shell/editor shortcuts. |
| `agents.zsh` | Define agent shortcuts, enforce shortcut modes, construct agent commands, and provide help and agent completion. |
| `_yolobox` | Complete the full command's actions, modes, and directories. |
| `_ybcode` | Complete shell and editor shortcuts. |
| `dc-resolve.py` | Handle container paths, CLI output, posture, and VS Code folder URIs. |
| `find-python.sh` | Locate Python for host initialization. |
| `write-local-env.sh` | Record host name, checkout path, and time zone for the container. |
| `ybe-gptchatyolo` | Preserve the older standalone entry point by forwarding to `ybgpt`. |

Keep these files flat: `devcontainer.zsh` resolves its siblings from its own
path, so another checkout cannot redirect its helpers. It sources `agents.zsh`
and both completion files. Shell and editor shortcuts and agent shortcuts all
call `_yb_shortcut`, which fixes their mode and action before invoking
`yolobox`. Agent actions use `_yb_agent_command` to construct the command run
in the container shell.

Source `devcontainer.zsh` after zsh completion initialization. If `compdef` was
unavailable when it loaded, source `devcontainer.zsh` again after `compinit`.
Completion reads no configuration and never invokes Docker.

## Functions

See [actions and shortcuts](../../docs/commands.md#actions-and-shortcuts) and
[container management](../../docs/commands.md#container-management) for the
public interface. `yolobox --help` exposes the same command families locally.

## Agent commands

See [agent permissions](../../docs/commands.md#agent-permissions) and
[directories and arguments](../../docs/commands.md#directories-and-agent-arguments).
Use the host launchers from a host terminal or local VS Code window; the
[GitHub auth documentation](../README.md#github-auth) explains VS Code's
credential relay when attaching to a container.

## Container identity and verification

Dev Containers identifies a container by its checkout folder and config file
(the `devcontainer.local_folder` and `devcontainer.config_file` labels).
`yolobox` passes the selected config to both `devcontainer up` and
`devcontainer exec`, and includes it in the VS Code folder URI. Containers for
other config files are left alone.

The launcher inspects the exact container ID returned by `devcontainer up`.
It refuses duplicate containers for one mode, a stale mount layout, or a
posture that does not match the selected mode. Rebuilds clear duplicates and
recreate existing modes; see the [rebuild behavior](../../docs/commands.md#container-management).
Before rebuilding, the launcher checks for active connections to the
in-container VS Code server, which can keep running after a window closes.

Both modes share per-checkout volumes. A checkout's folder name must therefore
be unique on the Docker daemon; see [working modes](../README.md#working-modes).
The host time zone is detected automatically; see
[timezone configuration](../README.md#timezone) to override it.

## Tests

Run from the checkout root:

```sh
zsh .devcontainer/host/tests/test-yolobox.zsh
zsh .devcontainer/host/tests/test-agents.zsh
python3 .devcontainer/host/tests/test-setup.py
```

These tests use mocked container commands and temporary files. They check
container selection and verification, shortcut and full-command equivalence,
argument quoting, permission conflicts, exit status, completions, and shell
registration migration without starting real containers or agents.

## Claude Code sessions

`ybcc` uses the container's `cchat-yolo` wrapper. See
[host versus container commands](../../docs/commands.md#host-versus-container-commands)
for remote-control naming and `CC_SESSION_NAME`.

Additional session tools (`cc-remote-sandbox`, `ccremotes`, `ccsessions`, and
`cckill`) are personal configuration and are not shipped here. On the author's
system they live in `MacUser/Shell-rc/cc-remotes.zsh`.
