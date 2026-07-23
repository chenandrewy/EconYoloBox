'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  recentSessionDateParts,
  sessionMetaFromLine,
  cachedSessionMeta,
  parseLine,
} = require('../codex');

const OPTS = { includeUser: true, sessionTimestamp: '2026-07-23T17:00:00.000Z' };

function line(type, payload, timestamp) {
  const rec = { type, payload };
  if (timestamp !== undefined) rec.timestamp = timestamp;
  return JSON.stringify(rec);
}

test('discovery dates: New York calendar window is stable at UTC and DST boundaries', () => {
  assert.deepEqual(
    recentSessionDateParts(Date.parse('2026-07-24T01:30:00.000Z'), 3),
    [
      ['2026', '07', '24'],
      ['2026', '07', '23'],
      ['2026', '07', '22'],
      ['2026', '07', '21'],
    ],
  );
  assert.deepEqual(
    recentSessionDateParts(Date.parse('2026-03-09T00:30:00.000Z'), 3),
    [
      ['2026', '03', '09'],
      ['2026', '03', '08'],
      ['2026', '03', '07'],
      ['2026', '03', '06'],
    ],
  );
});

test('metadata cache: negative result is reused until the file size changes', () => {
  const cache = new Map();
  let reads = 0;
  let firstLine;
  const read = () => {
    reads += 1;
    return firstLine;
  };

  assert.equal(cachedSessionMeta(cache, '/logical/rollout.jsonl', 7, 10, read), undefined);
  assert.equal(cachedSessionMeta(cache, '/logical/rollout.jsonl', 7, 10, read), undefined);
  assert.equal(reads, 1);

  firstLine = line('session_meta', {
    cwd: '/workspace/project',
    timestamp: '2026-07-23T18:00:00.000Z',
  });
  assert.deepEqual(cachedSessionMeta(cache, '/logical/rollout.jsonl', 7, 11, read), {
    cwd: '/workspace/project',
    timestamp: '2026-07-23T18:00:00.000Z',
  });
  assert.equal(reads, 2);

  // A positive result is immutable for this path+inode and survives later growth.
  assert.deepEqual(cachedSessionMeta(cache, '/logical/rollout.jsonl', 7, 99, read), {
    cwd: '/workspace/project',
    timestamp: '2026-07-23T18:00:00.000Z',
  });
  assert.equal(reads, 2);
});

test('metadata cache: malformed first line is negatively cached by size', () => {
  const cache = new Map();
  let reads = 0;
  const read = () => {
    reads += 1;
    return line('future_meta_type', { cwd: '/workspace/project' });
  };
  assert.equal(cachedSessionMeta(cache, '/logical/bad.jsonl', 8, 20, read), undefined);
  assert.equal(cachedSessionMeta(cache, '/logical/bad.jsonl', 8, 20, read), undefined);
  assert.equal(reads, 1);
});

test('session metadata: extracts immutable cwd and timestamp from first line', () => {
  const meta = sessionMetaFromLine(
    line(
      'session_meta',
      {
        cwd: '/workspace/real-project',
        timestamp: '2026-07-23T18:00:00.000Z',
        forked_from_id: 'synthetic-parent',
      },
      '2026-07-23T18:00:01.000Z',
    ),
  );
  assert.deepEqual(meta, {
    cwd: '/workspace/real-project',
    timestamp: '2026-07-23T18:00:00.000Z',
  });
});

test('session metadata: malformed or changed first lines fail soft', () => {
  assert.equal(sessionMetaFromLine('{'), undefined);
  assert.equal(sessionMetaFromLine('[]'), undefined);
  assert.equal(sessionMetaFromLine(line('event_msg', { cwd: '/workspace' })), undefined);
  assert.equal(sessionMetaFromLine(line('session_meta', { cwd: 42 })), undefined);
});

