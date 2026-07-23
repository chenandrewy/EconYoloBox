# MathPanel

A minimal VS Code webview that shows the transcript of the current Claude Code
session — prose as plain text, math rendered by KaTeX — updating live as the
session progresses. It reads Claude Code's own session transcript directly;
there is no hook, no HTTP server, and no data store of our own.

Design and threat model: `docs/journal/0723a,mathpanel-transcript.md`
(supersedes the hook+inbox design in `0722a,mathpanel-plan.md`; security
motivation in `0721a,MathRender-Risks.md`).

## What it does

- Watches `~/.claude/projects/<munge-of-workspace-cwd>/` and follows the
  most-recently-modified session `*.jsonl` (switches automatically when a new
  session starts or you `--resume` an old one).
- Shows assistant text and real user prompts, newest 50 messages. Thinking
  blocks, tool calls/results, and harness bookkeeping are skipped.
- Renders `$$…$$`, `\[…\]` (display) and `\(…\)` (inline) via a vendored,
  pinned KaTeX (`extension/media/katex/VENDOR.md`). Everything else — including
  code blocks — is inert plain text (`textContent`; no markdown, no HTML).
- Single-`$…$` is deliberately not treated as math (currency/`$VAR` false
  positives).

## Security posture (summary)

- **Read-only**: never writes under `~/.claude/`; reads only the direct-child
  `*.jsonl` files of the one project directory for this workspace.
- **No network**: no HTTP listener, socket, port, or CDN request. KaTeX is
  vendored and served through VS Code's internal webview channel.
- **No second copy**: no inbox, no history file — the panel re-reads the
  existing transcript on load.
- **No XSS surface**: prose reaches the DOM only via `textContent`; only math
  source text reaches KaTeX (`trust:false`, `throwOnError:false`); strict CSP
  with nonce'd scripts; fail-soft on any malformed record.

## Install (inside the devcontainer)

```sh
.tools/mathpanel/install-extension.sh
```

Then reload the VS Code window (`Developer: Reload Window`) and run
**MathPanel: Show** from the Command Palette. The extension runs
container-side (`"extensionKind": ["workspace"]`).

The install target (`~/.vscode-server/extensions/local.mathpanel-0.1.0`) is
wiped on container rebuild; rerun the script to restore it.

## Uninstall

```sh
rm -rf ~/.vscode-server/extensions/local.mathpanel-0.1.0
```

Reload the window. Nothing else was created anywhere.

## Tests

```sh
node --test .tools/mathpanel/extension/test/
```

Pure-parser tests (`transcript.js`) against synthetic fixtures — no real
transcript content is committed.

## v0.1 limitations

- Exactly one workspace folder; sessions started from a subdirectory of the
  workspace land in a different project directory and are not followed.
- Concurrent sessions in the same directory: the panel follows whichever file
  was modified most recently.
