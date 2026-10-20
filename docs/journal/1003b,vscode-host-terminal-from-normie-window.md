# Host terminal from the normie VS Code window: ctrl+t binding, cd attempts

Date: 2026-10-03. Messy notes. Follows 1003a (normie window as viewer, run
ybcc from a host terminal inside it).

## Finding the command

"Terminal: Create New Integrated Terminal (Local)" =
workbench.action.terminal.newLocal. Didn't show up when searching
"new terminal host" - title says Local, not host. Only exists in remote
windows. Works from the `ybcode --normie` window.

With user setting terminal.integrated.defaultLocation = "editor" it opens in
the editor area already, no moveToEditor needed.

## Bottom panel pops up

newLocal always ends with groupService.showPanel(true) (read it in
workbench.desktop.main.js, VS Code app bundle). Opening an empty terminal
panel in a remote window auto-creates a container zsh (normie banner).
Not caused by defaultLocation. No postAttachCommand / tasks.json involved.

## WORKED: ctrl+t binding (MacUser repo, commit 920c288)

~/Dropbox/MacUser/VSCode/keybindings.json (symlinked into
~/Library/Application Support/Code/User/):

```jsonc
{ "key": "ctrl+t", "command": "runCommands",
  "args": { "commands": ["workbench.action.terminal.newLocal",
                         "workbench.action.closePanel"] },
  "when": "remoteName != ''" }
```

- first tried shift+alt+t, too awkward. ctrl+t: no conflicts in MacUser
  configs; mac default ctrl+t = transpose letters in editors, only
  overridden in remote windows. In a focused terminal ctrl+t probably goes to
  the shell (runCommands not in commandsToSkipShell) - click an editor first.
- closePanel only hides; the panel's container shell keeps running.

## Problem: local terminal starts in 1-SANDBOX, not the opened folder

Window had /yolobox/workshop/Photo-Labeler open; host shell lands in the ybox
root. Why:
- newLocal: cwd = getCanonicalURI(last active workspace root), fallback
  userHome.
- Dev Containers ext (0.469.0) resolver getCanonicalURI decodes hostPath from
  the authority and returns Uri.file(hostPath). Ignores the URI path.
- dc-resolve.py folder-uri puts the ybox root in hostPath (must - it
  identifies the container / .devcontainer). Subfolder is only in the
  remote path.
- no cd in host zsh startup.

Can't pass a host cwd from a keybinding: createTerminal only goes local when
cwd is a URI object with scheme file; keybinding args are JSON strings.

## FAILED: sendSequence cd as third command

Attempt 1: newLocal, sendSequence, closePanel. Text
` p='${workspaceFolder}'; cd "$PWD$p[9,-1]" && clear` (zsh subscript strips
"/yolobox", no ${} so VS Code's resolver leaves it alone; leading space +
histignorespace keeps it out of history).
-> variable resolved fine (/yolobox/workshop/Photo-Labeler) but the text
went to the CONTAINER shell in the bottom panel (showPanel makes it the
active instance). cd failed with doubled path. Danger: if an agent was
running there, the line gets typed into its prompt.

Attempt 2: newLocal, closePanel, focusActiveEditorGroup, sendSequence, with
a `[[ $PWD != /yolobox* ]]` guard.
-> text now targets the local terminal, but VS Code error "Variable
workspaceFolder can not be resolved. Please open a folder." Resolution is
relative to the active terminal; a local terminal's cwd isn't under any
(remote) workspace folder.

Catch-22: container terminal active = variable resolves, wrong shell; local
terminal active = right shell, no variable. ${workspaceFolder:Name} would
work but hard-codes one project. Reverted to the 2-command binding
(uncommitted edits discarded, back to 920c288).

## Left as is / maybe later

- cd by hand; ybcc DIR takes the folder anyway.
- if wanted: ybcode records the opened subfolder somewhere, host zsh reads it
  when TERM_PROGRAM=vscode. Breaks with several ybcode windows (last wins).

## Side cleanup same session (MacUser)

- removed Cursor/ settings, its link rows in link-user-settings.sh, README
  line (commit 9afd5f5). App support dir, ~/.cursor, cursor-agent moved to
  ~/.Trash/cursor-removed-20261003/.
- removed 3 cursor.* keys from VSCode/settings.json - uncommitted, file has
  other pending edits.

## Later: per-project devcontainers? No.

Idea: .devcontainer in Photo-Labeler -> hostPath = Photo-Labeler -> local
terminal opens there. Evaluated, not worth it:
- ybox walks up to nearest .devcontainer, so the project becomes the root.
  Could likely keep one shared config via --config with hostPath = project
  (untested), so no copied .devcontainer.
- heavy volumes (R lib, venv, texlive) already shared by name. Per-basename
  ones multiply: codex-config 2.4G, vscode-extensions 0.9G, npm-global 0.6G,
  claude-config 29M, bashhistory -> ~4G/project, plus logins, extension
  installs, CLI updates, rebuilds per project. Rename = orphaned volumes.
