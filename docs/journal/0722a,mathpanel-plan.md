# MathPanel: plan for a safe local replacement of MathRender

**Date:** 2026-07-22
**Status:** plan agreed, nothing built yet. Revised after a code review
(2026-07-22) — accepted parts folded in; scope-inflating parts trimmed.
Revised again 2026-07-23: the panel shows the **full assistant transcript**
(prose + rendered math), not just extracted equations. This reverses the
"formulas only" data-at-rest decision — see §Decisions #8.
**Context:** follow-up to `0721a,MathRender-Risks.md`. Upstream repo is off
limits for interaction (author location); local rewrite instead of local patch.
Reference copy of upstream source sits at `/workspace/MathRenderer/` (zip,
unzipped, never executed) — used for ideas only, MIT-licensed.

## Decisions (settled in conversation 2026-07-22)

1. **Rewrite, not patch.** Essential logic is ~400 lines; patching keeps
   1,700 lines of someone else's code we can't track upstream.
2. **Full text, math rendered — nothing else rendered.** The panel shows the
   whole assistant message: non-math prose as plain escaped text, math spans
   rendered by KaTeX. No markdown rendering, no `marked`, no HTML from
   transcripts, no bold/headers/links/syntax-highlighting. Prose always reaches
   the DOM through `textContent`; only math text is ever handed to KaTeX. So the
   webview XSS posture is identical to the formulas-only design — the only thing
   that grows is what's stored (see #8).
3. **No HTTP server.** File handoff instead: hook appends a JSON record, the
   extension polls the file with `fs.watchFile`. Kills the entire
   localhost/browser attack class from the 0721 audit (CORS, cross-origin
   POSTs, port squatting) by construction.
4. **No npm install, ever.** Plain JavaScript extension (no TypeScript, no
   compile, no `node_modules`). Sole third-party artifact is a pinned,
   checksummed KaTeX tarball fetched via `npm pack katex@<pin>` (tarball
   download only — runs no lifecycle scripts; registry.npmjs.org is
   firewall-allowed) or the GitHub release tarball.
5. **No vsce, no marketplace, no .vsix.** Install = copy the extension folder
   into the container's `~/.vscode-server/extensions/`. ("Option 1.")
6. **Runs container-side.** `"extensionKind": ["workspace"]` in package.json.
   Hook and extension share the container filesystem; webview assets are
   tunneled to the desktop UI by VS Code itself (`asWebviewUri`), no network.
   Host VS Code stays untouched.
7. **Explicit, symmetric, merge-safe lifecycle.** Nothing self-installs into
   `~/.claude/settings.json`; the user hand-merges one hook entry (see §Claude
   settings) and removes exactly that entry to uninstall. The installer script
   never touches Claude settings, devcontainer config, or VS Code's extension
   registry files.
8. **Full transcript at rest, but nothing else and nowhere reachable.**
   *(Revised 2026-07-23 — reverses the earlier "formulas only" plan.)* To show an
   integrated transcript the inbox now stores the **full assistant message text**
   (segmented into text/math spans) + a timestamp, one record per Stop event.
   Scope stays tight: **assistant messages only** — no user prompts, no
   transcript paths, no other response metadata. (If we later decide to
   interleave user turns for context, that's a deliberate expansion, noted as an
   open question, not the default.) This gives up the "minimal data at rest"
   mitigation that distinguished us from upstream's `history.json`. What still
   holds — and is the property that actually mattered in the 0721 leak — is that
   the file is **unreachable**: mode 600, no HTTP listener, no socket, no
   browser-readable endpoint. Upstream's leak was serious because a browser tab
   could *read* the full text cross-origin, not merely because it was stored. We
   keep the file, drop the network. **Blast-radius invariant:** because the file
   now holds full transcripts, "never add a listener" is no longer a preference
   but a hard rule — any future network surface would expose transcripts, not
   just formulas. The inbox is intentionally persistent; the panel's in-memory
   history is rebuilt from it on each load.

## Name

`mathpanel` — deliberately not "mathrender", so nothing collides with upstream
residue (`~/.mathrender/`, port 18573 muscle memory, marketplace ID).

## Accepted threat model

