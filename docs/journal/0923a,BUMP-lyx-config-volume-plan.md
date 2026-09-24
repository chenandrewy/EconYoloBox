# 0923a — plan: mount ~/.lyx from a volume

Discussion snapshot, 2026-09-23, branch `yolo-default-posture`. Decided; not
yet implemented. BUMP: needs a rebuild, so it waits until the current tasks
are done.

## why

A plain `bbcode` start of a stopped container took about 13 s, and 7 s of
that was `tex-refresh` (LyX's `configure.py`). About 6 s of the 7 went to four
font lookups that fail: `garamondx-fonts`, `minion2newtx`, `ugm` and
`urwclassico`, each about 1.5 s. See the 2026-09-24T02:49 startup log.

`tex-refresh` has to run once per `~/.lyx`. Without the generated
`textclass.lst` and `lyxmodules.lst`, `tex2lyx` writes an empty file and still
reports success ([0910b](0910b,lyx-user-configuration-missing.md)). But
`~/.lyx` is in the container's writable layer, so:

- a stop and start keeps it, which makes the startup refresh redundant: it
  regenerates the same files from the same read-only TeX volume;
- a rebuild or recreate wipes it, and the refresh is really needed.

## the change

Give `~/.lyx` its own volume, like `~/.claude` and `~/.codex`. The LyX setup
and the user's LyX preferences (bindings, recent files, `preferences`) then
survive rebuilds too.

1. `devcontainer.json` mounts, next to the claude and codex config lines:
   ```json
   "source=${localWorkspaceFolderBasename}-lyx-config-${devcontainerId},target=/home/node/.lyx,type=volume",
   ```
2. `Dockerfile`, at the `mkdir -p /sandbox /home/node/.claude …` and
   `chown -R node:node …` line (currently lines 288-289): add
   `/home/node/.lyx`. Without it, Docker creates the mount point owned by
   root, and `configure.py`, which runs as `node`, cannot write there.
3. `post-start.sh`, last line: run `tex-refresh` only when the setup is
   missing, which is the first start on an empty volume:
   ```sh
   [ -s "$HOME/.lyx/textclass.lst" ] || tex-refresh || { echo "TeX/LyX refresh failed; see the message above" >&2; true; }
   ```
   This is a check that the file exists, not a staleness stamp. That is the
   simple option we chose.
4. Docs: `.devcontainer/README.md` (the "`tex-refresh` runs LyX converter
   detection … at startup … not persisted across container recreation"
   paragraph) and the `tex-refresh` sentence in
   `agents/SANDBOX-CLAUDE.md` (it is copied into the user-level CLAUDE.md).
   New rule: startup configures LyX once per volume. **Run `tex-refresh` by
   hand after a TeX Live update on the host or a `LYX_VERSION` bump in the
   Dockerfile.**

## the trade-off we accepted

The volume keeps the LyX setup across TeX and LyX changes, so the setup can go
stale. Nothing detects this automatically. The manual `tex-refresh` rule
covers it; both kinds of change are rare and done by the human. If stale setup
ever causes a problem, add a stamp (LyX version + the TeX volume's `ls-R`
mtime) to `tex-refresh`.

The usual per-`devcontainerId` volume cost applies: moving or renaming the
project folder leaves the volume orphaned (see the comment above the mounts in
`devcontainer.json`). Losing it only costs one 7 s reconfigure.

## interaction with 0921a

[0921a](0921a,BUMP-read-only-package-volumes-plan.md) also touches the TeX
refresh path and the Dockerfile's `mkdir`/`chown` line. Whichever plan lands
second should rebase on the other. Folding TeX into the shared builder does not
change where `~/.lyx` lives.

## test

- `bbox --rebuild`: the first start runs `configure.py`, and `~/.lyx` belongs
  to `node`.
- Stop and start: no LyX configure output; startup is about 7 s faster.
- Rebuild again: still no configure; `~/.lyx/preferences` survives.
- `tex2lyx` on a minimal `article` gives a non-empty `.lyx` that LyX exports.
- After `rm ~/.lyx/textclass.lst`, the next start configures again.
