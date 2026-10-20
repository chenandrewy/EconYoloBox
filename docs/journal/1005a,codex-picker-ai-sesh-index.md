# Codex resume picker misses an ai-sesh import

Date: 2026-10-05. Messy investigation notes; no fix applied. Findings from the 16:07 read-only inspection are in the section after Next steps.

## What happened

- The active sync tree is `/yolobox/tools/ai-sesh/data/` in the container (host: `1-SANDBOX/tools/ai-sesh/data/`). The old `workshop/AI-WorkFlow/econyolobox/.tools/ai-sesh/data/` is a stale copy. Initial searches in that old tree were misleading.
- Session `01a10d23-e278-7332-8c95-579b89fd900c` started on `macstudio25` at 13:36 EDT. Its rollout is present under both `data/macstudio25/codex/2026/10/05/` and `data/macbook25/codex/2026/10/05/`. Before resuming, the two files were byte-identical (SHA-256 `11a2afbe0688ec1af304242244953b5892adcce9fb3c58581a0bfe9db0b96015`). The first substantive user request concerns point 2 of `prev-ms-rd2/review/report.txt`.
- A new `ybgpt` session, `01a10d5d-b03c-7643-b3e4-7bcdf8c804d5`, appeared immediately under `data/macbook25/codex/2026/10/05/`. Both sessions record cwd `/yolobox/workshop/Ref,MS`, source `vscode`, and Codex CLI version `0.160.0`.
- In the new session's resume picker, with `Cwd` and `Active` selected, `01a10d23` was absent. Direct `gptchat-yolo resume 01a10d23-e278-7332-8c95-579b89fd900c` worked. The macbook copy then grew from 2,157,499 to 2,159,421 bytes, modified at 14:49 EDT. We have not checked the picker again after this resume.

## Likely mechanism, not yet confirmed in the container DB

`tools/ai-sesh/sesh-push` copies only `*.jsonl` rollouts. It does not copy or register Codex's `~/.codex/state_5.sqlite` thread rows or `~/.codex/session_index.jsonl`. Codex 0.160's startup state backfill returns when marked complete, and its picker can list from the local state DB. Direct resume can find a rollout by ID and has a read-repair path. Thus the rollout may be usable before it is indexed for browsing. Similar direct-resume-works/picker-misses-session bugs are reported in openai/codex issues #20165 and #28068. These reports do not prove which index is missing here.

The Mac-side attempt to inspect the running container through Docker returned socket `permission denied`; no container DB or index was changed. Do not infer corruption from the missing picker row.

## Next steps

1. **MacBook25 (YOLO container):** Exit the resumed session and reopen the picker. Check `All` as well as `Cwd`, search for `01a10d23` and for its title, and record whether the successful direct resume made it appear. This separates a one-time registration delay from a persistent import problem. ✅ With `All`, `01a10d23` appears (screenshot 15:56). `Cwd` was not rechecked.
2. **MacBook25 (YOLO container):** If absent, inspect that container's `~/.codex/state_5.sqlite` `threads` row and `~/.codex/session_index.jsonl` for the exact ID, read-only. Record `id`, `title`, `cwd`, `source`, `archived`, and `rollout_path`; verify the path exists. Do this before changing any index or database. Check whether `01a10d44-f9a4-7400-a4f0-ddb487a12cd0`, another imported session from today, is similarly absent. **MacStudio25:** Its original rollout is a reference for file comparison; its local index is not the one driving the MacBook picker. ✅ Rows now exist for both; see Findings.
3. **MacBook25 (investigation and any local repair):** If metadata is missing, investigate a supported Codex import/reindex route for version 0.160. No safe one-command reindex has been verified yet. Do **not** copy `state_5.sqlite` from MacStudio25: rollout paths and other state are machine-local. Back up MacBook25's local metadata before any repair and avoid modifying it while Codex is active. ✅ No reindex command exists; Codex's own read-repair is the working route. See Findings.
4. **MacBook25 (development and first validation), then MacStudio25 (reverse-direction validation):** Once an import method is verified, extend the shared `sesh-push` script so each successful Codex `install` or `fast-forward` also registers or refreshes that destination machine's local session metadata. Keep the operation idempotent and preserve its existing divergence behavior. Verify on a disposable Codex home on MacBook25: copied rollout, picker visibility, direct resume, repeat push, and divergent copy handling. After Dropbox settles, test MacStudio25 importing a MacBook25 session and seeing it in the MacStudio25 picker.
5. **MacBook25 (YOLO container):** If the row exists in both local indexes but the picker still hides it, inspect Codex's source/status/cwd filtering and logs for a picker bug. Keep the exact rollout and metadata evidence for an upstream issue. Avoid publishing transcript contents.