test('assistant: canonical response item renders output_text via shared segmenter', () => {
  const r = parseLine(
    line(
      'response_item',
      {
        type: 'message',
        role: 'assistant',
        content: [{ type: 'output_text', text: 'By \\(a=b\\), so $$c=d$$.' }],
      },
      '2026-07-23T18:00:04.000Z',
    ),
    OPTS,
  );
  assert.equal(r.unexpected, false);
  assert.deepEqual(r.messages, [
    {
      ts: '2026-07-23T18:00:04.000Z',
      role: 'assistant',
      spans: [
        { t: 'text', s: 'By ' },
        { t: 'math', m: 'inline', s: 'a=b' },
        { t: 'text', s: ', so ' },
        { t: 'math', m: 'display', s: 'c=d' },
        { t: 'text', s: '.' },
      ],
    },
  ]);
});

test('dedup: event agent copy and response user context are skipped', () => {
  const assistantCopy = line('event_msg', {
    type: 'agent_message',
    message: 'Duplicated assistant text.',
    phase: 'final_answer',
  });
  const injectedUser = line('response_item', {
    type: 'message',
    role: 'user',
    content: [{ type: 'input_text', text: 'Injected instructions.' }],
  });
  assert.deepEqual(parseLine(assistantCopy, OPTS), { messages: [], unexpected: false });
  assert.deepEqual(parseLine(injectedUser, OPTS), { messages: [], unexpected: false });
});

test('user: event user_message is kept only when enabled', () => {
  const user = line(
    'event_msg',
    { type: 'user_message', message: 'What is $x^2$?', images: [] },
    '2026-07-23T18:00:03.000Z',
  );
  assert.equal(parseLine(user, { includeUser: false }).messages.length, 0);
  assert.deepEqual(parseLine(user, OPTS).messages[0], {
    ts: '2026-07-23T18:00:03.000Z',
    role: 'user',
    spans: [
      { t: 'text', s: 'What is ' },
      { t: 'math', m: 'inline', s: 'x^2' },
      { t: 'text', s: '?' },
    ],
  });
});

test('timestamps: missing per-record timestamp falls back to session metadata', () => {
  const r = parseLine(
    line('response_item', {
      type: 'message',
      role: 'assistant',
      content: [{ type: 'output_text', text: 'Synthetic answer.' }],
    }),
    OPTS,
  );
  assert.equal(r.messages[0].ts, OPTS.sessionTimestamp);
});

test('fail-soft: malformed JSON and unexpected consumable shapes', () => {
  assert.deepEqual(parseLine('{', OPTS), { messages: [], unexpected: false });
  assert.equal(parseLine('123', OPTS).unexpected, true);
  assert.equal(
    parseLine(
      line('response_item', { type: 'message', role: 'assistant', content: 'changed' }),
      OPTS,
    ).unexpected,
    true,
  );
  assert.equal(
    parseLine(line('event_msg', { type: 'user_message', message: ['changed'] }), OPTS)
      .unexpected,
    true,
  );
});

test('bookkeeping: reasoning, tools, and unknown records are ignored', () => {
  for (const sample of [
    line('response_item', { type: 'reasoning', summary: [] }),
    line('response_item', { type: 'custom_tool_call', name: 'test' }),
    line('response_item', { type: 'custom_tool_call_output', output: 'test' }),
    line('event_msg', { type: 'token_count' }),
    line('turn_context', { cwd: '/workspace' }),
    line('world_state', {}),
    line('new_future_type', {}),
  ]) {
    assert.deepEqual(parseLine(sample, OPTS), { messages: [], unexpected: false });
  }
});

test('fixture: synthetic rollout yields one user and one assistant, without duplicates', () => {
  const lines = fs
    .readFileSync(path.join(__dirname, '..', 'fixtures', 'rollout.jsonl'), 'utf8')
    .trimEnd()
    .split('\n');
  assert.deepEqual(sessionMetaFromLine(lines[0]), {
    cwd: '/workspace/example',
    timestamp: '2026-07-23T18:00:00.000Z',
  });
  const messages = lines.flatMap((raw) => parseLine(raw, OPTS).messages);
  assert.deepEqual(
    messages.map((m) => m.role),
    ['user', 'assistant'],
  );
  assert.deepEqual(messages[1].spans, [
    { t: 'text', s: 'Commutativity gives ' },
    { t: 'math', m: 'display', s: 'x+y=y+x' },
    { t: 'text', s: '.' },
  ]);
});