- History lives inside the container at `~/.mathpanel/inbox.jsonl` (currently
  `/home/node/.mathpanel/inbox.jsonl`).
- Directory mode `700`; inbox file and lock file mode `600`.
- Records contain the full **assistant** message text (as text/math spans) and a
  New York timestamp — never user prompts, transcript paths, or any other
  response metadata. This is a larger at-rest footprint than the original
  formulas-only plan; it is accepted because the file remains unreachable (below).
- Any MathPanel instance in the same container may display the shared history.
  Cross-project aggregation is **accepted**.
- Same-user container processes, container root, and host/Docker admins can read
  the file. That is **accepted** local exposure.
- Formulas reach the desktop only through VS Code's internal
  extension→webview channel. MathPanel creates no HTTP listener, socket, CDN
  request, or browser-readable endpoint.

## Against the 0721 audit checklist

1. Binds `127.0.0.1` or `0.0.0.0`? — **binds nothing.**
2. Sets `Access-Control-Allow-Origin: *`? — **no HTTP exists.**
3. Any GET route returns conversation content? — **no routes at all.** The
   inbox file *does* now hold full assistant text, but no browser or network
   client can reach it — the property the audit checklist is really testing
   ("browser-readable endpoint") is still absent.

The upstream vuln class needed three conditions: a listener, permissive CORS, a
data-bearing route. Removing the listener means conditions 2 and 3 can't even be
expressed — which is exactly why storing more in the file (this revision) does
not reopen the leak.

## Folders and files

### In the repo (committed)

```
.tools/mathpanel/
├── README.md                     # what it is, install, uninstall, threat model
├── hook_send_math.py             # Claude Code Stop hook; stdlib only (~140 ln):
│                                 #   capture assistant msg → segment into
│                                 #   text/math spans → append record
├── test_hook.py                  # unittest for the hook (the only real parser)
├── install-extension.sh          # idempotent copy → ~/.vscode-server/ (~25 ln)
└── extension/
    ├── package.json              # name/version, publisher "local",
    │                             #   "main": "./extension.js",
    │                             #   "extensionKind": ["workspace"],
    │                             #   activationEvents: ["onCommand:mathpanel.show"],
    │                             #   contributes: one command, no view container
    ├── extension.js              # plain JS (~150 ln): register mathpanel.show,
    │                             #   singleton WebviewPanel, fs.watchFile inbox,
    │                             #   whole-file reparse → replaceHistory message
    ├── media/
    │   ├── index.html            # webview (~160 ln): strict CSP + nonce,
    │   │                         #   ready-handshake, iterate spans per record:
    │   │                         #   text→textContent (pre-wrap), math→katex.render;
    │   │                         #   textContent for errors/omissions; no innerHTML
    │   └── katex/                # vendored, pinned — the ONE third-party dep
    │       ├── VENDOR.md         # version, URL, npm integrity, sha256, NY date,
    │       │                     #   exact command, files copied
    │       ├── LICENSE           # KaTeX MIT license text (redistribution req.)
    │       ├── katex.min.js
    │       ├── katex.min.css
    │       └── fonts/            # every font referenced by katex.min.css
    └── .vscodeignore             # not needed (no packaging) — omit
```

### Created at runtime (container, not committed)

```
~/.mathpanel/                     # mode 700, created by hook
├── inbox.jsonl                   # mode 600; newline-terminated JSON records,
│                                 #   bounded to 1 MiB, newest kept on rotation
└── inbox.lock                    # mode 600; fcntl.flock target for writers
~/.vscode-server/extensions/local.mathpanel-0.1.0/
                                  # install target; wiped on container rebuild,
                                  #   restored by install-extension.sh
```

## Data flow

