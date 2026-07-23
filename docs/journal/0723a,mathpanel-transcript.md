# MathPanel (transcript-reader design): render Claude Code math live from the session transcript

**Date:** 2026-07-23
**Status:** plan agreed, nothing built yet. Supersedes the hook+inbox design in
`0722a,mathpanel-plan.md` (kept for history). Security motivation:
`0721a,MathRender-Risks.md`.

MathPanel is a VS Code webview that shows the **full assistant transcript** of a
Claude Code session — prose as plain text, math rendered by KaTeX — updating live
as the session progresses. It reads Claude Code's own session transcript file
directly. There is no companion hook, no HTTP server, and no data store of our
own.

## Core decisions

1. **Read the transcript directly.** The extension watches Claude Code's session
   JSONL under `~/.claude/projects/` and renders it. No Stop hook, no
   `~/.claude/settings.json` edit, no second copy of the conversation. The
   transcript already exists at mode 600; we only ever read it.
2. **Full text, math rendered — nothing else rendered.** Non-math prose is plain
   escaped text (`textContent`); math spans go to KaTeX. No markdown,
   bold/headers/links, or syntax highlighting. Prose never reaches the DOM as
   HTML.
3. **Read-only, fail-soft.** The extension never writes to the transcript or
   anywhere under `~/.claude/`. Any record it can't understand is skipped, never
   fatal — worst case is a missing line, never corruption.
4. **No network, no listener.** KaTeX is vendored and loaded via `asWebviewUri`;
   there is no HTTP server, socket, port, or CDN request at runtime.
5. **Container-side, plain JS.** `"extensionKind": ["workspace"]` so the
   extension runs in the container alongside Claude Code and the transcript.
   Plain JavaScript — no TypeScript, no `npm install`, no `node_modules`. The
   sole third-party artifact is a pinned, checksummed KaTeX tarball.
6. **Install by folder copy.** Copy `extension/` into the container's
   `~/.vscode-server/extensions/`. No vsce, no marketplace, no `.vsix`.
   Uninstall = remove that folder. Nothing else is touched.

### Why no hook and no inbox

The `0722a` design routed the transcript through a Stop hook into an inbox file
we owned. That required editing `~/.claude/settings.json`, a write-side (locking,
rotation), and — critically — a **second at-rest copy** of the conversation. The
0721 incident was fundamentally about a duplicate transcript store being exposed.
Reading the existing file directly means there is no duplicate to protect, no
lifecycle to tear down, and nothing to leave behind on uninstall. The cost is a
dependency on Claude's internal transcript format (see Parsing contract); we
accept it because the read is fail-soft and easy to repair when the format moves.

## Name

`mathpanel` — distinct from upstream `mathrender` so nothing collides with its
residue (`~/.mathrender/`, port 18573, marketplace id).

## Accepted threat model

- The extension reads only the direct `*.jsonl` children of the **single**
  project directory it computes for the current workspace (see Discovery) — not
  `~/.claude/projects/**` recursively. It never reads `~/.claude/settings.json`,
  credentials, or anything else under `~/.claude/`.
- It never writes anywhere under `~/.claude/`.
- Rendered transcript content reaches the desktop only through VS Code's internal
  extension→webview channel. MathPanel creates no HTTP listener, socket, CDN
  request, or browser-readable endpoint.
- Transcript content is the user's own, already on the container disk at mode
  600. MathPanel adds no new at-rest copy. Same-user processes, container root,
  and host/Docker admins can already read the transcript; that is accepted local
  exposure, unchanged by this tool.
- Cross-session and cross-project aggregation within the container is accepted
  (the panel follows the active session; other sessions' files remain readable to
  the same user regardless).

### Against the 0721 audit checklist

1. Binds `127.0.0.1` or `0.0.0.0`? — **binds nothing.**
2. Sets `Access-Control-Allow-Origin: *`? — **no HTTP exists.**
3. Any GET route returns conversation content? — **no routes, no server; and no
   second copy of the transcript is created.**

## Transcript source

### Location and discovery

Claude Code writes one JSONL file per session:

```
~/.claude/projects/<project-munge>/<session-uuid>.jsonl
```

