# MathPanel v0.2: follow Codex CLI sessions too — plan for the implementing agent

**Date:** 2026-07-23
**Status:** plan agreed, not built. Builds on the shipped MathPanel v0.1
(`.tools/mathpanel/`, design in `0723a,mathpanel-transcript.md`). Read that
first — every constraint there (read-only, fail-soft, no network, no writes
outside the extension folder, no npm install, synthetic-fixtures-only) carries
over unchanged.

## Goal

The panel currently follows the active **Claude Code** session transcript for
the workspace. Add the ability to follow the active **Codex CLI** session as
well. One panel; it follows whichever session file (Claude or Codex) was
written to most recently — same most-recent-mtime rule v0.1 already uses among
Claude sessions. A source toggle is a later nicety, not v0.2.

## What is already done and must not be re-litigated

- Rendering, segmentation, limits, webview, CSP, KaTeX: all source-agnostic and
  finished. `transcript.js` exposes `blockToSpans(text)` → spans and the
  message shape `{ts, role, spans}`; the webview validates and renders that
  shape. **Reuse `blockToSpans`; do not write a second segmenter.**
- Delimiters (updated today, after 0723a): `$$…$$`, `\[…\]` display; `\(…\)`
  and single-`$…$` inline (Pandoc-style guards: same line, no whitespace just
  inside delimiters, no digit after the closing `$`, `\$` ignored, code spans
  never math-scanned). This already covers both Claude's habits (mostly `$…$`)
  and GPT-family habits (mostly `\(…\)`/`\[…\]`). No delimiter work needed.
- User prompts are shown interleaved (`INCLUDE_USER = true` in
  `extension.js`); do the same for Codex user messages.

## Verified facts about Codex session storage (2026-07-23, this machine)

Checked directly against `~/.codex/sessions/` (430 files):

- Layout is **by date, not by project**:
  `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-timestamp>-<uuid>.jsonl`.
- One JSON object per line. Top-level record types observed (3 recent files):
  `session_meta`, `response_item`, `event_msg`, `turn_context`, `world_state`.
  Records carry a `payload` object; interesting payload types:
  - `response_item` / `message`, `reasoning`, `custom_tool_call`,
    `custom_tool_call_output`
  - `event_msg` / `agent_message`, `user_message`, `token_count`,
    `task_started`, `task_complete`, `thread_settings_applied`
- `session_meta.payload` keys include **`cwd`** (the workspace binding we
  need), plus `id`, `session_id`, `timestamp`, `forked_from_id`, `git`,
  `source`, `model_provider`, `cli_version`, `base_instructions`, …
  `session_meta` is (at least in observed files) the **first line** of the
  file.

## Design (agreed in conversation)

### Discovery: a second strategy alongside the Claude one

- Scan `~/.codex/sessions/<last N days>` of date dirs (suggest N=7; the dirs
  are small). For each `rollout-*.jsonl`, read **only the first line**, parse
  `session_meta.payload.cwd`, and keep files whose cwd matches the workspace
  folder (realpath'd, same as v0.1 does for Claude).
- A file's cwd never changes → **caching the per-file cwd is safe and
  encouraged**, keyed by `(path, inode)`. This is unlike the Claude side's
  "never cache the realpath of `~/.claude/projects`" rule — that rule is about
  the symlinked *directory*, not about per-file metadata. Still always open
  files via the logical `~/.codex/...` path each time (ai-sesh syncs Codex
  stores too; check whether `~/.codex/sessions` is a symlink at build time and
  behave identically either way).
- Candidate set = Claude candidates (existing munge-dir scan) ∪ Codex
  candidates (cwd-matched rollouts). Follow the single file with the newest
  mtime across both. Everything downstream of selection (watchFile,
  inode/size incremental read, LineBuffer, rebuild-from-tail) is
  source-independent and reused as-is; the only per-source piece after
  discovery is the record normalizer.

### Normalizer: `codex.js`, a pure module beside `transcript.js`

Maps one Codex JSONL line → `{ messages: [...], unexpected: bool }`, the exact
return shape of `transcript.js#parseLine`, reusing `blockToSpans`. Keep it
`vscode`-free and unit-tested under `node:test` like the Claude one.

**Critical dedup decision to verify first (keys-only inspection, never print
content):** assistant text appears to be logged **twice** — as
`response_item`/`message` and as `event_msg`/`agent_message`. Consume exactly
one or every message renders twice. Determine which record carries the final
canonical text (expect `response_item/message` with `role:"assistant"` and a
content array of `output_text` items; expect user prompts as
`response_item/message` `role:"user"` with `input_text` items or as
`event_msg/user_message` — verify both role paths and pick one family).
Skip `reasoning` (Codex's thinking), tool calls/outputs, `token_count`,
`turn_context`, `world_state`, and any unknown type — fail-soft, `unexpected`
only for records we should consume but can't parse.

### Timestamps

Codex records: check for a per-record timestamp field; if absent, fall back to
`session_meta.payload.timestamp` or empty string. Same NY-time display path in
`extension.js` (`tsDisplay` handles the invalid/missing case already).

## Files touched

```
.tools/mathpanel/extension/
├── codex.js                  # NEW pure module: discovery helpers (first-line
│                             #   session_meta cwd extraction) + line normalizer
├── transcript.js             # unchanged (maybe export a shared helper or two)
├── extension.js              # discovery loop: union of Claude + Codex
│                             #   candidates; per-source normalizer dispatch
├── test/codex.test.js        # NEW node:test against synthetic rollout fixtures
├── fixtures/rollout.jsonl    # NEW small SYNTHETIC rollout records — never
│                             #   real transcript content
└── README.md                 # document Codex support + its v0.2 limitations
```

Version stays `local.mathpanel-0.1.0` install-target-wise unless you decide to
bump; if you bump, update `install-extension.sh`'s target and README/uninstall
paths together.

## Build order

1. **Verify the Codex record contract** against 2–3 real rollout files
   (keys/types only): the `response_item/message` content-array shape for both
   roles, the agent_message duplication question, per-record timestamps,
   whether files are append-only (watchFile/inode logic assumes append +
   occasional replace), and whether `session_meta` is guaranteed line 1.
   Model synthetic fixtures on what you find.
2. Write `codex.js` + `test/codex.test.js`; green under `node --test`.
3. Wire discovery union + dispatch in `extension.js`.
4. Reinstall (`install-extension.sh` — ask the user first if this conversation
   didn't already authorize an install), reload, and verify: a live Codex
   session with math renders and updates; starting a Claude session afterward
   steals the panel (most-recent rule) and vice versa.
5. Negative checks unchanged from 0723a: no listener (`lsof`), hostile KaTeX
   inputs inert, malformed lines skipped.

## Accepted risks / notes for the implementer

- Two vendors' undocumented formats instead of one. Fail-soft everywhere: a
  Codex format change must degrade to "panel doesn't show Codex" — never crash
  or block the Claude path.
- First-line reads during discovery are new file opens (~a few dozen per scan,
  once per second). With per-(path,inode) caching, steady-state cost is one
  readdir over a handful of date dirs — fine. Do not recursively scan all of
  `~/.codex/sessions`.
- The panel reads Codex transcripts read-only via the logical path; never
  write under `~/.codex/`, mirroring the `~/.claude/` rule.
- `forked_from_id` sessions (`gpt-fork` in ai-sesh) look like normal files with
  their own cwd; no special handling expected — verify one at build time.