```
Claude Code Stop event
  → hook_send_math.py
      · read Stop-hook JSON from stdin (cap 2 MiB)
      · require dict, hook_event_name == "Stop"
      · obtain the full last assistant message text  [SOURCE: verify at build, see below]
      · segment into ordered spans:
          - fenced + inline code → text spans (shown, never scanned for math)
          - $$…$$ and \[…\]      → display-math spans
          - \(…\)                → inline-math spans
          - everything else      → text spans
      · enforce limits (below): truncate over-long message text with a notice,
        drop over-limit math spans (never render a truncated formula as valid)
      · under flock(inbox.lock): ensure trailing \n, append one record,
        rotate to newest-that-fit ≤1 MiB via tempfile + os.replace
  → extension.js fs.watchFile fires (poll ~1 s)
      · reparse whole bounded file, validate records, ignore bad lines
      · replace in-memory history, postMessage {type:"replaceHistory", entries}
  → index.html renders each record: iterate spans in order; text spans via
      textContent (white-space: pre-wrap, newlines preserved); math spans via
      katex.render into their own element; never innerHTML
```

No listener, no port, no CDN at runtime. Message content is never logged to
stdout (Claude may read hook stdout) or stderr.

### Record format (versioned)

One record per Stop event. Spans are ordered; concatenating their `s` values
reconstructs the (bounded) message. `t` is `"text"` or `"math"`; math spans
carry `m` = `"inline"` or `"display"`.

```json
{"v":1,"ts":"2026-07-23T14:05:00-04:00","spans":[
  {"t":"text","s":"By the mass–energy relation "},
  {"t":"math","m":"inline","s":"E=mc^2"},
  {"t":"text","s":", so:\n"},
  {"t":"math","m":"display","s":"E^2=(mc^2)^2+(pc)^2"}
]}
```

`ts` from `zoneinfo.ZoneInfo("America/New_York")`.

**Segmentation lives in the hook** (Python), so the only scanner/parser is the
one covered by `test_hook.py`; the webview stays a trivial iterate-and-render
loop with no scanning of its own. (Alternative considered: store raw message
text and split in the webview — rejected to keep parsing tested and the webview
minimal.)

### ⚠️ Verify the message source at build time

The review proposed reading a `last_assistant_message` field straight off the
Stop-hook stdin JSON. **Not confirmed to exist** — as far as we know the Stop
payload is `{session_id, transcript_path, cwd, hook_event_name,
stop_hook_active}`, and the assistant text is only reachable via
`transcript_path` (which is why upstream reads the transcript). If we code to a
missing field the hook silently extracts nothing.

Build-time check (keys only, no content) against a **real** Stop event:

```python
import sys, json; print(sorted(json.load(sys.stdin).keys()))
```

- If `last_assistant_message` is present in current Claude Code → use it, never
  open `transcript_path`.
- If absent → read `transcript_path`, parse only the trailing lines for the last
  assistant message.

Either way: only the **assistant** message text (segmented into spans) + `ts` is
written — never user prompts or the transcript path itself, even when we read
`transcript_path` to obtain the message. The scope guarantee holds regardless of
source.

## Transport reliability (v0.1: whole-file refresh, not offset tailer)

`fs.watch` + byte-offset tailing is fragile around creation, partial writes,
coalesced events, and rotation. Instead:

- **Writer (hook):** serialize the full record first, then one append. Under
  `fcntl.flock` on `inbox.lock`: ensure any existing file ends in `\n` (so a
  crashed partial line can't corrupt the next record), append, then rotate —
  retain the newest complete records that fit in 1 MiB and atomically replace
  via a same-directory tempfile + `os.replace`. **Never truncate in place.**
- **Reader (extension):** `fs.watchFile` (poll 500–1000 ms), not raw `fs.watch`
  — handles creation, replacement, and truncation uniformly on the one platform
  we run (Linux). On activation and every change: read the whole bounded file,
  parse newline-terminated records, validate, drop malformed lines individually,
  replace in-memory history, send one `replaceHistory`. `fs.unwatchFile` on
  deactivate.

Whole-file replace also removes duplicate-after-rotation bugs and all cursor
bookkeeping.

Acceptance tests: inbox absent at activation; first hook creates it and shows;
two concurrent hooks don't interleave JSON; trailing partial line ignored
without losing later records; rotation leaves valid JSONL with newest records;
VS Code restart reloads history exactly once; malformed line doesn't block later
valid lines.

## Resource limits

Enforce at **two** layers — the hook (sole writer) and the KaTeX renderer.
The extension does ordinary type/count validation on parse but is not a third
enforcement layer (single-user tool, one trusted writer; three-layer
enforcement is defense-in-depth theater here).

| Limit | Value |
|---|---|
| Hook stdin | 2 MiB |
| Stored assistant message text | 128 KiB (truncate beyond, with notice) |
| Single math span | 8,192 chars |
| Math spans per message | 64 |
| Serialized record | 160 KiB |
| Inbox file | 1 MiB |
| Messages retained in panel | newest 50 |
| KaTeX | `trust:false`, `throwOnError:false`, `maxExpand:1000`, `maxSize:20` |

Buffers are larger than the formulas-only plan because full messages are bigger
than bare equations (256 KiB held plenty of formulas but only ~2 messages).

Two truncation behaviors, deliberately different:
- **Prose over the message cap** → truncate and append a visible text marker
  (`[message truncated: size limit]`). Truncated prose is still just inert text.
- **A math span over its cap** → *drop* it and optionally show a plain-text
  notice ("Formula omitted: size limit exceeded"). Never render a truncated
  formula as if valid.

## UI: command-only WebviewPanel (no sidebar in v0.1)

- Contribute one command `mathpanel.show`; explicit activation event
  `onCommand:mathpanel.show`.
- Singleton `WebviewPanel` in `ViewColumn.Beside`; reveal the existing panel if
  open; set the reference to `undefined` on dispose.
- On reopen, wait for the webview's `ready` message, then resend current history.
- No activity-bar container, tree view, welcome view, or sidebar icon (removes
  the missing-icon/provider mismatch copied from upstream's manifest; matches
  the near-zero-niceties decision). A real sidebar via `WebviewViewProvider` is
  a later option.

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
  extension replies `{type:"replaceHistory", entries:[...]}` → later refreshes
  reuse the same message.
- Per record, iterate spans in order. Text spans: create an element and set
  `textContent` (CSS `white-space: pre-wrap` so newlines/indent survive). Math
  spans: `katex.render(span.s, el, {...displayMode: span.m==="display"})`.
  Errors/omissions go in via `textContent`, never `innerHTML`. No HTML string
  building anywhere. Validate every message and every span (`t`/`m`/`s` types)
  before touching the DOM.
- Because prose is inert `textContent` and only math text reaches KaTeX, showing
  the full transcript adds **no** XSS surface over the formulas-only design.

## Claude settings (hand-merged, never scripted)

The installer must **not** edit `~/.claude/settings.json` — it already holds
unrelated top-level config and hook entries. README instructs the user to:

1. Open the existing `~/.claude/settings.json`.
2. Preserve all current top-level keys and all existing hook arrays/entries.
3. Add exactly one MathPanel command hook to `hooks.Stop` (search for the exact
   command string first to avoid duplicates).
4. Validate: `python3 -m json.tool ~/.claude/settings.json`.

The nested entry:

```json
{
  "type": "command",
  "command": "python3 /workspace/.tools/mathpanel/hook_send_math.py",
  "timeout": 5,
  "async": true
}
```

Uninstall removes only the nested hook whose `command` exactly matches that
path; it must not delete the whole `Stop` array or `hooks` object unless they
become empty.

## Installer (idempotent, narrow)

`install-extension.sh`:

- `set -eu`; resolve source relative to the script, not the caller's cwd.
- Verify `extension/package.json` and `extension/extension.js` exist.
- Target exactly `~/.vscode-server/extensions/local.mathpanel-0.1.0`.
- `rm -rf` the exact target, then `cp -r extension/. ` into it; safe to run
  twice with identical result.
- Print that the user must reload the VS Code window.
- Never edit `extensions.json`, `.obsolete`, Claude settings, or devcontainer
  config.

(The review's staging-dir-with-trap atomic-deploy choreography is overkill for
copying a handful of files into our own home dir; the failure mode is "run it
again." Kept simple.)

Installation is an environment change — run only when the user explicitly asks
to build/install MathPanel.

## Uninstall order

1. Remove the exact Claude hook entry (command path match).
2. Remove the exact `local.mathpanel-0.1.0` extension directory.
3. Reload the VS Code window (terminates any still-running instance).
4. Optionally `rm -rf ~/.mathpanel/` to erase saved history.
5. Confirm no MathPanel hook or extension directory remains.

Unlike upstream MathRender there is no listener and no deactivate-time history
writeback, so there is no server or shutdown-flush to chase during teardown.

## Tests (proportionate)

- **`test_hook.py`** (Python `unittest`, stdlib): payload parsing, span
  segmentation (text vs display/inline math, delimiters, code kept as text and
  never math-scanned), message truncation + math-span drop at limits, malformed
  JSON, file/dir permissions, concurrent append under flock, rotation. Uses temp
  dirs only — never writes the real `~/.mathpanel`.
- Manual integration checklist (below) covers the rest. No Node test harness,
  installer-idempotence suite, or static HTML-grep CI for v0.1 — that test
  matrix would be larger than the extension. (Revisit if the tool grows.)

Manual checks: install → reload → open panel; fake Stop event; real Claude Stop
event; close/reopen panel; VS Code restart reloads history once; hostile KaTeX
inputs render inert or error; `lsof -nP -iTCP -sTCP:LISTEN` identical before and
after (proves no listening socket).

## KaTeX vendor record

`media/katex/` must contain `VENDOR.md`, the exact KaTeX `LICENSE`,
`katex.min.js`, `katex.min.css`, and every font the CSS references. `VENDOR.md`
records: exact version (never a range or "latest"); exact tarball URL; npm
integrity value if available; computed SHA-256 of the tarball; New York
acquisition date; exact command used; which files were copied.

The first checksum anchors *this build's* artifact — it does not prove the
registry was uncompromised. On later rebuilds, compare the download against the
recorded checksum before extracting.

## Build order (when we build)

1. Fetch + verify KaTeX tarball (`npm pack`), record in `VENDOR.md`, vendor
   files + LICENSE into `media/katex/`. ← only step touching the network.
2. **Verify the Stop-hook message source** (keys-only dump, above) and pick the
   `last_assistant_message`-vs-`transcript_path` branch.
3. Write `package.json`, `extension.js`, `index.html`, `hook_send_math.py`,
   `test_hook.py`, `install-extension.sh`, `README.md`.
4. Run `test_hook.py` (temp dirs); confirm records are assistant-only span
   arrays (no prompts / no transcript path), mode 600, dir 700.
5. Run `install-extension.sh`, reload window, confirm the panel opens.
6. Add the hook to `~/.claude/settings.json` (user, hand-merged), run a real
   Claude turn with math, confirm render.
7. Negative checks: `lsof` listener table unchanged; hostile inputs
   (`\href{javascript:...}`, `\htmlData`, huge `\def`) inert or errored.

## Open questions (decide during build)

- KaTeX version pin (latest 0.16.x at build time; upstream used 0.16.11).
- **User prompts?** v0.1 stores assistant messages only. Interleaving the user's
  own turns would make the panel read more like a true conversation, but means
  reading `transcript_path` for user text and storing prompts at rest — a
  deliberate expansion of the footprint. Default off; decide if the
  assistant-only view feels disjointed in use.
- Single-`$…$` delimiters stay **out** of v0.1 (currency / shell-var / prose
  false positives). With code now kept as text spans and never math-scanned, the
  worst offenders (shell `$VAR`) are already handled; revisit `$…$` only if real
  inline formulas are being missed.
- Per-project gating: hook fires in every project once registered. Accepted
  (cross-project aggregation is in the threat model); revisit if noisy.

## Not doing

- No `npm install`, no TypeScript, no vsce, no marketplace publishing.
- No contact with upstream repo (no fork, no issue, no PR).
- No history persistence beyond the bounded assistant-message inbox, no
  `/clear`-style remote controls, no config beyond what's needed to render.
- No markdown/rich rendering of prose (no bold, headers, links, syntax
  highlighting) — non-math is plain `textContent` only.
- No user prompts stored in v0.1 (see open questions).
- No third enforcement layer, no atomic-deploy staging, no Node/CI test matrix
  in v0.1.
- Upstream reference copy `/workspace/MathRenderer/` stays unexecuted; delete
  once the rewrite is stable.