Relevant source: `tools/ai-sesh/{README.md,sesh-push,_common.sh}`; Codex 0.160 `codex-rs/rollout/src/state_db.rs` in `openai/codex`.

## Findings, 16:07 EDT (MacBook25 YOLO container, read-only)

Method: copied `state_5.sqlite` (+ `-wal`, `-shm`) and `logs_2.sqlite` to a scratchpad and queried the copies. Nothing under `~/.codex` was modified.

- **Rows exist now.** `threads` has rows for `01a10d23` and `01a10d44`, each with cwd `/yolobox/workshop/Ref,MS`, source `vscode`, `archived=0`, and a `rollout_path` that exists. `session_index.jsonl` (21 lines) holds only named threads (`thread_name`), so its lack of these IDs is irrelevant to the picker. Of 963 rollouts on disk, 10 have no row: 9 guardian subagents and 1 two-line fork stub (`01a10c19`). No row lacks a file.
- **`sesh-push` ran at 14:20:09–10** and wrote 80 Codex rollouts, all present under `macstudio25`. Their mtimes are 14:20:09–10 because `_common.sh` copies with `install -m 600`, which does not preserve mtime.
- **Codex did not register them at startup.** `backfill_state` is `complete` with a 09-25 watermark, so startup does not rescan.
- **One picker listing repaired all 80 at 15:52:49.** `logs_2.sqlite` shows one `thread/list` request followed by 80 `WARN codex_rollout::state_db: state db discrepancy during read_repair_rollout_path: upsert_needed (slow path)` lines, each paired with `Resuming rollout from …`. The 80 include `01a10d44`, which was never opened on this machine. `01a10d23` is not among them; its direct resume at 14:49:14 (`thread/resume` in the log) had already repaired it.
- **Repair takes `updated_at`/`recency_at` from file mtime.** All 80 rows got 14:20:09–10, which is why the picker shows "1h ago" for nearly everything and sorting by Updated is meaningless for imported sessions.
- **No reindex command in 0.160.** `codex --help` lists none. `doctor` only diagnoses; `migrate-rollouts` converts legacy sessions to paginated history (a different job) and was not run.
- **Not confirmed:** why the 14:40 picker missed `01a10d23`. `logs_2.sqlite` has no `thread/list` entries before 15:51, so that request is unrecorded. Hypothesis: the `Cwd` view lists from the state DB only, while `All` scans rollouts and read-repairs. All rows are repaired now, so testing needs a fresh import.

## Revised next steps (supersede 4–5 above)

A. **Test the Cwd hypothesis on a fresh import.** On MacStudio25, create a throwaway Codex session in a test project; after Dropbox settles, run `sesh-push` on MacBook25 and, before any resume, open the picker with `Cwd` in that project. Then switch to `All`. Copy `logs_2.sqlite` afterward and check whether the `Cwd` listing logged read-repair warnings. This decides whether the picker bug is in the `Cwd` path.
B. **Preserve mtime in `sesh-push`.** Change `install -m 600` to `install -p -m 600` (or `cp -p` + `chmod`) in `_common.sh` for install and fast-forward, so repaired rows sort by when the session was last used. Verify in a disposable `CODEX_HOME`/`CODEX_SESSIONS_DIR`. Existing 14:20 rows will not re-sort unless their files are re-pushed or touched to the source mtime.
C. **Registration step in `sesh-push`, only if A shows `Cwd` never repairs.** Preferred route is Codex itself (e.g. a listing call that triggers read-repair after a push), not direct SQL into `state_5.sqlite`. If no supported trigger exists, document "open the picker with All once after `sesh-push`" in the ai-sesh README instead.
D. **Upstream issue, if A confirms it.** Report "`Cwd` resume picker omits rollouts lacking state-DB rows; `All` read-repairs them" with the log lines above; no transcript contents.
