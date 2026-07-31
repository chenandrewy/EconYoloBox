// Run: `node --test .tools/chatrender/extension/test/active-terminal.test.js`.
// Input: a synthetic /proc process tree and workspace-validated candidates.
// Output: assertions for active terminal transcript selection.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  processTreePids,
  openJsonlBasenames,
  candidateForProcessTree,
  claudeSessionForProcessTree,
} = require('../active-terminal');

function fakeProc(children, fds, files = {}, dirs = {}) {
  return {
    readFileSync(p) {
      if (files[p] !== undefined) return files[p];
      const match = p.match(/^\/fake\/(\d+)\/task\/\1\/children$/);
      if (!match || children[match[1]] === undefined) throw new Error('ENOENT');
      return children[match[1]];
    },
    readdirSync(p) {
      if (dirs[p] !== undefined) return dirs[p];
      const match = p.match(/^\/fake\/(\d+)\/fd$/);
      if (!match || fds[match[1]] === undefined) throw new Error('ENOENT');
      return Object.keys(fds[match[1]]);
    },
    readlinkSync(p) {
      const match = p.match(/^\/fake\/(\d+)\/fd\/(.+)$/);
      if (!match || !fds[match[1]] || fds[match[1]][match[2]] === undefined) {
        throw new Error('ENOENT');
      }
      return fds[match[1]][match[2]];
    },
  };
}

function procStat(pid, name, start) {
  return `${pid} (${name}) S ${Array(18).fill('0').join(' ')} ${start}`;
}

test('process tree: walks terminal descendants and tolerates exited processes', () => {
  const procFs = fakeProc({ 10: '11 12', 11: '13', 13: '' }, {});
  assert.deepEqual(processTreePids(10, { fs: procFs, procRoot: '/fake' }), [
    10, 11, 12, 13,
  ]);
  assert.deepEqual(processTreePids(undefined, { fs: procFs, procRoot: '/fake' }), []);
});

test('open transcripts: keeps JSONL basenames across replaced file aliases', () => {
  const procFs = fakeProc(
    { 20: '21', 21: '' },
    {
      20: { 0: '/dev/pts/1' },
      21: {
        3: '/run/host/rollout-2026-07-28-session-a.jsonl',
        4: '/run/host/session-b.jsonl (deleted)',
        5: '/run/host/state.sqlite',
      },
    },
  );
  assert.deepEqual(
    [...openJsonlBasenames(20, { fs: procFs, procRoot: '/fake' })].sort(),
    ['rollout-2026-07-28-session-a.jsonl', 'session-b.jsonl'],
  );
});

test('candidate selection: matches only workspace-validated candidates', () => {
  const procFs = fakeProc(
    { 30: '31', 31: '' },
    {
      30: {},
      31: {
        7: '/different-alias/rollout-2026-07-28-session-a.jsonl',
        8: '/different-alias/unrelated.jsonl',
      },
    },
  );
  const candidates = [
    {
      path: '/logical/codex/rollout-2026-07-28-session-a.jsonl',
      source: 'codex',
      mtimeMs: 100,
    },
    {
      path: '/logical/claude/session-b.jsonl',
      source: 'claude',
      mtimeMs: 200,
    },
  ];
  assert.equal(
    candidateForProcessTree(30, candidates, { fs: procFs, procRoot: '/fake' }),
    candidates[0],
  );
  assert.equal(
    candidateForProcessTree(
      30,
      [{ path: '/logical/codex/not-open.jsonl', source: 'codex', mtimeMs: 300 }],
      { fs: procFs, procRoot: '/fake' },
    ),
    undefined,
  );
});