**Munge rule (verified 2026-07-23 against all 21 project dirs on this machine):**
take the session cwd and replace **every non-alphanumeric character** with `-`,
**literally, per character — no run-collapsing**. So `_` → `-`, `,` → `-`, `.`
→ `-`, `/` → `-`, and a double `__` becomes a double `--` (e.g.
`/workspace/Ref,JEconom` → `-workspace-Ref-JEconom`;
`/tmp/pdf2md__logotr_` → `-tmp-pdf2md--logotr-`). Implement as a per-char map,
**not** `re.sub(r'[^a-z0-9]+', '-')` (the `+` would wrongly collapse runs).
Undocumented and version-dependent, so fail-soft if the computed dir is absent.
Unverified edge: Claude reportedly truncates paths beyond ~200 chars and appends
an internal hash — not exercised here (longest real path ≈ 80 chars); handle by
falling back to the "no session found" state rather than guessing.

#### Independence from ai-sesh

On this machine `~/.claude/projects` is a **symlink** into the ai-sesh store
(`/workspace/.tools/ai-sesh/data/<host>/claude`). MathPanel does **not** depend
on that and must never reference ai-sesh, its store layout, or the resolved
target:

- Always use the **logical** path `os.homedir()/.claude/projects/...` and let the
  kernel resolve the symlink on each access. **Never `realpath` the `projects`
  symlink and cache the result** — caching the resolved ai-sesh path is the only
  thing that would couple us to it, and it would break when the store moves.
- Because we re-open the logical path every poll, an ai-sesh sync that swaps the
  target underneath us is handled for free — it looks like a transient `ENOENT`
  or an inode change, both already covered by the fail-soft reader.
- If ai-sesh were removed and `projects` became a real directory, the tool would
  behave identically. The dependency is on Claude Code's canonical transcript
  location, nothing else.

(The `realpath` we *do* use is on the **workspace folder**, to match how Claude
munges the cwd — see below. That is unrelated to the `projects` symlink.)

#### Active-session discovery loop (v0.1)

- Support **exactly one** workspace folder. If there are zero or more than one,
  show a clear "unsupported workspace" notice and do nothing else.
- Resolve that workspace folder with `fs.realpathSync`, then compute its
  `<project-munge>` directory under the logical `~/.claude/projects/`.
  - **Build-time check:** confirm Claude munges the *realpath* of the cwd and not
    the literal cwd string. Every dir on this machine has `cwd == realpath(cwd)`,
    so the two can't be distinguished from current data; a symlinked workspace
    component would diverge. Default to realpath (as here) but verify once.
- Every ~1 s: `readdir` that project directory and `stat` its **direct-child**
  `*.jsonl` files (no recursion). Select the **non-empty** file with the newest
  `mtimeMs`; break ties deterministically by filename.
  - Directory-mtime is *not* a usable signal: appending to a non-selected session
    bumps that file's mtime but not the directory's, so a switch to an existing
    session (e.g. `claude --resume`) would be missed. Hence the periodic full
    stat scan.
- If the selected path changes: `fs.unwatchFile` the old file, clear its reader
  state, `fs.watchFile` the new file, and rebuild from its tail.
- Between discovery scans, `fs.watchFile` (500–1000 ms) on the selected file
  drives live updates.
- If the project directory or any transcript is absent, show "No Claude session
  found for this workspace" and keep polling.
- Sessions started from a **subdirectory** land in a different munge dir and are
  out of scope for v0.1 (see Open questions). Concurrent sessions resolve to
  most-recent-mtime, which is accepted (with the caveat that a background/agent
  session writing in the same dir could momentarily steal focus).

### Record shape (observed 2026-07-23, current session)

One JSON object per line; every record carries `type` and `version`. Types seen:
`assistant`, `user`, `attachment`, `system`, `mode`, `permission-mode`,
`ai-title`, `last-prompt`, `file-history-snapshot`, `file-history-delta`.

What we consume:
- **`type == "assistant"`** → `message.content` is an array of blocks. Keep only
  blocks with `type == "text"`. **Skip `thinking` and `tool_use`.**
- **`type == "user"`** *(only if user turns are enabled — off by default, see
  Open questions)* → keep only when `message.content` is a **string** (a real
  prompt). Skip user records whose content is an array / that carry
  `toolUseResult` — those are tool results, not prompts.
- Everything else (bookkeeping types) → skip.

In the sample session, assistant `text` blocks were 17 of 187 lines — expect the
transcript to be mostly non-text bookkeeping and tool traffic.

### Reading strategy (incremental, with whole-file fallback)

Claude appends to the transcript; it may also replace it (e.g. compaction). Track
`(inode, size)` for the followed file:
- Change with **same inode and grown size** → read only the appended bytes, parse
  newly completed lines, buffer any trailing partial line until its newline
  arrives.
- **Inode changed or size shrank** (new session, compaction) → re-read the whole
  file and rebuild.

