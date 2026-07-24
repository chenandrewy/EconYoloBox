// Pure Codex CLI transcript helpers for MathPanel. No vscode or filesystem
// imports. Discovery uses sessionMetaFromLine() on the first JSONL line; the
// follower sends all later lines through parseLine().
'use strict';

const { blockToSpans } = require('./transcript');

const NONE = { messages: [], unexpected: false };
const NO_SESSION_META = Symbol('no-session-meta');
const dateFmtCache = new Map();
function dateFmt(timeZone) {
  let fmt = dateFmtCache.get(timeZone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone, // undefined = host zone, the same clock Codex wrote the dirs by
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    dateFmtCache.set(timeZone, fmt);
  }
  return fmt;
}

// Codex names its YYYY/MM/DD session directories after the *local* calendar
// date of the machine that wrote them, not UTC — verified against 111 observed
// rollouts, 11 of which sit in a directory that disagrees with their own UTC
// timestamp. So anchor the scan to the host zone; `timeZone` overrides it for
// tests only. Include tomorrow as a forward guard for ai-sesh stores written by
// a machine in a zone ahead of this one. Do the subtraction as calendar
// arithmetic, not fixed 24-hour jumps across DST. `days` is the number of dates
// through today, so the returned window has days + 1 entries after tomorrow.
function recentSessionDateParts(nowMs, days, timeZone) {
  const parts = Object.fromEntries(
    dateFmt(timeZone)
      .formatToParts(new Date(nowMs))
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, Number(part.value)]),
  );
  const out = [];
  for (let i = -1; i < days; i += 1) {
    const date = new Date(Date.UTC(parts.year, parts.month - 1, parts.day - i, 12));
    out.push([
      String(date.getUTCFullYear()).padStart(4, '0'),
      String(date.getUTCMonth() + 1).padStart(2, '0'),
      String(date.getUTCDate()).padStart(2, '0'),
    ]);
  }
  return out;
}

function timestampOf(rec, opts) {
  if (typeof rec.timestamp === 'string') return rec.timestamp;
  return opts && typeof opts.sessionTimestamp === 'string' ? opts.sessionTimestamp : '';
}

function makeMessage(rec, opts, role, text) {
  return {
    ts: timestampOf(rec, opts),
    role,
    spans: blockToSpans(text),
  };
}

// The session_meta record is the first line in observed Codex rollouts. Return
// only the immutable fields discovery needs; malformed or changed records are
// ignored rather than made fatal.
function sessionMetaFromLine(line) {
  let rec;
  try {
    rec = JSON.parse(line);
  } catch {
    return undefined;
  }
  const payload = rec && rec.payload;
  if (
    !rec ||
    typeof rec !== 'object' ||
    Array.isArray(rec) ||
    rec.type !== 'session_meta' ||
    !payload ||
    typeof payload !== 'object' ||
    Array.isArray(payload) ||
    typeof payload.cwd !== 'string' ||
    payload.cwd === ''
  ) {
    return undefined;
  }
  return {
    cwd: payload.cwd,
    timestamp:
      typeof payload.timestamp === 'string'
        ? payload.timestamp
        : typeof rec.timestamp === 'string'
          ? rec.timestamp
          : '',
  };
}

// Cached by (logical path, inode), one entry per file either way. Positive
// metadata is immutable, so a hit is final. A negative entry carries the size it
// failed at and is overwritten in place on each retry: an incomplete file — one
// still syncing in, say — is reread only after it grows, and a permanently
// unparseable one is not reopened every discovery tick. Keeping the size in the
// value rather than the key is what bounds the cache; keying by size would mint
// a new entry for every append to a file that never parses.
function cachedSessionMeta(cache, filePath, inode, size, readFirstLine) {
  const fileKey = `${filePath}\0${inode}`;
  const cached = cache.get(fileKey);
  if (cached !== undefined) {
    if (cached.kind !== NO_SESSION_META) return cached;
    if (cached.size === size) return undefined;
  }

  const line = readFirstLine();
  const meta = typeof line === 'string' ? sessionMetaFromLine(line) : undefined;
  cache.set(fileKey, meta || { kind: NO_SESSION_META, size });
  return meta;
}

// One Codex JSONL line -> { messages: [...], unexpected: bool }.
//
// Assistant text is present twice in current rollouts. response_item/message is
// the canonical copy; event_msg/agent_message is deliberately skipped. For user
// prompts we do the reverse: event_msg/user_message contains what the user
// typed, while response_item role:user also contains injected context records.
function parseLine(line, opts) {
  let rec;
  try {
    rec = JSON.parse(line);
  } catch {
    return NONE;
  }
  if (!rec || typeof rec !== 'object' || Array.isArray(rec)) {
    return { messages: [], unexpected: true };
  }
  const payload = rec.payload;

  if (rec.type === 'response_item' && payload && payload.type === 'message') {
    if (payload.role !== 'assistant') return NONE;
    if (!Array.isArray(payload.content)) {
      return { messages: [], unexpected: true };
    }
    const messages = [];
    let changedShape = false;
    for (const item of payload.content) {
      if (!item || typeof item !== 'object' || item.type !== 'output_text') {
        changedShape = true;
        continue;
      }
      if (typeof item.text !== 'string') {
        changedShape = true;
        continue;
      }
      if (item.text.trim() !== '') {
        messages.push(makeMessage(rec, opts, 'assistant', item.text));
      }
    }
    return { messages, unexpected: changedShape };
  }

  if (
    rec.type === 'event_msg' &&
    payload &&
    payload.type === 'user_message' &&
    opts &&
    opts.includeUser
  ) {
    if (typeof payload.message !== 'string') {
      return { messages: [], unexpected: true };
    }
    if (payload.message.trim() === '') return NONE;
    return {
      messages: [makeMessage(rec, opts, 'user', payload.message)],
      unexpected: false,
    };
  }

  // event_msg/agent_message is the duplicate assistant copy. Reasoning, tools,
  // turn context, world state, token counts, and unknown types are bookkeeping.
  return NONE;
}

module.exports = {
  recentSessionDateParts,
  sessionMetaFromLine,
  cachedSessionMeta,
  parseLine,
};
