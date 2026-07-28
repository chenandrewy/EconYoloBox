// Pure active-terminal process helpers for MathPanel.
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

function claudeSessionForProcessTree(rootPid, sessionDir, opts) {
  const procFs = (opts && opts.fs) || fs;
  const procRoot = (opts && opts.procRoot) || '/proc';
  const states = [];
  for (const pid of processTreePids(rootPid, { fs: procFs, procRoot })) {
    let state;
    try {
      state = JSON.parse(
        procFs.readFileSync(path.join(sessionDir, `${pid}.json`), 'utf8'),
      );
    } catch {
      continue;
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
      continue;
    }
    // Claude records Linux /proc starttime to distinguish a live process from
    // an old state file whose PID has since been reused.
    if (
      typeof state.procStart === 'string' &&
      state.procStart !== procStart(procFs, procRoot, pid)
    ) {
      continue;
    }
    states.push({
      pid,
      sessionId: state.sessionId,
      cwd: state.cwd,
      kind: typeof state.kind === 'string' ? state.kind : '',
    });
  }
  return states.find((state) => state.kind === 'interactive') || states[0];
}

module.exports = {
  processTreePids,
  openJsonlBasenames,
  candidateForProcessTree,
  claudeSessionForProcessTree,
};
