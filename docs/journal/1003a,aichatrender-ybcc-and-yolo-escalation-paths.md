# AIChatRender vs ybcc, and YOLO -> normie/host escalation paths

Date: 2026-10-03. Messy notes from a discussion. Nothing edited or tested.
Follows docs/journal/1002a (git separation plan), branch feat/yolo-separation
(commit 7bea995 added ybcc/ybcodex/nbcc/nbcodex in .devcontainer/host/agents.zsh).

## Problem

Goal (1002a): gh / GitHub write access in normie, none in YOLO. Mechanism:
never attach VS Code to YOLO (attaching starts the credential relay sockets in
/tmp), run YOLO agents via `devcontainer exec` (ybe / ybcc) from a host terminal.

But AIChatRender is `extensionKind: ["workspace"]` -> only runs inside an
attached window, reads ~/.claude/projects and ~/.codex/sessions *there*.
- Local (unattached) window: extension runs on Mac, reads Mac ~/.claude.
  Container transcripts are in docker volumes; cwd is /yolobox/... so wouldn't
  match the host workspace path anyway.
- Follow Active Terminal Chat (active-terminal.js) walks the terminal's
  process tree for open .jsonl fds. ybcc chain is host zsh -> devcontainer exec
  -> container zsh -> claude, crosses docker boundary. Never matches.

## Workaround chosen to try: normie window as viewer

Both configs mount the SAME `${basename}-claude-config` and `-codex-config`
volumes (devcontainer.json:132-133 in both), workspaceFolder /yolobox in both.
So a window attached to normie sees YOLO transcripts with matching cwd.

Workflow:
- `ybcode --normie` = the one window (editor, AIChatRender panel)
- host shell inside that window: Command Palette ->
  "Terminal: Create New Integrated Terminal (Local)"
  (workbench.action.terminal.newLocal). Starts in ~ probably, so cd or
  `ybcc DIR`.
- can move it into editor area: "Terminal: Move Terminal into Editor Area"
  (workbench.action.terminal.moveToEditor). Possible one-key binding in host
  keybindings.json, untested:
  ```jsonc
  { "key": "ctrl+alt+`", "command": "runCommands",
    "args": { "commands": ["workbench.action.terminal.newLocal",
                           "workbench.action.terminal.moveToEditor"] } }
  ```
- normie agents: just run in the normal (container) terminal of that window;
  Follow Active Terminal works there.

To verify:
- panel auto-follows a ybcc session (newest transcript under /yolobox)
- clickable links in a local terminal inside a remote window: relative and
  /yolobox/... paths. unknown which side resolves them.

Costs: Follow Active Terminal lost for YOLO sessions (use picker). normie
container runs all day, firewall open. normie window has the VS Code relay ->
host GitHub credential reachable from any normie process (1002a table already
accepts "VS Code attached to normie: relay unchanged"); makes per-session
GH_TOKEN for `ybe --normie` mostly moot while the window is open.

Rejected / later:
- ybcode (YOLO) as viewer: brings the relay back. no.
- in-container `ybcc` alias run in an attached YOLO window terminal: same. no.
- host-side AIChatRender: bind-mount ~/.claude/projects + ~/.codex/sessions to
  a non-Dropbox host dir, add AIChatRender settings for extra transcript roots
  + path map /yolobox -> host checkout. Cleaner long term, two repos, YOLO
  writes files the host editor reads.
- Follow-terminal across containers: launcher picks `claude --session-id`
  on host, writes terminal-pid -> session map host-side, extension reads it.
  Claude only. fiddly.

## Q: can a YOLO agent open a host terminal?

### Attached YOLO window: very likely yes (unverified)

VS Code treats the remote server as trusted. Code in the remote extension host
can executeCommand workbench commands incl. terminal.newLocal +
terminal.sendSequence -> shell on the Mac. Getting code into the ext host:
extensions volume is readonly in YOLO (good) but ~/.vscode-server/bin (server
JS) sits on the writable overlay, ubuntu-owned. Assume doable.
=> another reason never to attach to YOLO. Idea: plain `ybcode` should refuse
YOLO unless explicit; warn when /tmp/vscode-remote-containers-ipc-*.sock
appears in YOLO (1002a already suggests).

### Normie window + ybcc: no direct path, but shared writable state

YOLO can't reach normie's VS Code server (different container). But it can
plant things that run later with more privilege:

| YOLO writes | runs later in | effect |
|---|---|---|
| .devcontainer/** (initializeCommand, host/devcontainer.zsh) | host: next ybox/ybe/ybcc, next host shell | host code exec. already documented docs/features.md ~L88 "not a security boundary", review = git diff |
| .git/hooks/* (shared worktree) | normie or host on commit/push | runs with GitHub creds |
| npm-global volume (claude/codex binaries, rw in YOLO, devcontainer.json:142) | normie next agent start | code in normie: open firewall, relay, GH_TOKEN |
| ~/.claude, ~/.codex shared volumes (settings hooks etc.) | normie agents | same, until startup re-seed |

Note ybcc runs `devcontainer up` every launch -> initializeCommand on the host
every launch. More frequent than before.

Rows 2-4 undercut the gh separation: YOLO never holds the token but can get
code run by something that does.

### Fix ideas (not done)

1. npm-global readonly in YOLO, CLI updates only in normie (like extensions).
   Clearest win.
2. core.hooksPath -> root-owned empty dir in normie image's system gitconfig
   and host global gitconfig. NOT in repo .git/config (YOLO can rewrite).
   Also .git/config can carry filters, core.fsmonitor, etc. -> other
   code-exec knobs; review before pushing.
3. per-mode ~/.claude / ~/.codex volumes. Cost: login per mode, AND kills the
   AIChatRender normie-viewer trick above (YOLO transcripts no longer
   visible). Tension. Alternative: keep shared, rely on root-owned managed
   settings to block non-managed hooks (check Claude docs for a managed-only
   hooks setting; Codex equivalent?).
4. ybcc warns if `git diff -- .devcontainer` nonempty / unreviewed.
   accident guard only.

Open: does fix 3 vs viewer trick force the host-side AIChatRender route
eventually? Possibly share only the transcript subdirs between modes (separate
config volumes, shared projects/sessions mount) - but transcripts aren't code,
so sharing them read-only into normie might be fine. Think about it.