test('Claude session: resolves the interactive state for a live descendant PID', () => {
  const sessionId = '11111111-2222-4333-8444-555555555555';
  const procFs = fakeProc(
    { 40: '41 42', 41: '', 42: '' },
    {},
    {
      '/fake/41/stat': procStat(41, 'claude-agent', '4100'),
      '/fake/42/stat': procStat(42, 'claude', '4200'),
      '/sessions/41.json': JSON.stringify({
        pid: 41,
        sessionId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        cwd: '/workspace/project',
        procStart: '4100',
        kind: 'agent',
      }),
      '/sessions/42.json': JSON.stringify({
        pid: 42,
        sessionId,
        cwd: '/workspace/project/subdir',
        procStart: '4200',
        kind: 'interactive',
      }),
    },
  );
  assert.deepEqual(
    claudeSessionForProcessTree(40, '/sessions', {
      fs: procFs,
      procRoot: '/fake',
    }),
    {
      pid: 42,
      sessionId,
      cwd: '/workspace/project/subdir',
      kind: 'interactive',
    },
  );
});

test('Claude session: rejects stale PID state and unsafe metadata', () => {
  const procFs = fakeProc(
    { 50: '51 52', 51: '', 52: '' },
    {},
    {
      '/fake/51/stat': procStat(51, 'claude', 'new-start'),
      '/fake/52/stat': procStat(52, 'claude', '5200'),
      '/sessions/51.json': JSON.stringify({
        pid: 51,
        sessionId: '11111111-2222-4333-8444-555555555555',
        cwd: '/workspace/project',
        procStart: 'old-start',
        kind: 'interactive',
      }),
      '/sessions/52.json': JSON.stringify({
        pid: 52,
        sessionId: '../../outside',
        cwd: 'relative/project',
        procStart: '5200',
        kind: 'interactive',
      }),
    },
  );
  assert.equal(
    claudeSessionForProcessTree(50, '/sessions', {
      fs: procFs,
      procRoot: '/fake',
    }),
    undefined,
  );
});

test('Claude session: follows an interactive terminal into its parked background job', () => {
  const parkedSessionId = '191aa71b-3593-4d37-84c5-a59131e9567c';
  const procFs = fakeProc(
    { 60: '61', 61: '' },
    {},
    {
      '/fake/61/stat': procStat(61, 'claude', '6100'),
      '/fake/99/stat': procStat(99, 'claude-bg', '9900'),
      '/sessions/61.json': JSON.stringify({
        pid: 61,
        sessionId: '11111111-2222-4333-8444-555555555555',
        cwd: '/workspace/project',
        procStart: '6100',
        kind: 'interactive',
        parkedJobId: '191aa71b',
      }),
      '/sessions/99.json': JSON.stringify({
        pid: 99,
        sessionId: parkedSessionId,
        cwd: '/workspace/project',
        procStart: '9900',
        kind: 'bg',
        jobId: '191aa71b',
      }),
    },
    { '/sessions': ['61.json', '99.json'] },
  );
  assert.deepEqual(
    claudeSessionForProcessTree(60, '/sessions', {
      fs: procFs,
      procRoot: '/fake',
    }),
    {
      pid: 99,
      sessionId: parkedSessionId,
      cwd: '/workspace/project',
      kind: 'bg',
    },
  );
});

test('Claude session: ignores a stale parked job and keeps the interactive session', () => {
  const interactiveSessionId = '11111111-2222-4333-8444-555555555555';
  const procFs = fakeProc(
    { 70: '71', 71: '' },
    {},
    {
      '/fake/71/stat': procStat(71, 'claude', '7100'),
      '/fake/98/stat': procStat(98, 'claude-bg', 'new-start'),
      '/sessions/71.json': JSON.stringify({
        pid: 71,
        sessionId: interactiveSessionId,
        cwd: '/workspace/project',
        procStart: '7100',
        kind: 'interactive',
        parkedJobId: '191aa71b',
      }),
      '/sessions/98.json': JSON.stringify({
        pid: 98,
        sessionId: '191aa71b-3593-4d37-84c5-a59131e9567c',
        cwd: '/workspace/project',
        procStart: 'old-start',
        kind: 'bg',
        jobId: '191aa71b',
      }),
    },
    { '/sessions': ['71.json', '98.json'] },
  );
  assert.deepEqual(
    claudeSessionForProcessTree(70, '/sessions', {
      fs: procFs,
      procRoot: '/fake',
    }),
    {
      pid: 71,
      sessionId: interactiveSessionId,
      cwd: '/workspace/project',
      kind: 'interactive',
    },
  );
});
