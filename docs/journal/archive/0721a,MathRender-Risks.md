# MathRender: localhost CORS exposure of agent transcripts

**Date:** 2026-07-21
**Extension:** `nikkfh5.mathrender-0.8.2` (VS Code), publisher `Nikkfh5`, MIT
**Repo:** https://github.com/Nikkfh5/mathrender
**Status:** uninstalled pending fix. Not malicious. One real vulnerability.

## Bottom line

MathRender is the best solution I've seen for a genuinely common use case —
rendering LaTeX from Claude Code / Codex responses in an editor side panel.
The problem below is a one-line mistake, not a sign of a bad project. Worth
re-checking and reporting upstream, and worth reinstalling once fixed.

## What is clean

Audited the full package (`~/.vscode/extensions/nikkfh5.mathrender-0.8.2`).

- No obfuscation or hostile minification; ships readable JS with sourcemaps.
- No `child_process`, `exec`, `spawn`, `eval`, or `new Function` anywhere.
- No outbound network to any author-controlled host. Only external fetches are
  `cdn.jsdelivr.net` for KaTeX 0.16.11 and marked 12.0.2.
- HTTP server binds `127.0.0.1`, not `0.0.0.0` — unreachable from LAN/internet.
- `~/.mathrender/history.json` is mode `600`.

The Python hook (`~/.mathrender/hook_send_formulas.py`) does exactly what it
claims: regex-matches LaTeX, POSTs the message text to localhost. Nothing hidden.

## The vulnerability

`out/extension.js:25-29` sets a wildcard CORS header on **every** route:

```js
const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
};
```

`GET /history` returns the full text of every captured assistant response.
The wildcard is what makes that readable cross-origin — without it the browser
blocks the read.

**Consequence:** any web page, in any tab, while VS Code is running, can do:

```js
fetch('http://127.0.0.1:18573/history')
  .then(r => r.json())
  .then(data => /* exfiltrate */);
```

No prompt, no user interaction beyond visiting the page.

### Proof of concept (re-verify before reporting)

```sh
curl -s -H "Origin: https://evil.example" -D- -o /dev/null \
  http://127.0.0.1:18573/history | grep -iE '^HTTP|access-control'
```

Observed 2026-07-21:

```
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
```

### Why it mattered here

At the time of discovery `history.json` contained my in-progress referee
analysis of an unpublished manuscript under confidential review at J Econom.
Leaking that is a professional-conduct problem, not merely a privacy one.

### Secondary

`POST /clear`, `/pause`, `/resume` are CORS-simple requests — any page can wipe
history or silently pause capture. Destructive only, low severity.

## Lower priority: webview sanitizer

`media/index.html:357` is a homegrown **denylist** sanitizer feeding `innerHTML`,
under a CSP permitting `script-src 'unsafe-inline'`. It strips
`script`/`iframe`/`object`/`embed`/`form`, `on*` attributes, and `javascript:`
hrefs. Denylist sanitizers of this shape are historically bypassable via
mutation-XSS. No working bypass found. Path would be: hostile content in a
reviewed PDF → pasted into a session → rendered in webview. Speculative, but
it is why the CORS bug was not the only sharp edge.

## Orphans that survive uninstall

Uninstalling the extension removes the reader, not the residue:

1. **`~/.claude/settings.json`** — the extension self-installed a `Stop` hook
   (`python3 ~/.mathrender/hook_send_formulas.py`, `timeout: 5`, `async: true`).
   VS Code uninstall does not revert this. Left in place it spawns a Python
   process every turn, in every project, against a dead port. It fails closed
   (connection refused → silent exit), so it is wasted work rather than risk —
   but it is the kind of orphan that quietly reactivates if something else
   later binds 18573.
2. **`~/.mathrender/history.json`** — the transcript data itself.

Both need explicit removal. After uninstalling, reload the VS Code window and
confirm the port is free: `lsof -nP -iTCP:18573 -sTCP:LISTEN`. The extension
host can outlive the uninstall until restart.

### Teardown is a three-body problem (observed, not theoretical)

All three of these bit during the actual 2026-07-21 teardown. The naive order —
uninstall, delete data — fails in both directions.

**1. `--uninstall-extension` does not stop the running server.** After the
uninstall command, PID 44055 (`Code Helper`) was still bound to 18573 and still
answering `GET /history` cross-origin. VS Code marks the extension obsolete
(`~/.vscode/extensions/.obsolete`) and drops it from `--list-extensions`, but
the live extension host keeps serving until the window reloads. The directory
itself lingers until VS Code's next startup sweep — harmless once deregistered,
but it looks alarming.

