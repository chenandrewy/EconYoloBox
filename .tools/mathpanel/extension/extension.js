// MathPanel: VS Code glue. Discovers the active Claude Code or Codex CLI session
// transcript for this workspace, follows it read-only via fs.watchFile, and
// mirrors the parsed history into a singleton webview. No network, no transcript
// writes, no files of our own.
'use strict';

const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const {
  LIMITS,
  mungePath,
  LineBuffer,
  parseLine: parseClaudeLine,
} = require('./transcript');
const {
  recentSessionDateParts,
  cachedSessionMeta,
  parseLine: parseCodexLine,
} = require('./codex');

const INCLUDE_USER = true; // interleave real user prompts with assistant text
const DISCOVERY_MS = 1000;
const WATCH_MS = 750;
const CODEX_DAYS = 7;
const FIRST_LINE_CHUNK = 64 * 1024;
const NO_SESSION = 'No Claude Code or Codex CLI session found for this workspace.';

let panel; // singleton WebviewPanel
let webviewReady = false;
let follower; // transcript-follow state while the panel is open

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('mathpanel.show', () => show(context)),
  );
}

function deactivate() {
  stopFollower();
}

function show(context) {
  if (panel) {
    panel.reveal(vscode.ViewColumn.Beside);
    return;
  }
  panel = vscode.window.createWebviewPanel('mathpanel', 'MathPanel', vscode.ViewColumn.Beside, {
    enableScripts: true,
    localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'media')],
  });
  webviewReady = false;
  panel.webview.html = buildHtml(context, panel.webview);
  panel.webview.onDidReceiveMessage(
    (m) => {
      if (m && m.type === 'ready') {
        webviewReady = true;
        sendHistory();
      }
    },
    undefined,
    context.subscriptions,
  );
  panel.onDidDispose(
    () => {
      panel = undefined;
      webviewReady = false;
      stopFollower();
    },
    undefined,
    context.subscriptions,
  );
  startFollower();
}

function buildHtml(context, webview) {
  const mediaUri = (...p) =>
    webview.asWebviewUri(vscode.Uri.joinPath(context.extensionUri, 'media', ...p)).toString();
  const nonce = crypto.randomBytes(16).toString('base64');
  const html = fs.readFileSync(path.join(context.extensionPath, 'media', 'index.html'), 'utf8');
  return html
    .replaceAll('{{cspSource}}', webview.cspSource)
    .replaceAll('{{nonce}}', nonce)
    .replaceAll('{{katexCss}}', mediaUri('katex', 'katex.min.css'))
    .replaceAll('{{katexJs}}', mediaUri('katex', 'katex.min.js'));
}

// ---------------------------------------------------------------- follower

function startFollower() {
  if (follower) return;
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length !== 1 || folders[0].uri.scheme !== 'file') {
    follower = { messages: [], status: 'MathPanel supports exactly one local workspace folder.' };
    return;
  }
  // Match both vendors against the workspace realpath. Their transcript roots
  // stay logical — the kernel resolves any symlink again on every access.
  let real;
  try {
    real = fs.realpathSync(folders[0].uri.fsPath);
  } catch {
    real = folders[0].uri.fsPath;
  }
  follower = {
    workspaceReal: real,
    claudeProjDir: path.join(os.homedir(), '.claude', 'projects', mungePath(real)),
    codexRoot: path.join(os.homedir(), '.codex', 'sessions'),
    codexMetaCache: new Map(), // positive path+inode; negative path+inode+size
    file: undefined,
    source: undefined,
    sessionTimestamp: '',
    lastIno: -1,
    lastSize: 0,
    lineBuf: new LineBuffer(),
    messages: [],
    unexpected: false,
    status: NO_SESSION,
    timer: setInterval(discover, DISCOVERY_MS),
  };
  discover();
}

function stopFollower() {
  if (!follower) return;
  if (follower.timer) clearInterval(follower.timer);
  if (follower.file) fs.unwatchFile(follower.file);
  follower = undefined;
}

function newer(a, b) {
  if (!a) return b;
  if (!b) return a;
  if (b.mtimeMs !== a.mtimeMs) return b.mtimeMs > a.mtimeMs ? b : a;
  return b.path > a.path ? b : a;
}

function discoverClaude() {
  let names;
  try {
    names = fs.readdirSync(follower.claudeProjDir);
  } catch {
    return undefined;
  }
  let best;
  for (const name of names) {
    if (!name.endsWith('.jsonl')) continue;
    const p = path.join(follower.claudeProjDir, name);
    let st;
    try {
      st = fs.statSync(p);
    } catch {
      continue;
    }
    if (!st.isFile() || st.size === 0) continue;
    best = newer(best, { path: p, source: 'claude', mtimeMs: st.mtimeMs });
  }
  return best;
}

function recentCodexDirs() {
  return recentSessionDateParts(Date.now(), CODEX_DAYS).map((parts) =>
    path.join(follower.codexRoot, ...parts),
  );
}

// Read only the first line, capped by the same guard as normal transcript lines.
// Most metadata lines fit in the initial 64 KiB; grow only when necessary.
function readFirstLine(p) {
  let fd;
  try {
    fd = fs.openSync(p, 'r');
    const maxBytes = LIMITS.MAX_LINE + 1;
    let buf = Buffer.alloc(Math.min(FIRST_LINE_CHUNK, maxBytes));
    let read = 0;
    for (;;) {
      if (read === buf.length) {
        if (buf.length === maxBytes) return undefined; // no newline within cap
        const grown = Buffer.alloc(Math.min(buf.length * 2, maxBytes));
        buf.copy(grown, 0, 0, read);
        buf = grown;
      }
      const n = fs.readSync(fd, buf, read, buf.length - read, read);
      if (n <= 0) return undefined;
      const newline = buf.subarray(read, read + n).indexOf(0x0a);
      if (newline >= 0) return buf.toString('utf8', 0, read + newline);
      read += n;
    }
  } catch {
    return undefined;
  } finally {
    if (fd !== undefined) {
      try {
        fs.closeSync(fd);
      } catch {}
    }
  }
}

