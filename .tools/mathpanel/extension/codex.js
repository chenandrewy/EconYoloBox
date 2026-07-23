// Pure Codex CLI transcript helpers for MathPanel. No vscode or filesystem
// imports. Discovery uses sessionMetaFromLine() on the first JSONL line; the
// follower sends all later lines through parseLine().
'use strict';

const { blockToSpans } = require('./transcript');

const NONE = { messages: [], unexpected: false };
const NO_SESSION_META = Symbol('no-session-meta');
const NY_DATE_FMT = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

// Anchor the scan to New York calendar dates and include tomorrow as a forward
// guard for ai-sesh stores written by a machine in a time zone ahead of New
// York. Do the subtraction as calendar arithmetic, not fixed 24-hour jumps
// across DST. `days` is the number of dates through today, so the returned
// window has days + 1 entries after adding tomorrow.
function recentSessionDateParts(nowMs, days) {
  const parts = Object.fromEntries(
    NY_DATE_FMT.formatToParts(new Date(nowMs))
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

// Positive metadata is immutable and cached by (logical path, inode). Negative
// results also include size, so an incomplete new file is retried after growth
// while a permanently unparseable file is not reopened every discovery tick.
function cachedSessionMeta(cache, filePath, inode, size, readFirstLine) {
  const fileKey = `${filePath}\0${inode}`;
  if (cache.has(fileKey)) return cache.get(fileKey);

  const negativeKey = `${fileKey}\0${size}`;
  if (cache.get(negativeKey) === NO_SESSION_META) return undefined;

  const line = readFirstLine();
  const meta = typeof line === 'string' ? sessionMetaFromLine(line) : undefined;
  if (meta) {
    cache.set(fileKey, meta);
  } else {
    cache.set(negativeKey, NO_SESSION_META);
  }
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
