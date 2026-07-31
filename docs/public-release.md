# Public release plan

Goal: publish the sandbox infrastructure without revealing which journals the
owner reviews for, or any host paths and identifiers.

## Approach: snapshot, re-export if needed

Copy the tracked files into a **fresh folder**, `git init`, one commit, push to a
new public repo. Two physically separate folders means no push from the private
repo can reach the public remote.

Rejected: an orphan branch in this repo (one wrong push leaks everything) and a
`git filter-repo` rewrite (auditing 72 commits to preserve history nobody will
read).

Deferred: inverting the flow, so the public repo becomes the home of the
infrastructure and the private workspace consumes it. Cleanest long-run, but it
means developing the container config in public. Only worth it if people
actually use the thing.

Re-export when there is something worth re-exporting. Public history becomes a
series of snapshots. If it goes stale instead, a dated snapshot is a fine
outcome for a "here's my setup" repo.

## Excluded from the export

- `docs/journal/` — messy notes by definition, and where every PII hit lives.
- Everything already in `.gitignore` (private project folders, `template/`,
  `/dev/`, session data).

## Pre-flight check

Grep the staged copy for `chen1678`, `/Users/`, `Dropbox`, `MacBook`, `Ref,`,
`Disc,` and refuse to publish on any hit. This is what caught the mathpanel test
fixture.

Already safe: `credentials-map.json` holds only slug → env-var-name mappings, no
values; private project folders were never committed; `.gitignore` uses the
comma forms that actually match the folder names; no remote is configured.

## Open decisions

- **Repo name.** Earlier suggestions were `agentic-sandbox` / `sandbox-setup`;
  the naming discussion favored something more distinctive (`EconYoloBox` and
  variants).
- **Journal.** Strip entirely (safe, less interesting) or curate a few scrubbed
  entries. The firewall analysis, the credential-theatre entry, and the Codex
  review that caught leaked examples are the strongest candidates.
- **README.** `docs/features.md` is now a usable front door, so the public
  README can be thin and point at it.

## Fixes to make in the private repo

These outlive the export, so do them here rather than in a staging copy.

- `.tools/mathpanel/extension/test/transcript.test.js` uses the fixture path
  `/workspace/Ref,JEconom`. Genericize it.
- Decide whether `docs/journal/0629T14-public-sandbox-sharing.md` (superseded by
  this file) and the two build-error dumps still earn their place.

## History note

`3218e05 "Initial public release of the sandbox setup"` sits mid-history. That
cleanup was done on a copy that was not kept; 63 commits have landed since, and
its scrubs are **not** in this repo. Do not assume HEAD is clean because that
commit exists.