function discoverCodex() {
  let best;
  for (const dir of recentCodexDirs()) {
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const name of names) {
      if (!/^rollout-.*\.jsonl$/.test(name)) continue;
      const p = path.join(dir, name);
      let st;
      try {
        st = fs.statSync(p);
      } catch {
        continue;
      }
      if (!st.isFile() || st.size === 0) continue;
      const meta = cachedSessionMeta(
        follower.codexMetaCache,
        p,
        st.ino,
        st.size,
        () => readFirstLine(p),
      );
      if (!meta) continue;
      if (meta.cwd !== follower.workspaceReal) continue;
      best = newer(best, {
        path: p,
        source: 'codex',
        mtimeMs: st.mtimeMs,
        sessionTimestamp: meta.timestamp,
      });
    }
  }
  return best;
}

// Every ~1s: union the Claude project candidates with cwd-matched Codex
// rollouts from the last seven date directories plus tomorrow's timezone guard,
// then follow the newest mtime.
function discover() {
  if (!follower || !follower.claudeProjDir) return;
  selectFile(newer(discoverClaude(), discoverCodex()));
}

function selectFile(candidate) {
  if (!follower) return;
  const p = candidate && candidate.path;
  if (p === follower.file && (!candidate || candidate.source === follower.source)) {
    if (candidate) {
      follower.sessionTimestamp = candidate.sessionTimestamp || '';
      poll();
    }
    return;
  }
  if (follower.file) fs.unwatchFile(follower.file);
  follower.file = p;
  follower.source = candidate && candidate.source;
  follower.sessionTimestamp = (candidate && candidate.sessionTimestamp) || '';
  follower.lastIno = -1;
  follower.lastSize = 0;
  follower.lineBuf.reset();
  follower.messages = [];
  follower.unexpected = false;
  if (!p) {
    follower.status = NO_SESSION;
    sendHistory();
    return;
  }
  follower.status = '';
  fs.watchFile(p, { interval: WATCH_MS }, poll);
  poll();
}

// Open the logical path fresh each time (never a cached fd or realpath) so a
// swapped symlink target shows up as an inode change or transient ENOENT.
function poll() {
  if (!follower || !follower.file) return;
  let fd;
  try {
    fd = fs.openSync(follower.file, 'r');
  } catch {
    return; // transient ENOENT (rotation/sync swap): keep polling
  }
  try {
    const st = fs.fstatSync(fd);
    if (st.ino !== follower.lastIno || st.size < follower.lastSize) {
      rebuild(fd, st);
    } else if (st.size > follower.lastSize) {
      const consumed = readRange(fd, follower.lastSize, st.size);
      follower.lastSize += consumed;
      sendHistory();
    }
  } catch {
    // fail-soft: skip this cycle
  } finally {
    try {
      fs.closeSync(fd);
    } catch {}
  }
}

function rebuild(fd, st) {
  follower.messages = [];
  follower.lineBuf.reset();
  follower.unexpected = false;
  let offset = 0;
  if (st.size > LIMITS.MAX_REBUILD_BYTES) {
    offset = st.size - LIMITS.MAX_REBUILD_BYTES;
    follower.lineBuf.startMidLine();
  }
  const consumed = readRange(fd, offset, st.size);
  follower.lastIno = st.ino;
  follower.lastSize = offset + consumed;
  sendHistory();
}

// Reads [from, to), feeds complete lines through the parser. Returns bytes
// actually consumed so a short read is retried on the next poll.
function readRange(fd, from, to) {
  const len = to - from;
  if (len <= 0) return 0;
  const buf = Buffer.alloc(len);
  let read = 0;
  while (read < len) {
    const n = fs.readSync(fd, buf, read, len - read, from + read);
    if (n <= 0) break;
    read += n;
  }
  const lines = follower.lineBuf.push(read === len ? buf : buf.subarray(0, read));
  for (const line of lines) {
    const opts = {
      includeUser: INCLUDE_USER,
      sessionTimestamp: follower.sessionTimestamp,
    };
    const r =
      follower.source === 'codex'
        ? parseCodexLine(line, opts)
        : parseClaudeLine(line, opts);
    if (r.unexpected) follower.unexpected = true;
    for (const m of r.messages) follower.messages.push(m);
  }
  if (follower.messages.length > LIMITS.MAX_MESSAGES) {
    follower.messages = follower.messages.slice(-LIMITS.MAX_MESSAGES);
  }
  return read;
}

// ---------------------------------------------------------------- webview out

const TS_FMT = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  hour12: true,
});

function tsDisplay(ts) {
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? '' : TS_FMT.format(d);
}

function sendHistory() {
  if (!panel || !webviewReady) return;
  const f = follower;
  panel.webview.postMessage({
    type: 'replaceHistory',
    entries: f
      ? f.messages.map((m) => ({ role: m.role, tsDisplay: tsDisplay(m.ts), spans: m.spans }))
      : [],
    status: f ? f.status : '',
    notice:
      f && f.unexpected
        ? `Some records were skipped — ${
            f.source === 'codex' ? 'Codex CLI' : 'Claude Code'
          } transcript format may have changed.`
        : '',
  });
}

module.exports = { activate, deactivate };
