# MathPanel

A minimal VS Code webview that shows the current Claude Code or Codex CLI
session transcript — prose as plain text, math rendered by KaTeX — updating
live as the session progresses. It reads the tools' own session transcripts
directly; there is no hook, no HTTP server, and no data store of our own.

Base design and threat model: `docs/journal/0723a,mathpanel-transcript.md`;
Codex v0.2 design: `docs/journal/0723b,codex-mathpanel-plan.md`
(supersedes the hook+inbox design in `0722a,mathpanel-plan.md`; security
motivation in `0721a,MathRender-Risks.md`).

## What it does

- Watches `~/.claude/projects/<munge-of-workspace-cwd>/` plus cwd-matched
  rollouts in the last seven New York date directories, plus tomorrow as a
  cross-time-zone guard, under `~/.codex/sessions/`. It follows the
  most-recently-modified session across both sources and switches automatically
  when either tool writes.
- Shows assistant text and real user prompts, newest 50 messages. Thinking
  blocks, tool calls/results, and harness bookkeeping are skipped.
- Renders `$$…$$`, `\[…\]` (display) and `\(…\)`, `$…$` (inline) via a
  vendored, pinned KaTeX (`extension/media/katex/VENDOR.md`). Everything else —
  including code blocks — is inert plain text (`textContent`; no markdown, no
  HTML).
- Single-`$…$` uses Pandoc-style guards against currency/`$VAR` false
  positives: both `$` on one line, no whitespace just inside the delimiters, no
  digit right after the closing `$`, escaped `\$` ignored.

## Security posture (summary)

- **Read-only**: never writes under `~/.claude/` or `~/.codex/`. Claude
  discovery reads only direct-child `*.jsonl` files for this workspace. Codex
  discovery must read the first line of every rollout in the scanned date
  directories, including other workspaces; those lines can contain base
  instructions, git, and provider metadata. Only `cwd` and the session
  timestamp are cached from each line. Metadata from nonmatching rollouts is
  never logged or sent to the webview; full contents are read only for the one
  selected workspace-matching rollout.
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

The install target (`~/.vscode-server/extensions/local.mathpanel-0.2.0`) is
wiped on container rebuild; rerun the script to restore it. During an upgrade,
the installer removes the superseded `local.mathpanel-0.1.0` folder after the
new copy succeeds.

## Uninstall

```sh
rm -rf ~/.vscode-server/extensions/local.mathpanel-0.2.0
```

Reload the window. Nothing else was created anywhere.

## Tests

```sh
node --test .tools/mathpanel/extension/test/
```

Pure-parser tests (`transcript.js` and `codex.js`) against synthetic fixtures —
no real transcript content is committed.

## v0.2 limitations

- Exactly one workspace folder; sessions started from a subdirectory of the
  workspace do not match that workspace cwd and are not followed.
- There is no source toggle. Across concurrent Claude and Codex sessions, the
  panel follows whichever matching file was modified most recently.
- Codex discovery scans only the last seven date directories. Older rollouts
  outside that window are not followed, even when resumed.
