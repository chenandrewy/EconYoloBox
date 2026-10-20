# Extended Setup

Setup beyond the README's [minimal setup](../README.md#minimal-setup) and
[recommended additions](../README.md#recommended-additions). Each section is
optional.

## Using more than one Mac

A yolobox checkout in Dropbox can be used from several Macs, one at a time.
The checkout, the project files and the agents' session logs sync through
Dropbox; credentials, package volumes and containers stay per machine.

### 1. Switch desks without losing sessions

Every Mac's Claude and Codex sessions land in one shared store,
`tools/ai-sesh/data/` (see [ai-sesh](../tools/ai-sesh/README.md)). To
continue a session on the other Mac:

1. Exit the session on the Mac you are leaving.
2. Wait for Dropbox to finish syncing.
3. On the other Mac, in the container, resume it (`claude --resume` from the
   same project folder, or `codex resume <id>`).

Never run the same session on both Macs at once. If that happens, Dropbox
keeps both versions as a conflicted copy; see the
[ai-sesh README](../tools/ai-sesh/README.md#operating-rule).

### 2. Share VS Code user settings (optional)

To keep one VS Code `settings.json` and `keybindings.json` for every Mac, keep
them in Dropbox and symlink them into each Mac's VS Code user folder. On each
Mac, with VS Code closed, move any existing files aside first:

```zsh
cd ~/Library/Application\ Support/Code/User
mv settings.json settings.json.bak
mv keybindings.json keybindings.json.bak
ln -s ~/Library/CloudStorage/Dropbox/<folder>/settings.json settings.json
ln -s ~/Library/CloudStorage/Dropbox/<folder>/keybindings.json keybindings.json
```

Absolute paths in a shared file must be valid on every Mac. They are only if
each Mac has the same macOS username, since the Dropbox folder lives under
your home folder. Otherwise keep separate per-machine settings files.

### 3. Read container sessions in a host VS Code window (optional)

[AIChatRender](https://github.com/chenandrewy/aichatrender) renders Claude
and Codex sessions in a VS Code panel. In a devcontainer window it reads the
container's own stores and needs no setup. To use it in a local (host) window
instead, point it at the ai-sesh stores, which are ordinary files on the Mac.
In VS Code **user** settings (Preferences: Open User Settings (JSON)), with
the checkout's absolute host path in place of `/ABS/CHECKOUT`:

```jsonc
"aichatrender.claudeTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/claude"
],
"aichatrender.codexTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/codex"
],
"aichatrender.pathMappings": [
  { "from": "/yolobox/", "to": "/ABS/CHECKOUT" }
]
```

The settings accept only literal absolute paths, with no `~`, globs or
`${...}`. Every Mac shares the same store, so one shared settings file
(step 2) works on all of them if the checkout path is the same. Close and
reopen the panel after changing the settings.

**Follow Active Terminal Chat** cannot see through the container boundary
from a host window, so it always opens the picker. Choose **Automatic** to
follow the most recently modified session in the open folder.

### Adding another Mac later

Set up the container as in the README; its first shell links it to the
shared session store. If VS Code settings are shared, symlink them (step 2).