**2. Deleting `history.json` does not clear the served data.** History is read
into a module-level array at activation (`out/extension.js:216`) and served from
memory. With `~/.mathrender/` already deleted, `GET /history` still returned
12,450 bytes of referee content out of RAM — *more* than the 6,575 bytes the
file had held, since capture continued during the audit itself.

**3. The reload resurrects the file.** On deactivate the extension flushes its
in-memory array back to disk. `~/.mathrender/history.json` reappeared at 11:25,
12,450 bytes, immediately after the window reload that killed the server.
Deleting before reload is therefore useless.

**Correct order:** uninstall → **reload the window** → *then* delete the data
directory → verify. Verification is two commands, and both must be checked:

```sh
lsof -nP -iTCP:18573 -sTCP:LISTEN   # must be empty
ls -la ~/.mathrender               # must be gone, checked AFTER reload
```

Generalizes to any long-lived local service holding transcripts: **the process
is the authority on the data, not the filesystem.** Kill the process first, and
re-check disk afterward — a graceful shutdown may write the very file you just
removed.

## The general lesson (this is the part that generalizes)

The specific bug is one wildcard. The **pattern** is the real finding:

> agent transcript → localhost HTTP bridge → editor UI

Anything with that shape is reachable from any browser tab, and the transcript
is the crown jewels. This class of tool is proliferating.

Audit checklist for any such tool — three checks, would have caught this in
under a minute:

1. Does it bind `127.0.0.1` or `0.0.0.0`?
2. Does it set `Access-Control-Allow-Origin: *`?
3. Does any GET route return conversation content?

A localhost bind is necessary but **not** sufficient. The browser is the
attack surface, not the network.

## Remediation path (scoped 2026-07-21, not yet executed)

### The CORS block is dead code — delete it, don't narrow it

Confirmed against 0.8.2. Nothing legitimate ever talks to that server over HTTP:

- The webview uses `acquireVsCodeApi()` + `postMessage` (`media/index.html:337`),
  VS Code's internal message channel, not HTTP. Zero `fetch`/`XHR`/`WebSocket`
  calls in the webview.
- Its CSP sets `connect-src https://cdn.jsdelivr.net` — it *could not* reach
  `127.0.0.1` even if it wanted to.

So the fix is removing `CORS_HEADERS` and its three usages outright, rather than
carefully narrowing an allowlist. Lower risk of breaking the panel.

Upstream location (still present as of 2026-07-21):
`extension/src/extension.ts:29-33`. Repo is alive — last commit 2026-06-02,
TypeScript source, standard build.

### Do NOT publicly fork before disclosing

GitHub forks of public repos are permanently public — there is no setting to
make one private. Pushing a commit titled "remove CORS wildcard" publishes a
working 0-day, with the exploit implied by the diff, to every current MathRender
user before the author can ship a fix. This is the only irreversible step in the
whole exercise.

Correct order: patch privately → notify author → let them fix → then public.
A private copy for tracking is a `git clone` pushed to a **new private repo**,
not a fork.

### Local safe build (steps, for when there's time)

Toolchain verified present 2026-07-21: node v25.9.0, npm 11.12.1,
VS Code 1.129.1, `gh` authed as `chenandrewy`. `vsce` via `npx`.

1. `git clone https://github.com/Nikkfh5/mathrender` to a scratch dir
2. Delete `CORS_HEADERS` + its three usages in `extension/src/extension.ts`
3. `npm install && npm run compile`, then `npx vsce package` → `.vsix`
4. `code --install-extension mathrender-0.8.2.vsix` — local only, never
   touches the marketplace
5. Re-run the PoC curl to confirm the header is gone and the panel still renders
6. Separately: file a quiet upstream issue describing the bug **without** a
   weaponized diff

Steps 1-5 are local and reversible. Step 6 is the outward-facing one.

## TODO

- [ ] Re-verify the PoC against current upstream `main` before reporting.
- [ ] File issue with Nikkfh5 (see disclosure ordering above — issue, not a
      PR from a public fork).
- [ ] Build the local patched `.vsix` if the tool is wanted before upstream
      fixes it.
- [ ] Reinstall once fixed — the tool solves a real problem well.
- [ ] Audit other agent-adjacent local tools against the 3-check list above.