// Pure transcript-parsing module for MathPanel. No vscode imports — unit-testable
// under node:test. Converts Claude Code session JSONL lines into renderable
// messages of ordered text/math spans. Fail-soft throughout: anything with an
// unexpected shape is skipped, never fatal.
'use strict';

const LIMITS = {
  MAX_TEXT: 128 * 1024, // chars kept per message (truncate beyond, with marker)
  MAX_MATH_SPAN: 8192, // chars in a single math span (drop beyond, with notice)
  MAX_MATH_PER_MSG: 64, // math spans per message (extras rendered as plain text)
  MAX_LINE: 256 * 1024, // bytes; longer JSONL lines skipped before JSON.parse
  MAX_PARTIAL: 512 * 1024, // bytes; partial-line buffer cap (discard + resync)
  MAX_MESSAGES: 50, // messages retained in the panel
  MAX_REBUILD_BYTES: 4 * 1024 * 1024, // tail read on whole-file rebuild
};

// Claude Code's project-directory munge: every non-alphanumeric character of the
// session cwd becomes '-', per character, with no run-collapsing
// ('/tmp/pdf2md__logotr_' -> '-tmp-pdf2md--logotr-').
function mungePath(p) {
  let out = '';
  for (const ch of p) out += /[A-Za-z0-9]/.test(ch) ? ch : '-';
  return out;
}

// Splits incoming byte chunks into complete UTF-8 lines. Buffers the trailing
// partial line as bytes (never decodes a split UTF-8 sequence). Oversized lines
// are skipped without decoding; an over-cap partial buffer is discarded and the
// reader resyncs at the next newline.
class LineBuffer {
  constructor() {
    this.partial = Buffer.alloc(0);
    this.discarding = false;
  }

  reset() {
    this.partial = Buffer.alloc(0);
    this.discarding = false;
  }

  // Call when the next pushed bytes start mid-line (tail rebuild): everything up
  // to and including the first newline is dropped.
  startMidLine() {
    this.partial = Buffer.alloc(0);
    this.discarding = true;
  }

  push(buf) {
    const data = this.partial.length ? Buffer.concat([this.partial, buf]) : buf;
    const lines = [];
    let start = 0;
    for (;;) {
      const nl = data.indexOf(0x0a, start);
      if (nl === -1) break;
      if (this.discarding) {
        this.discarding = false; // dropped through the resync newline
      } else {
        const len = nl - start;
        if (len > 0 && len <= LIMITS.MAX_LINE) {
          lines.push(data.toString('utf8', start, nl));
        }
      }
      start = nl + 1;
    }
    if (this.discarding) {
      this.partial = Buffer.alloc(0); // still inside a discarded line
    } else {
      this.partial = Buffer.from(data.subarray(start));
      if (this.partial.length > LIMITS.MAX_PARTIAL) {
        this.partial = Buffer.alloc(0);
        this.discarding = true;
      }
    }
    return lines;
  }
}

// Delimiters scanned in priority order; at equal positions the earlier entry
// wins (``` before `). Code is kept as literal text and never math-scanned.
const DELIMS = [
  { open: '```', close: '```', kind: 'code', sameLine: false },
  { open: '`', close: '`', kind: 'code', sameLine: true },
  { open: '$$', close: '$$', kind: 'math', mode: 'display', sameLine: false },
  { open: '\\[', close: '\\]', kind: 'math', mode: 'display', sameLine: false },
  { open: '\\(', close: '\\)', kind: 'math', mode: 'inline', sameLine: false },
];

