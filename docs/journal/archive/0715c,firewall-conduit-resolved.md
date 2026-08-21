# Firewall bug conduit resolved: direct clone of anthropics/claude-code, Aug 7–8, 2025

2026-07-15, evening NY time

## How we found it

Copied a batch of old Obsidian notes into `docs/journal/obsidian-copy/` and examined them against the open "conduit unresolved" question in `0715a,firewall-fails-open.md` — i.e., how a Jul 30 – Aug 15, 2025 (pre-fix) vintage of the upstream devcontainer template got into our lineage.

## The answer

`250831 cc-sessions hooks...` and friends are an August 2025 Claude Code learning spree, and one note is the smoking gun: **`250807 CONTAINER Claude code skip permissions rambling.md`** (created 2025-08-07, modified 2025-08-08). It documents, step by step, the first-ever devcontainer setup:

1. Install the Dev Containers extension in Cursor.
2. `gh repo clone anthropics/claude-code` (after a detour through `brew install gh` + login) to get the reference `.devcontainer`.
3. Install Docker Desktop from the dmg.
4. "Reopen in container" against that `.devcontainer` — succeeds after opening one folder up.

Cloned **Aug 7–8, 2025**; upstream's fail-open fix (`6d79459`, postStart + waitFor + REJECT) landed **Aug 20, 2025**. The clone missed the fix by twelve days. Main at clone time simply *was* the buggy template.

## What this corrects in 0715a

1. **Conduit known; the recollection was right.** 0715a floated three hypotheses — old pinned tag, stale fork/tutorial copy, or AI-reproduced from training data — and leaned toward doubting the memory of "pulling from anthropics/". All three were wrong. It was a genuine clone of `anthropics/claude-code` main; 0715a's hidden error was implicitly dating the clone to early 2026 (repo-creation time) instead of Aug 2025 (actual clone time).
2. **First contact with containers moves back six months**: Aug 7–8, 2025, not Feb 11, 2026 (ralph-wiggum-asset-pricing repo creation). The Aug-2025 clone sat on disk and seeded ralph-wiggum the following February, carrying the pre-fix template forward.
3. **The `anthropic.claude-code` extension marker fits cleanly now.** 0715a treated it as the lone post-fix anomaly (upstream added it to the template Aug 27, 2025). It was still added locally — but by someone actively setting up Claude Code in Cursor that very week, exactly what the notes document.

The dating also lands dead-center in the Jul 30 – Aug 15 vintage window 0715a established from four independent code markers: the code forensics and the contemporaneous notes now corroborate each other exactly.

## Misc observations

- The other sixteen notes (Aug 5–31, 2025) are context, not evidence: Context7 MCP setup, subagent prompts, permissions in `settings.local.json`, a multi-day notification-hooks struggle, print mode, a VM-instead-of-Docker idea. They confirm the tooling-setup window but say nothing further about the firewall.
- Lesson for future archaeology: "cloned from upstream main" and "cloned from *current* upstream main" are different claims. The recollection was accurate; only the assumed date made it look impossible.

Related: `0715a,firewall-fails-open.md`, `docs/journal/obsidian-copy/250807 CONTAINER Claude code skip permissions rambling.md`
