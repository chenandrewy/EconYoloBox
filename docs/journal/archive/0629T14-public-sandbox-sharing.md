# Sharing the sandbox setup publicly

Working notes on prepping this repo for a public GitHub release. Goal: share
the sandbox **setup/infrastructure** while never revealing which academic
journals the owner reviews for.

## Key facts established
- The "setup" is just the **33 tracked files** (~168 KB). All journal-related
  content lives in **untracked** project folders (`Ref,RFS`, `Disc,ABFR`,
  `Ref,JEconom`, etc.) that have never been committed.
- `.credentials/credentials-map.json` only maps slugs → **env-var names**
  (`WRDS_PASSWORD`, ...). No secret values anywhere in tracked content.

## Risks found in the original repo
1. **`.gitignore` didn't match the folders.** Patterns used dashes
   (`Disc-*/`, `Ref-*/`) but actual folders use commas (`Disc,ABFR`), so the
   private folders were NOT ignored — one `git add -A` would have leaked them,
   and the folder names themselves reveal journals.
2. **Dropbox "conflicted copy" ref** (`main (Mac Studio's conflicted copy ...)`)
   in `.git/refs/heads/` was breaking git tooling (`git log --all` errored).
3. **Local PII**: `dev/journal/0423H14-build-error.md` had
   `/Users/chen1678/.../Dropbox/Sandbox` paths (~12x).

## Approach chosen
Delete `.git` and reconstruct with no history (history not needed), then create
a fresh public remote. Old `.git` tarred to scratchpad as a safety net.

## Done so far
- Reconstructed `.git`: fresh `init`, single clean commit, exactly the 33 prior
  files + a new **MIT `LICENSE`** (chose MIT after comparing MIT / Apache-2.0 /
  BSD / CC0-Unlicense / GPL — MIT is the conventional, attribution-keeping,
  max-adoption default for a tooling/config repo).
- Rewrote `.gitignore` to match comma naming (`Ref,*/`, `Disc,*/`, ...) and
  verified the private folders are now ignored.
- Scrubbed PII: `chen1678` removed, Dropbox path → `/workspace`.

## Codex review (headless, yolo in container)
- 1st pass NO-GO, caught two leaks I'd missed:
  - my own `.gitignore` comment had literally spelled out `Ref,RFS` /
    `Disc,ABFR` as examples;
  - `dev/journal/0505T20-...md` referenced `Ref-JFInsights`.
  Both fixed (comment genericized; reference → "any single project").
- 2nd pass: all journal/secret/Dropbox issues GO. Residual NO-GO is only generic
  VS Code/macOS paths (`/Users/USER/.vscode`, `/Applications/Visual Studio
  Code.app`) in the build-error dump — username already redacted, no journal or
  identity info. Judged non-blocking per the "everything but journals" criterion
  (and Codex tends to over-flag edge cases).

## Open / next (NOT yet done)
- `gh` is authed as `chenandrewy`.
- Need: **repo name** (suggested `agentic-sandbox` or `sandbox-setup`) and a
  call on whether to keep or drop `dev/journal/0423H14-build-error.md`.
- Then: `gh repo create <name> --public --source=. --remote=origin --push`.