- up to 2 containers per project (normie needed for viewer trick).
- BLOCKER for Photo-Labeler: not its own git repo (root is 1-SANDBOX; same
  for dev/, Other/). Container would mount no .git. Most other workshop/
  folders are their own repos.
- upside would be real per-project YOLO isolation. Maybe someday, opt-in,
  for standalone repos only. Not for a cd.

## AIChatRender: transcripts are ALREADY on the host (ai-sesh)

1003a missed this. tools/ai-sesh: sesh-init (every container shell) symlinks
~/.claude/projects and ~/.codex/sessions -> /yolobox/tools/ai-sesh/data/
<machine>/{claude,codex}. That's the bind mount, so live transcripts are
real files on the Mac, e.g.
1-SANDBOX/tools/ai-sesh/data/macstudio25/claude/-yolobox-workshop-Photo-Labeler/*.jsonl
(checked: recent ones there, modified within the last 2h). git-ignored, Dropbox-synced.

So the "host-side AIChatRender" option is cheap - no new mount. Needs in
AIChatRender (v0.6.1, active-terminal.js / extension.js):
1. extra transcript roots setting -> ai-sesh/data/<this machine>/{claude,codex}
2. path map /yolobox -> host checkout (project key -yolobox-..., and cwd
   inside transcripts)
3. follow: why it fails now - follow uses terminal.processId and walks the
   process tree for open .jsonl / ~/.claude/sessions/<pid>.json. In the
   normie window the ext runs in the container but the terminal pid is a Mac
   pid; and claude itself runs in YOLO anyway. On host: ybcc runs on host,
   can write hostShellPid -> sessionId (claude --session-id) to a host file
   YOLO can't touch. Or just "newest transcript" if one session at a time.
   Codex: probably no preset session id -> newest.

Wins: plain local VS Code window, no normie viewer running all day with the
relay. Original cd problem gone (open Photo-Labeler locally, normal
terminal). Per-mode ~/.claude volumes (1003a fix 3) no longer kill the
viewer since both modes write ai-sesh/data via the bind mount.

Risk: host-side ext renders YOLO-written files. But host already reads YOLO
files all the time (Dropbox, host VS Code + extensions on the whole
workspace, host git, Claude on host). Not a new category. Real diff:
AIChatRender is a small custom renderer (less hardened than VS Code
built-ins), and transcripts hold arbitrary outside text (fetched pages,
command output). Check: escapes everything, strict webview CSP, tolerates a
half-written last line.

Current lean: host-side AIChatRender beats the normie-viewer workaround.
Discussion only, nothing built.

## AIChatRender is public - keep it generic

Worry: host-side support ties the public extension to EconYoloBox. Answer:
make it generic settings, EconYoloBox only supplies values. The general
problem: agent runs in a container/remote, transcripts land somewhere the
editor can read, under paths that don't match the editor's.

Settings (all default empty -> no change for existing users):
1. aichatrender.extraTranscriptRoots - more dirs to scan besides
   ~/.claude/projects and ~/.codex/sessions.
2. aichatrender.pathMappings - [{from: "/yolobox", to: "${workspaceFolder}"}],
   applied to project keys (-yolobox-...) and transcript cwd. Same idea as
   debugger sourceFileMap / localRoot+remoteRoot.
3. follow:
   - generic fallback: newest transcript when the process-tree lookup finds
     nothing.
   - optional "session hints" dir: any launcher writes terminalPid ->
     sessionId. ybcc would be one writer; also useful for ssh/tmux. Later.

EconYoloBox values live in 1-SANDBOX/.vscode/settings.json, e.g. root
${workspaceFolder}/tools/ai-sesh/data/<machine>/claude + the /yolobox
mapping. Extension never names ybox. Wrinkle: <machine> - glob data/*
(also shows other machines' synced sessions) or have ybox setup write it.
Extension has to resolve ${workspaceFolder} itself (VS Code doesn't
substitute in arbitrary extension settings).

Security: workspace settings are repo files -> YOLO-editable -> could aim
the host ext at arbitrary dirs (read-only, .jsonl only, low stakes). Fix:
"scope": "machine" (user settings only), or list under
capabilities.untrustedWorkspaces.restrictedConfigurations.

Lean: ship 1 + 2 + newest-fallback, generic. Session hints only if parallel
sessions make "newest" pick wrong. Discussion only.

Tension I glossed over: "scope": "machine" means the values can't live in
1-SANDBOX/.vscode/settings.json - they'd go in host user settings
(MacUser/VSCode/settings.json), keyed by path so they only apply to this
checkout. restrictedConfigurations keeps workspace settings working in
trusted workspaces, but YOLO edits a trusted workspace. Pick one; leaning
user settings.
