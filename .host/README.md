# Host-side toolkit

Shell functions that run on your **Mac** (not inside the container) to launch
and manage the 1-SANDBOX dev container and Claude Code sessions. Everything the
container needs at runtime lives in `.devcontainer/`; this folder is only the
host-side convenience layer, kept here so the sandbox can be shared standalone.

## Install

Add one line to your interactive shell rc (`~/.zshrc`), pointing at wherever you
cloned this repo:

```zsh
source /path/to/1-SANDBOX/.host/host-aliases.zsh
```

Reload the shell (`exec zsh`) and you have the functions below.

### Requirements

- [Docker](https://www.docker.com/) running
- the [`devcontainer` CLI](https://github.com/devcontainers/cli)
  (`npm i -g @devcontainer/cli`)
- macOS **Terminal.app** for the `window` launchers (or override the launcher —
  see below). `dccode` additionally needs the `code` CLI on PATH.

## Configuration

Paths are plain shell globals (**not** exported — they are only read inside the
functions, so nothing leaks into child processes). Set any that differ from the
defaults *before* the `source` line:

| Global             | Default                                              | Used by            |
|--------------------|------------------------------------------------------|--------------------|
| `CC_SANDBOX_DIR`   | this repo (auto-derived from the file's location)    | `cc-remote-sandbox`|
| `CC_OBSIDIAN_VAULT`| `Main`                                               | `cc-remote-obs`    |
| `CC_OBSIDIAN_DIR`  | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/$CC_OBSIDIAN_VAULT` | `cc-remote-obs` |
| `CC_DROPBOX_DIR`   | `~/Library/CloudStorage/Dropbox`                     | `cc-remote-dropbox`|

`CC_SANDBOX_DIR` needs no configuration — it resolves to this repo's checkout, so
`cc-remote-sandbox` works out of the box. The Obsidian/Dropbox remotes are
personal targets; point them at your own paths (or ignore them). Use Dropbox's
real install folder, not a `~/Dropbox` symlink, so resolution never depends on a
link that may not exist yet.

## Functions

| Command                | What it does                                                        |
|------------------------|---------------------------------------------------------------------|
| `cc-remote-sandbox`    | Bring the sandbox container up, run Claude in it, current terminal. |
| `cc-remote-obs`        | Same, for the Obsidian vault container.                             |
| `cc-remote-dropbox`    | Run Claude on the host (not a container), cd'd into Dropbox.        |
| `ccremotes`            | Launch all three, each in its own new terminal window.              |
| `ccsessions`           | List every `--remote-control` Claude session across containers.     |
| `cckill`               | Terminate every `--remote-control` Claude session.                  |
| `dcu`                  | `devcontainer up` for the current directory.                        |
| `dce [dir]`            | Open an interactive shell inside the enclosing dev container.       |
| `dccode [dir]`         | Open the enclosing dev container's folder in VS Code.               |

### Safety note

`--dangerously-skip-permissions` (yolo mode) is passed **only** for
`target_env=container` launches, where the container is the blast radius.
`target_env=local` (e.g. `cc-remote-dropbox`) runs unsandboxed against your real
`$HOME`, so it keeps Claude's default permission prompting. This invariant lives
in `_cc_remote` — one place, keyed off the target, not duplicated per mode.

## Using a different terminal

The `window` launchers call `_cc_open_window <title> <command>`, which defaults
to Terminal.app. Override it in your own rc *after* the `source` line to drive
another terminal. Example for [Ghostty](https://ghostty.org/):

```zsh
_cc_open_window() {
  local title="$1" cmd="$2"
  # -n forces a fresh instance (else `open` just focuses the running one and
  # drops -e); --window-save-state=never stops that instance restoring saved
  # windows; --title pins the title; `zsh -ic` gives -e the interactive PATH.
  open -na Ghostty.app --args --title="$title" --window-save-state=never -e zsh -ic "$cmd"
}
```
