# Extended Setup

Setup beyond the README's [minimal setup](../README.md#minimal-setup) and
[recommended additions](../README.md#recommended-additions). Each section is
optional.

## Using more than one Mac

A yolobox checkout in Dropbox can be used from several Macs, one at a time.
The checkout, the project files and the agents' session logs sync through
Dropbox; credentials, package volumes and containers stay per machine.

### 1. Give each Mac a distinct short name

The container derives a machine id from the Mac's name (`MacStudio25.local`
-> `macstudio25`), and [ai-sesh](../tools/ai-sesh/README.md) keeps each
machine's sessions under `tools/ai-sesh/data/<machine>/`. Set the name under
**System Settings → General → About → Name** before first use, and reopen the
container afterward. Renaming later starts a new, empty store; the old one
stays under its old name.

### 2. Switch desks without losing sessions

Each machine's Claude and Codex sessions sync passively. To continue a
session on the other Mac:

1. Exit the session on the Mac you are leaving.
2. Wait for Dropbox to finish syncing.
3. On the other Mac, in the container, run `sesh-push`, then resume
   (`claude --resume`, `codex resume`, or `gpt-fork` for Codex).

Never run the same session on both Macs at once. See the
[ai-sesh README](../tools/ai-sesh/README.md) for how divergent copies are
handled.

### 3. Share VS Code user settings (optional)

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

### 4. Read container sessions in a host VS Code window (optional)

[AIChatRender](https://github.com/chenandrewy/aichatrender) renders Claude
and Codex sessions in a VS Code panel. In a devcontainer window it reads the
container's own stores and needs no setup. To use it in a local (host) window
instead, point it at the ai-sesh stores, which are ordinary files on the Mac.
In VS Code **user** settings (Preferences: Open User Settings (JSON)), with
the checkout's absolute host path in place of `/ABS/CHECKOUT`:

```jsonc
"aichatrender.claudeTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/macstudio25/claude",
  "/ABS/CHECKOUT/tools/ai-sesh/data/macbook25/claude"
],
"aichatrender.codexTranscriptRoots": [
  "/ABS/CHECKOUT/tools/ai-sesh/data/macstudio25/codex",
  "/ABS/CHECKOUT/tools/ai-sesh/data/macbook25/codex"
],
"aichatrender.pathMappings": [
  { "from": "/yolobox/", "to": "/ABS/CHECKOUT" }
]
```

Replace `macstudio25` and `macbook25` with your machine ids (the folder names
under `tools/ai-sesh/data/`). With separate settings per Mac, listing only
that Mac's store is enough. With a shared settings file (step 3), list every
Mac's store: the settings accept only literal absolute paths, with no `~`,
globs or `${...}`, so one file cannot choose a store per machine. Close and
reopen the panel after changing the settings.

What to expect:

- **Follow Active Terminal Chat** cannot see through the container boundary
  from a host window, so it always opens the picker. Choose **Automatic** to
  follow the most recently modified session in the open folder.
- After `sesh-push`, a session can be listed twice: the other Mac's original
  and this Mac's installed copy. The picker shows each copy's folder. Resuming
  appends to this Mac's copy, so **Automatic** follows the live one; when
  picking by hand, choose the copy under this Mac's `data/<machine>/`.

### Adding another Mac later

1. Give it a short name (step 1) and set up the container as in the README.
2. If VS Code settings are shared, symlink them (step 3) and add the new
   machine's `claude` and `codex` stores to the AIChatRender roots (step 4).