Two cheap robustness guards on the line reader (hygiene, not DoS defense — the
transcript is trusted local data; this just keeps a giant tool-result line or a
crash-truncated file from being wasted work):
- **Length check before `JSON.parse`.** We already split on newlines; skip any
  line longer than **256 KiB** without parsing it. That clears the 128 KiB
  message cap comfortably, so no real assistant message is lost, while giant
  `toolUseResult` lines (observed >1 MiB) are dropped without decoding. One line
  of code; makes "we don't choke on a huge line" an explicit property.
- **Cap the partial-line buffer.** If the trailing (not-yet-newline-terminated)
  buffer ever exceeds ~**512 KiB**, discard it and resync at the next newline.
  Guards the one realistic version of "unbounded growth": a corrupt or
  crash-truncated final record. Fits the fail-soft stance.

Not doing: a chunked streaming reader with a discard-until-newline state machine.
At these scales (≤~2 MiB files, ~1 s polling, ms-scale `JSON.parse`) it optimizes
a cost that rounds to zero, and 64 KiB chunking adds a UTF-8-split footgun. The
two guards above are the whole worthwhile subset.

Poll with `fs.watchFile` (500–1000 ms) rather than raw `fs.watch` — it handles
creation, replacement, and truncation uniformly on the one platform we run
(Linux, in-container). `fs.unwatchFile` on deactivate and whenever we switch
files. Always stat/open the **logical** path each cycle (no cached fd or resolved
realpath), so a target swapped by ai-sesh sync surfaces as a normal inode-change
or transient `ENOENT` and is handled by the rules above — never a silent stale
read.

## Parsing contract

- Segmentation of a text block into ordered spans lives in a **pure module**
  (`transcript.js`, no `vscode` imports) so it is unit-testable under `node:test`.
- Each kept `text` block becomes a message = an ordered list of spans:
  - fenced and inline code → **text** spans (shown, never scanned for math);
  - `$$…$$` and `\[…\]` → **display-math** spans;
  - `\(…\)` → **inline-math** spans;
  - everything else → **text** spans.
- **Fail-soft:** a record with an unexpected shape (missing `message`, non-array
  `content`, unknown block type) is skipped, never fatal. Malformed/partial JSON
  lines are skipped individually.
- **Version awareness:** read each record's `version`. If a record's shape does
  not match what we parse, skip it and surface a single non-blocking panel notice
  ("Some records were skipped — Claude Code format may have changed") rather than
  silently rendering nothing.
- Content is never logged to stdout/stderr.

### In-memory message shape

```js
// one per kept assistant text block, newest-last
{ ts: "2026-07-23T14:05:00-04:00", role: "assistant",
  spans: [ {t:"text", s:"By "}, {t:"math", m:"inline", s:"E=mc^2"}, … ] }
```

`ts` from the record's `timestamp`, displayed in New York time.

## Resource limits

| Limit | Value |
|---|---|
| Text kept per message | 128 KiB (truncate beyond, with a visible notice) |
| Single math span | 8,192 chars |
| Math spans per message | 64 |
| Messages retained in panel | newest 50 |
| Max JSONL line parsed | 256 KiB (longer lines skipped before `JSON.parse`) |
| Max partial-line buffer | ~512 KiB (discard + resync at next newline) |
| Bytes re-read on whole-file rebuild | last 4 MiB of the file (tail) if larger |
| KaTeX | `trust:false`, `throwOnError:false`, `maxExpand:1000`, `maxSize:20` |

Truncation behaviors, deliberately different:
- **Prose over the message cap** → truncate, append a visible text marker
  (`[message truncated: size limit]`). Truncated prose is still inert text.
- **A math span over its cap** → *drop* it, optionally show a plain-text notice
  ("Formula omitted: size limit exceeded"). Never render a truncated formula as
  valid.

## UI: command-only WebviewPanel

- Contribute one command `mathpanel.show`; explicit activation event
  `onCommand:mathpanel.show`.
- Singleton `WebviewPanel` in `ViewColumn.Beside`; reveal the existing panel if
  open; set the reference to `undefined` on dispose.
- On (re)open, wait for the webview's `ready` message, then send the current
  history.
- No activity-bar container, tree view, welcome view, or sidebar icon in v0.1.
  A real sidebar via `WebviewViewProvider` is a later option.

## Webview security contract

- `enableScripts: true`; `localResourceRoots` = extension `media/` only; no
  command URIs.
