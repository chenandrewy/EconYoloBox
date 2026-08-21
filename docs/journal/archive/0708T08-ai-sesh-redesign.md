# ai-sesh redesign: symlink-based machine switching

*2026-07-08, ~8am ET. Messy design notes.*

## Goal

Frictionless machine switching between two machines (M4, M3 Ultra) whose
`/workspace` is synced via Dropbox. Work a session on one, walk to the other,
resume it. **History beyond 30 days is explicitly NOT a goal** — the built-in
Claude Code purge (`cleanupPeriodDays`, default 30) self-trims each machine's
mirror, which is fine/welcome here.

Context: current ai-sesh uses a single `data/` staging cache with manual
`sesh-grab` / `sesh-push` / `sesh-wipe`. This redesign kills the manual grab
step by making each machine's live store *be* a folder in the synced tree.

## Core mechanism: symlink home -> workspace

Point the symlink **home -> workspace** (NOT the reverse). Reverse direction
(`data/<machine>` -> `~/.claude/projects`) produces a dangling link on the
other machine — the link text travels but its target doesn't exist there.
Home->workspace makes Claude write *real bytes* into the synced tree.

Per machine:
- `~/.claude/projects` -> `/workspace/.tools/ai-sesh/data/<machine>/claude`
- `~/.codex/sessions`  -> `/workspace/.tools/ai-sesh/data/<machine>/codex`
- `~/.claude/todos`    -> `/workspace/.tools/ai-sesh/data/<machine>/todos`
  (optional — include if you want todo state to travel with a resumed session)

Set up in devcontainer provisioning so a rebuild re-links; data lives in the
persistent `/workspace` mount and survives rebuilds. This also solves the
container-rebuild wipe problem for free.

**Kept machine-local, never symlinked:** `.credentials.json`, caches, and
`history.jsonl` (per-machine up-arrow recall).

## File structure

```
/workspace/.tools/ai-sesh/
├── README.md
├── _common.sh
├── sesh-push          # install ANOTHER machine's session into your home store
├── cc-fork            # fork a Claude seed (mints new UUID)
├── gpt-fork           # fork a Codex seed
└── data/
    ├── m4/                              # machine id
    │   ├── claude/                      # <- ~/.claude/projects links here
    │   │   └── <project-key>/           #    e.g. -workspace-Disc-ABFR
    │   │       └── <uuid>.jsonl
    │   ├── codex/                       # <- ~/.codex/sessions links here
    │   │   └── YYYY/MM/DD/*.jsonl
    │   └── todos/                       # <- ~/.claude/todos links here (optional)
    │       └── <uuid>-agent-*.json
    └── m3ultra/
        ├── claude/…
        ├── codex/…
        └── todos/…
```

Top-level partition changes from per-**project** (old) to per-**machine** (new).
Under each machine, the tree mirrors the relevant parts of `~/.claude` /
`~/.codex` exactly.

## Storage (measured)

- This machine's `~/.claude/projects` = 103 MB (90 MB jsonl, 99 files), oldest
  file 27 days old — i.e. already a steady-state ~30-day window.
- Heavily skewed: two projects (ABFR 50 MB, Washington 32 MB) = 80% of bytes;
  one single jsonl is 19 MB, median only 213 KB. Footprint tracks
  "do I run long/heavy sessions," not session count.
- ~100 MB per machine steady state, ~200 MB total, held locally on **each**
  machine (Dropbox mirrors both folders everywhere). Trivial for disk.
- Real cost is Dropbox **version history / churn**, not disk: live jsonl is
  appended continuously, so Dropbox re-syncs a growing multi-MB file many
  times and retains prior versions. Account usage could run 2-5x live footprint
  on the big files. Watch churn on the 19 MB-class sessions, not space.

## Cross-machine use

Own machine's sessions are already live in `data/<self>/` — nothing to do. To
pick up a session that originated on the *other* machine, `sesh-push` (or
`cc-fork`/`gpt-fork`) installs it from `data/<other>/` into your own home store
(= `data/<self>/`), where you resume or fork it.

## Push / install decision (per matching session UUID)

Never a blind copy. Cheap-test ladder:

1. **Same id + same size -> skip.** (Decision: NO hash. Equal id + equal size is
   good enough for an append-only log; the equal-size-but-different-bytes case
   is vanishingly unlikely and not worth the cost.)
2. **Different size, shorter is a byte-prefix of longer -> take the longer**
   (fast-forward; this is what normal sequential resume produces).
3. **Different size, not a prefix -> true divergence.** Keep both (suffix-rename
   one) and WARN. Never silently discard.

`mtime` is deliberately **never** used to decide:
- Doesn't skip identical files (Dropbox may re-stamp mtime) — wasted overwrites.
- Clock-skew fragile across machines; length is monotonic and skew-proof.
- Fatally, mtime can't distinguish "newer" from "conflicting" — it would
  silently clobber divergent work. Length/prefix is the only signal that
  *detects* the case where any tiebreaker is unsafe.

## Operating rule

Switching desks: **exit on the machine you're leaving -> let Dropbox settle ->
resume on the other.** Never run the same session live on both machines at once.

- Sequential resume IS the fast-forward case (rule 2) — fully supported, and
  arguably the better fit than forking. Ping-ponging = a chain of ever-longer
  fast-forwards, handled forever.
- Divergence (rule 3) only arises from (a) concurrency — same session live on
  both at once, or (b) stale resume — resuming before Dropbox pulled the latest.
- Claude Code appends to the jsonl **live** (not just on exit), so "exit first"
  matters: it stops the file moving under Dropbox and guarantees a clean final
  state. The prefix check is the safety net if the rule ever slips.

## Command changes vs. today

- `sesh-grab` -> **retired** (home store is live-mirrored).
- `sesh-push` -> **repurposed** to cross-machine install w/ fast-forward/conflict
  logic above.
- `sesh-wipe` -> largely **unneeded** (purge self-trims); keep only for manual
  reset.
- `cc-fork` / `gpt-fork` -> **unchanged**, still the seed-and-fork helpers.

## Rejected alternatives

- Public sync tools (claude-sync, ccsync, Syncthing, git-in-~/.claude): their
  headline feature is path remapping, which our container already moots
  (`/workspace` + `/home/node` identical everywhere). They're Claude-only (drop
  Codex + our fork workflow), and real-time whole-dir sync adds live-write
  corruption risk our explicit/partitioned model avoids. Also the specific npm
  package names/features in that writeup were unverified — treat as leads only.
- `cleanupPeriodDays` bump to keep >30 days: not needed, we don't want long
  history.

## Open / next

- Pick machine ids (`m4`, `m3ultra`?) and wire the symlinks into devcontainer
  provisioning (shellrc / postCreate).
- Decide whether `data/` stays gitignored (it should — Dropbox is the
  transport, not git).
- Implement the fast-forward/prefix/conflict logic in `sesh-push`.
