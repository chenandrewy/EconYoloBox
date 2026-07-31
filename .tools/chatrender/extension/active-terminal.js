// Pure active-terminal process helpers for ChatRender.
// Input: a terminal root PID, workspace-validated transcript candidates, and
// optionally an injected /proc reader for tests.
// Output: the candidate whose JSONL basename is open in that process tree, or
// the live Claude session metadata registered for a process in that tree.
'use strict';

const fs = require('fs');
const path = require('path');

const MAX_PROCESSES = 512;
const DELETED_SUFFIX = ' (deleted)';
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const JOB_ID = /^[0-9a-f]{8}$/i;

function childPids(procFs, procRoot, pid) {
  let raw;
  try {
    raw = procFs.readFileSync(
      path.join(procRoot, String(pid), 'task', String(pid), 'children'),
      'utf8',
    );
  } catch {
    return [];
  }
  return String(raw)
    .trim()
    .split(/\s+/)
    .map(Number)
    .filter((value) => Number.isSafeInteger(value) && value > 0);
}

function processTreePids(rootPid, opts) {
  if (!Number.isSafeInteger(rootPid) || rootPid <= 0) return [];
  const procFs = (opts && opts.fs) || fs;
  const procRoot = (opts && opts.procRoot) || '/proc';
  const seen = new Set();
  const queue = [rootPid];
  while (queue.length && seen.size < MAX_PROCESSES) {
    const pid = queue.shift();
    if (seen.has(pid)) continue;
    seen.add(pid);
    for (const child of childPids(procFs, procRoot, pid)) {
      if (!seen.has(child)) queue.push(child);
    }
  }
  return [...seen];
}

function openJsonlBasenames(rootPid, opts) {
  const procFs = (opts && opts.fs) || fs;
  const procRoot = (opts && opts.procRoot) || '/proc';
  const names = new Set();
  for (const pid of processTreePids(rootPid, { fs: procFs, procRoot })) {
    const fdDir = path.join(procRoot, String(pid), 'fd');
    let fds;
    try {
      fds = procFs.readdirSync(fdDir);
    } catch {
      continue;
    }
    for (const fd of fds) {
      let target;
      try {
        target = procFs.readlinkSync(path.join(fdDir, String(fd)));
      } catch {
        continue;
      }
      if (target.endsWith(DELETED_SUFFIX)) {
        target = target.slice(0, -DELETED_SUFFIX.length);
      }
      const name = path.basename(target);
      if (name.endsWith('.jsonl')) names.add(name);
    }
  }
  return names;
}

function candidateForProcessTree(rootPid, candidates, opts) {
  const names = openJsonlBasenames(rootPid, opts);
  let best;
  for (const candidate of candidates || []) {
    if (!candidate || typeof candidate.path !== 'string') continue;
    if (!names.has(path.basename(candidate.path))) continue;
    if (!best || candidate.mtimeMs > best.mtimeMs) best = candidate;
  }
  return best;
}

function procStart(procFs, procRoot, pid) {
  let raw;
  try {
    raw = procFs.readFileSync(path.join(procRoot, String(pid), 'stat'), 'utf8');
  } catch {
    return undefined;
  }
  // Field 2 is parenthesized and may itself contain spaces or parentheses.
  // Everything after its final ")" begins at field 3; starttime is field 22.
  const close = String(raw).lastIndexOf(')');
  if (close === -1) return undefined;
  const fields = String(raw).slice(close + 1).trim().split(/\s+/);
  return fields.length > 19 ? fields[19] : undefined;
}

function readClaudeState(procFs, procRoot, sessionDir, pid) {
  let state;
  try {
    state = JSON.parse(
      procFs.readFileSync(path.join(sessionDir, `${pid}.json`), 'utf8'),
    );
  } catch {
    return undefined;
  }
  if (
    !state ||
    typeof state !== 'object' ||
    Array.isArray(state) ||
    state.pid !== pid ||
    typeof state.sessionId !== 'string' ||
    !SESSION_ID.test(state.sessionId) ||
    typeof state.cwd !== 'string' ||
    !path.isAbsolute(state.cwd)
  ) {
    return undefined;
  }
  // Claude records Linux /proc starttime to distinguish a live process from
  // an old state file whose PID has since been reused.
  if (
    typeof state.procStart === 'string' &&
    state.procStart !== procStart(procFs, procRoot, pid)
  ) {
    return undefined;
  }
  return {
    pid,
    sessionId: state.sessionId,
    cwd: state.cwd,
    kind: typeof state.kind === 'string' ? state.kind : '',
    jobId: typeof state.jobId === 'string' && JOB_ID.test(state.jobId) ? state.jobId : '',
    parkedJobId:
      typeof state.parkedJobId === 'string' && JOB_ID.test(state.parkedJobId)
        ? state.parkedJobId
        : '',
  };
}

function publicClaudeState(state) {
  return {
    pid: state.pid,
    sessionId: state.sessionId,
    cwd: state.cwd,
    kind: state.kind,
  };
}

function parkedClaudeState(procFs, procRoot, sessionDir, jobId) {
  let names;
  try {
    names = procFs.readdirSync(sessionDir);
  } catch {
    return undefined;
  }
  let checked = 0;
  for (const name of names) {
    if (!/^\d+\.json$/.test(name)) continue;
    checked += 1;
    if (checked > MAX_PROCESSES) break;
    const pid = Number(name.slice(0, -'.json'.length));
    const state = readClaudeState(procFs, procRoot, sessionDir, pid);
    if (state && state.kind === 'bg' && state.jobId === jobId) return state;
  }
  return undefined;
}

function claudeSessionForProcessTree(rootPid, sessionDir, opts) {
  const procFs = (opts && opts.fs) || fs;
  const procRoot = (opts && opts.procRoot) || '/proc';
  const states = [];
  for (const pid of processTreePids(rootPid, { fs: procFs, procRoot })) {
    const state = readClaudeState(procFs, procRoot, sessionDir, pid);
    if (state) states.push(state);
  }
  const active = states.find((state) => state.kind === 'interactive') || states[0];
  if (!active) return undefined;
  if (active.parkedJobId) {
    const parked = parkedClaudeState(
      procFs,
      procRoot,
      sessionDir,
      active.parkedJobId,
    );
    if (parked) return publicClaudeState(parked);
  }
  return publicClaudeState(active);
}

module.exports = {
  processTreePids,
  openJsonlBasenames,
  candidateForProcessTree,
  claudeSessionForProcessTree,
};
