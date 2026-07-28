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
  rollouts in the last seven date directories under `~/.codex/sessions/`, plus
  tomorrow as a cross-time-zone guard. Those directories are named for the
  *local* date of whichever machine wrote them, so the scan follows the host
  zone. It follows the most-recently-modified session across both sources and
  switches automatically when either tool writes.
- **MathPanel: Follow Active Terminal Chat** switches immediately to the
  transcript held open by the active terminal's process tree and pins that
  selection. If the terminal cannot be matched (for example, an idle CLI has
  closed its transcript), a picker lists the workspace's recent chats. Choose
  **Automatic** in that picker to resume following the newest transcript.
- Shows assistant text and real user prompts, newest 50 messages. Thinking
  blocks, tool calls/results, and harness bookkeeping are skipped.
- Renders `$$…$$`, `\[…\]` (display) and `\(…\)`, `$…$` (inline) via a
  vendored, pinned KaTeX (`extension/media/katex/VENDOR.md`). A small Markdown
  subset covers headings, bulleted and numbered lists, blockquotes, horizontal
  rules, bold/italic text, and inline/fenced code. Raw HTML and Markdown links
  remain inert text.
- Copies rendered equations as their original LaTeX source, including when a
  selection mixes prose and formulas, using KaTeX's pinned `copy-tex`
  extension.
- Single-`$…$` uses Pandoc-style guards against currency/`$VAR` false
  positives: both `$` on one line, no whitespace just inside the delimiters, no
  digit right after the closing `$`, escaped `\$` ignored.

## Security posture (summary)

- **Read-only**: never writes under `~/.claude/` or `~/.codex/`. Claude
  automatic discovery reads only direct-child `*.jsonl` files for this
  workspace. **Follow Active Terminal Chat** may additionally read the
  PID-keyed Claude state record under `~/.claude/sessions/` and the exact
  transcript it names, after validating that its real cwd is inside the
  workspace. Codex discovery must read the first line of every rollout in the
  scanned date directories, including other workspaces; those lines can
  contain base instructions, git, and provider metadata. Only `cwd` and the
  session timestamp are cached from each line. Metadata from nonmatching
  rollouts is never logged or sent to the webview; full contents are read only
  for the one selected workspace-matching rollout.
- **No network**: no HTTP listener, socket, port, or CDN request. KaTeX is
  vendored and served through VS Code's internal webview channel.
- **No second copy**: no inbox, no history file — the panel re-reads the
  existing transcript on load.
- **No XSS surface**: the Markdown subset creates only fixed DOM elements and
  assigns prose through `textContent` or text nodes; raw HTML is never parsed.
  Only math source reaches KaTeX (`trust:false`, `throwOnError:false`); strict
  CSP with nonce'd scripts; fail-soft on any malformed record.

## Install (inside the devcontainer)

The devcontainer's `postStartCommand` automatically synchronizes MathPanel into
the VS Code Server extension directory. If the installed copy is already
current, the check is a no-op. To synchronize it immediately without restarting
the container, run `.tools/mathpanel/install-extension.sh`.

After a changed copy is installed, reload the VS Code window
(`Developer: Reload Window`) if MathPanel does not appear, then run
**MathPanel: Show** from the Command Palette. The extension runs container-side
(`"extensionKind": ["workspace"]`).

The install target (`~/.vscode-server/extensions/local.mathpanel-0.2.0`) is
wiped on container rebuild and restored automatically on the next start. During
an upgrade, the installer removes the superseded `local.mathpanel-0.1.0` folder
after the new copy succeeds.

## Uninstall

```sh
rm -rf ~/.vscode-server/extensions/local.mathpanel-0.2.0
```

Also remove MathPanel from the devcontainer's `postStartCommand`, or it will be
restored on the next start. Reload the window. Nothing else was created
anywhere.

## Tests

```sh
node --test .tools/mathpanel/extension/test/*.test.js
```

Pure-parser tests (`transcript.js` and `codex.js`) against synthetic fixtures —
no real transcript content is committed.

## v0.2 limitations

- Exactly one workspace folder. Automatic discovery does not follow sessions
  started from a subdirectory, but **Follow Active Terminal Chat** can select
  an active Claude session whose real cwd is inside the workspace.
- There is no source toggle. Across concurrent Claude and Codex sessions, the
  panel follows whichever matching file was modified most recently unless a
  chat was explicitly pinned with **Follow Active Terminal Chat**.
- Active-terminal detection uses Linux `/proc`, as provided by the
  devcontainer. Some idle CLI processes close their transcript file; in that
  case the command asks the user to select the chat.
- Codex discovery scans only the last seven date directories. Older rollouts
  outside that window are not followed, even when resumed.