// Segments one text block into ordered spans: {t:'text',s} | {t:'math',m,s}.
// Concatenating text spans plus delimited math reconstructs the input.
function segment(text) {
  const spans = [];
  let textBuf = '';
  const flush = () => {
    if (textBuf) {
      spans.push({ t: 'text', s: textBuf });
      textBuf = '';
    }
  };
  let i = 0;
  while (i < text.length) {
    let best = null;
    for (const d of DELIMS) {
      const idx = text.indexOf(d.open, i);
      if (idx !== -1 && (best === null || idx < best.idx)) best = { d, idx };
    }
    if (!best) {
      textBuf += text.slice(i);
      break;
    }
    const { d, idx } = best;
    textBuf += text.slice(i, idx);
    const bodyStart = idx + d.open.length;
    let closeIdx = text.indexOf(d.close, bodyStart);
    if (closeIdx !== -1 && d.sameLine) {
      const nl = text.indexOf('\n', bodyStart);
      if (nl !== -1 && closeIdx > nl) closeIdx = -1;
    }
    if (closeIdx === -1) {
      if (d.kind === 'code' && !d.sameLine) {
        textBuf += text.slice(idx); // unterminated fence: rest is code
        break;
      }
      textBuf += d.open; // unclosed delimiter is literal text
      i = bodyStart;
      continue;
    }
    const end = closeIdx + d.close.length;
    if (d.kind === 'code') {
      textBuf += text.slice(idx, end); // code shown verbatim, delimiters included
    } else {
      flush();
      const body = text.slice(bodyStart, closeIdx).trim();
      if (body) spans.push({ t: 'math', m: d.mode, s: body });
    }
    i = end;
  }
  flush();
  return spans;
}

// segment() plus the resource limits: message truncation (visible marker),
// over-size math dropped (never rendered truncated), over-count math inert.
function blockToSpans(text) {
  let truncated = false;
  if (text.length > LIMITS.MAX_TEXT) {
    text = text.slice(0, LIMITS.MAX_TEXT);
    truncated = true;
  }
  const out = [];
  let mathCount = 0;
  for (const sp of segment(text)) {
    if (sp.t === 'math') {
      if (sp.s.length > LIMITS.MAX_MATH_SPAN) {
        out.push({ t: 'text', s: '[formula omitted: size limit exceeded]' });
        continue;
      }
      mathCount += 1;
      if (mathCount > LIMITS.MAX_MATH_PER_MSG) {
        out.push({ t: 'text', s: sp.s });
        continue;
      }
    }
    out.push(sp);
  }
  if (truncated) out.push({ t: 'text', s: '\n[message truncated: size limit]' });
  return out;
}

function makeMessage(rec, role, text) {
  return {
    ts: typeof rec.timestamp === 'string' ? rec.timestamp : '',
    role,
    spans: blockToSpans(text),
  };
}

// One JSONL line -> { messages: [...], unexpected: bool }. `unexpected` marks a
// record we should consume but whose shape we don't recognize (drives the
// "format may have changed" notice); records we deliberately skip don't set it.
function parseLine(line, opts) {
  let rec;
  try {
    rec = JSON.parse(line);
  } catch {
    return { messages: [], unexpected: false };
  }
  const none = { messages: [], unexpected: false };
  if (!rec || typeof rec !== 'object' || Array.isArray(rec)) {
    return { messages: [], unexpected: true };
  }
  if (rec.isSidechain === true) return none; // subagent traffic
  if (rec.type === 'assistant') {
    const content = rec.message && rec.message.content;
    if (!Array.isArray(content)) return { messages: [], unexpected: true };
    const messages = [];
    for (const b of content) {
      if (!b || typeof b !== 'object' || b.type !== 'text') continue; // skip thinking/tool_use
      if (typeof b.text !== 'string' || b.text.trim() === '') continue;
      messages.push(makeMessage(rec, 'assistant', b.text));
    }
    return { messages, unexpected: false };
  }
  if (rec.type === 'user') {
    if (!opts || !opts.includeUser) return none;
    if (rec.isMeta === true) return none;
    if (rec.toolUseResult !== undefined) return none; // tool result, not a prompt
    const content = rec.message && rec.message.content;
    if (typeof content !== 'string') return none; // array content = tool results
    const s = content.trimStart();
    if (
      !s ||
      s.startsWith('<command-') ||
      s.startsWith('<local-command') ||
      s.startsWith('<system-reminder>')
    ) {
      return none; // harness bookkeeping, not something the user typed
    }
    return { messages: [makeMessage(rec, 'user', content)], unexpected: false };
  }
  return none; // other record types are bookkeeping
}

module.exports = { LIMITS, mungePath, LineBuffer, segment, blockToSpans, parseLine };