- All KaTeX js/css/font URLs via `asWebviewUri`; no CDN, no runtime network.
- CSP: `default-src 'none'; connect-src 'none'; base-uri 'none';
  form-action 'none'`; scripts only from the webview source with a per-document
  nonce; **no `'unsafe-inline'` for scripts**; `font-src` = webview source.
- KaTeX emits inline `style` attributes, so styles need a narrow allowance:
  CSP3 `style-src-attr 'unsafe-inline'` with a restricted `style-src-elem`, or
  fall back to `style-src <webview-source> 'unsafe-inline'`.
- Ready handshake: webview installs its listener → sends `{type:"ready"}` →
  extension replies `{type:"replaceHistory", entries:[…]}`; later refreshes reuse
  the same replacement message (avoids duplicate/rotation bookkeeping).
- Rendering: iterate each message's spans in order. Text spans → create an
  element, set `textContent` (CSS `white-space: pre-wrap` so newlines/indent
  survive). Math spans → `katex.render(span.s, el, {displayMode: span.m==="display", …})`.
  Errors/omissions via `textContent`. **Never `innerHTML`, never HTML string
  building.** Validate every message and span (`t`/`m`/`s` types) before touching
  the DOM.
- Because prose is inert `textContent` and only math text reaches KaTeX, the
  webview has no transcript-driven XSS surface.

## Folders and files

### In the repo (committed)

```
.tools/mathpanel/
├── README.md                     # what it is, install, uninstall, threat model
├── install-extension.sh          # idempotent copy → ~/.vscode-server/ (~25 ln)
└── extension/
    ├── package.json              # name/version, publisher "local",
    │                             #   "main": "./extension.js",
    │                             #   "extensionKind": ["workspace"],
    │                             #   activationEvents: ["onCommand:mathpanel.show"],
    │                             #   contributes: one command, no view container
    ├── extension.js              # vscode glue (~180 ln): session discovery,
    │                             #   fs.watchFile follow, incremental read,
    │                             #   singleton WebviewPanel, replaceHistory
    ├── transcript.js             # PURE module (~120 ln): parse records → keep
    │                             #   assistant text → segment into spans →
    │                             #   enforce limits. No vscode import.
    ├── test/
    │   └── transcript.test.js    # node:test against synthetic fixtures
    ├── fixtures/
    │   └── *.jsonl               # SMALL SYNTHETIC records mirroring the observed
    │                             #   schema — never real transcript content
    └── media/
        ├── index.html            # webview (~160 ln): CSP+nonce, ready-handshake,
        │                         #   iterate spans, textContent/katex.render
        └── katex/                # vendored, pinned — the ONE third-party dep
            ├── VENDOR.md         # version, URL, integrity, sha256, NY date, cmd
            ├── LICENSE           # KaTeX MIT license text (redistribution req.)
            ├── katex.min.js
            ├── katex.min.css
            └── fonts/            # every font referenced by katex.min.css
```

No Python anywhere — the whole tool is one JS extension plus vendored KaTeX.

### Created at runtime (container, not committed)

```
~/.vscode-server/extensions/local.mathpanel-0.1.0/
                                  # install target; wiped on container rebuild,
                                  #   restored by install-extension.sh
```

MathPanel creates **no** files under `~/.mathpanel/` or elsewhere — it only reads
the existing transcript.

## Data flow

```
Claude Code session  →  ~/.claude/projects/<munge>/<uuid>.jsonl  (append)
  → extension.js: ~1s discovery scan picks newest-mtime *.jsonl in the munge dir
      (switch files if the selection changed; logical path, never cached realpath)
  → extension.js: fs.watchFile on the selected file fires
      · (inode,size) grew  → read appended bytes, parse new complete lines
        inode changed/shrank → re-read (tail ≤4 MiB) and rebuild
        ENOENT (sync swap / rotation) → keep polling, rebuild when it returns
  → transcript.js: keep assistant text blocks → segment into spans → enforce limits
  → replace in-memory history (newest 50) → postMessage {type:"replaceHistory"}
  → index.html: iterate spans; text→textContent (pre-wrap); math→katex.render;
      never innerHTML
```

No listener, no port, no CDN, no second copy of the data.

## Installer (idempotent, narrow)

`install-extension.sh`:
- `set -eu`; resolve source relative to the script, not the caller's cwd.
- Verify `extension/package.json` and `extension/extension.js` exist.
- Target exactly `~/.vscode-server/extensions/local.mathpanel-0.1.0`.
- `rm -rf` that exact target, then `cp -r extension/.` into it; safe to run twice
  with identical result.
