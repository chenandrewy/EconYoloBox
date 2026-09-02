# Turned off LaTeX Workshop auto-build, deleted the PDF viewer rule

Date: 2026-08-31 (NY)

Follow-up to `0828a,pdf-viewer-build-races.md`, which listed four mechanisms
behind the broken PDF tabs and proposed a plan. This entry records what was
actually done, what was dropped, and the one idea worth keeping for later.

## What was done

**1. Confirmed the mechanism 4 claims from the extension source.** The 0828
entry read these out of the container. The same version is installed on the
host at `~/.vscode/extensions/james-yu.latex-workshop-10.18.0`, so they are
now checked directly:

- `package.json:1505`: `latex.autoBuild.run` defaults to `"onFileChange"`,
  scope `resource`.
- Its own description says the build fires "upon detecting a file change in
  any of the dependencies, **even modified by other applications**."
- `out/src/compile/build.js:58`:
  `lw.watcher.src.onChange(filePath => void autoBuild(filePath.fsPath, 'onFileChange'))`
- `latex.outDir` defaults to `%DIR%`; `autoBuild.cleanAndRetry.enabled`
  defaults to `true`.

So the extension is a plain filesystem watcher. It cannot tell an agent's
write from a keystroke from `sed -i` in a terminal. The agent is not special
here; it is just another writer. Dropbox syncing a `.tex` from the other
machine counts too.

The reason this is easy to miss: the agent feels headless and separate, but
the extension host runs *inside the same container*, on the same files. There
is no `.vscode-server` on the host at all. Two processes, one directory, no
isolation between them.

**2. Set `autoBuild.run` to `never` in host User settings.**
`Dropbox/MacUser/VSCode/settings.json`, right after `latex.recipe.default`.
That file is symlinked to `~/Library/Application Support/Code/User/settings.json`
and is in git and in Dropbox, so both machines get it.

The 0828 entry argued the fix should not live in host User settings because it
would diverge between macbook25 and macstudio25. That reason was wrong: the
file is already synced, and it already carries a large amount of
latex-workshop configuration (tools, recipes, default recipe, formatter, enter
key binding) that has been propagating into the container all along. The
setting is `resource` scope, so it reaches the remote window.

Caveat: this is User scope, so host-side LaTeX no longer auto-builds either.
Accepted.

**3. Deleted the PDF viewer safety rule** from
`.devcontainer/agents/SANDBOX-CLAUDE.md` (was line 93). It told agents to
build into a temporary output directory and leave the project PDF alone. It
was written from the symptom, it prevented the deliverable rather than the
cause, and it did nothing about mechanism 4.

Deleting it is deliberate exposure. Agents will now build project PDFs in
place, without any protection against the truncation race. That is the point:
we want the traffic in order to find out whether the race actually bites in
normal use.

## What was dropped

- **Forcing the race.** Mechanisms 1 and 2, the non-atomic write and the
  viewer that reloads without debouncing and never retries, are hard to
  trigger on demand. Rather than build a test rig for them, wait and see what
  happens with the setting in place.
- **Putting the setting in `devcontainer.json`, rebuilding, merging.** The
  0828 plan wanted this because `econyolobox` ships publicly and a clone would
  otherwise still have the bug. Skipped, because the yolobox is being
  overhauled entirely, and this belongs in that work instead.

Both changes are uncommitted as of writing.

## The atomic build idea, for later

Not adopted. Written down so it does not have to be worked out again.

`rename(2)` is atomic. A path resolves to either the old file or the new one,
never to something half written. That is a kernel guarantee, not a matter of
timing.

`pdflatex` does the opposite. It opens the output PDF, truncates it to zero,
and grows it back on the same inode. Sampling during a build of a 120-page
article showed size 0 growing to 503 KB over roughly 0.3 seconds. Anything
reading in that window gets a broken file.

Publishing through a rename avoids this:

```bash
pdflatex -output-directory=build ... slides.tex
mv -f build/slides.pdf slides.pdf
touch slides.pdf
```

Two details that matter:

- **The temporary file must be on the same filesystem.** Rename is atomic only
  within one filesystem. Across filesystems `mv` quietly becomes copy plus
  unlink, which is the non-atomic write we were trying to avoid. With
  `/workspace` on a VirtioFS mount and `/tmp` local to the container, a build
  directory beside the project is required and `/tmp` is not.
- **The `touch` is not decoration.** A rename may reach a watcher as a move
  event rather than a content change, so the viewer might not reload at all.
  Since the viewer never retries, what decides whether the tab ends up correct
  is whether the *last* event it sees points at a complete file. The `touch`
  guarantees one.

A second benefit, which is really the whole point for an open tab: a reader
that already has the file open holds a handle to the old inode. Rename only
unlinks the name, so that data stays alive and readable underneath the open
tab. In-place truncation instead pulls the bytes out from under a reader that
did nothing wrong.

### Correction to the 0828 entry

That entry credited `yolobox-writing`'s `beamer/build.sh` with eliminating
mechanism 1. Going by the snippet quoted there, it does not:

```bash
tmp_pdf="$(mktemp slides.pdf.XXXXXX)"
cp slides.pdf "$tmp_pdf"
mv -f "$tmp_pdf" slides.pdf
touch slides.pdf
```

`pdflatex` has already written `slides.pdf` in place before any of this runs.
The truncation window has already happened and already fired watcher events.
What the script adds is a clean atomic final event on complete data, which
*repairs* a tab that got a bad read rather than preventing the bad read.

Useful, given a viewer with no retry. But repair is not prevention. The
`-output-directory` form above is the version to use, because there the only
writer to the published path is `mv`. It also quietly does what the deleted
rule was reaching for, building somewhere else, without forbidding the
deliverable.

Could not find the script on the host to check the surrounding context;
`Live_*` is gitignored. Working from the quoted snippet only.

## Still unverified

Nothing has been watched failing or not failing in a live viewer tab. Every
claim about what the *viewer* does is read from extension source. The
`autoBuild.run` change has not yet been confirmed to take effect after a
window reload.