- Print that the user must reload the VS Code window.
- Never edit `extensions.json`, `.obsolete`, Claude settings, or devcontainer
  config.

Installation is an environment change — run only when the user explicitly asks to
build/install MathPanel.

## Uninstall

1. Remove the `local.mathpanel-0.1.0` extension directory.
2. Reload the VS Code window (terminates any running instance).
3. Confirm no MathPanel extension directory remains.

There is no hook to unregister, no inbox to delete, and no server/shutdown flush
to verify — nothing of ours persists outside the extension folder.

## Tests

- **`transcript.test.js`** (`node:test`, built in — no install): record filtering
  (assistant `text` only; skip `thinking`/`tool_use`); user prompt vs
  tool-result discrimination; span segmentation (display/inline/text, code kept
  as text and never math-scanned); limits (message truncation, math-span drop);
  fail-soft on unknown record shapes and partial JSON lines. Runs against small
  **synthetic** fixtures — never committed real transcript content.
- **KaTeX smoke test**: render normal formulas and a few hostile inputs
  (`\href{javascript:…}`, `\htmlData`, huge `\def`) against the vendored bundle;
  assert inert output or a caught error.
- **Manual integration**: install → reload → open panel on an active session with
  math; verify live update as new turns arrive; switch sessions (new file) and
  confirm the panel follows; VS Code restart rebuilds from the transcript;
  `lsof -nP -iTCP -sTCP:LISTEN` identical before/after (no listening socket).

## KaTeX vendor record

`media/katex/` must contain `VENDOR.md`, the exact KaTeX `LICENSE`,
`katex.min.js`, `katex.min.css`, and every font the CSS references. `VENDOR.md`
records: exact version (never a range or "latest"); exact tarball URL; npm
integrity value if available; computed SHA-256 of the tarball; New York
acquisition date; exact command used; which files were copied. The first checksum
anchors *this build's* artifact; on later rebuilds, compare the download against
it before extracting.

## Build order (when we build)

1. Fetch + verify KaTeX tarball (`npm pack katex@<pin>` — download only, runs no
   lifecycle scripts; registry.npmjs.org is firewall-allowed), record in
   `VENDOR.md`, vendor files + LICENSE into `media/katex/`. ← only network step.
2. **Confirm the remaining transcript conventions** against real files in
   `~/.claude/projects/`. The munge rule is verified (21/21 dirs, per-char
   non-alnum→`-`); still to confirm: realpath-vs-literal-cwd for the munge, the
   >200-char truncate+hash edge, the assistant-`text` / `thinking` / `tool_use`
   block split, and the user prompt-vs-tool-result distinction. Capture a couple
   of *synthetic* fixtures modeled on them (never commit real transcript content).
3. Write `transcript.js`, `transcript.test.js`, `extension.js`, `package.json`,
   `index.html`, `install-extension.sh`, `README.md`.
4. `node --test` (or `node test/transcript.test.js`) green.
5. Run `install-extension.sh`, reload window, open the panel on a live session
   with math; confirm live rendering and session-follow.
6. Negative checks: `lsof` listener table unchanged; hostile KaTeX inputs inert;
   corrupt/partial transcript lines skipped without breaking the panel.

## Open questions (decide during build)

- **User prompts in the panel?** Default off (assistant text only). Turning it on
  is cheap (the prompts are `str`-content `user` records), but decide whether the
  assistant-only view reads as disjointed.
- **Thinking blocks?** Skipped in v0.1. Could be an opt-in toggle later; they
  often contain math but are noisier and more sensitive.
- **Subdirectory sessions.** v0.1 follows only the window-cwd munge dir. Widen to
  sibling munge dirs if sessions started in subfolders are commonly wanted.
- **KaTeX version pin** (latest 0.16.x at build; upstream MathRender used
  0.16.11).
- **Single-`$…$`** stays out of v0.1 (currency / shell-var false positives; code
  is already kept as text and never math-scanned). Revisit only if real inline
  math is missed.

## Not doing

- No Stop hook, no `~/.claude/settings.json` edit, no inbox or any file of our
  own, no second copy of the transcript.
- No `npm install`, TypeScript, vsce, or marketplace publishing.
- No HTTP server, socket, port, or CDN request.
- No markdown/rich rendering of prose; non-math is plain `textContent` only.
- No writes anywhere under `~/.claude/`.
- No contact with the upstream MathRender repo (no fork, issue, or PR).
- Upstream reference copy at `/workspace/MathRenderer/` stays unexecuted; delete
  once this rewrite is stable.
