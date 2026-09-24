# The PDF viewer rule guards the wrong cause, and misses a real one

Date: 2026-08-28 (NY)

`SANDBOX-CLAUDE.md` has told agents since commit `ace68fb` (2026-07-17,
"Document safe temporary PDF builds") to build LaTeX into a temporary output
directory and leave the project PDF alone, "because replacing an open PDF can
confuse the VS Code PDF viewer." The rule was written from the symptom; no
entry records a diagnosis. This one supplies it.

The short version: agents building PDFs is not the cause. Four mechanisms
produce the observed breakage, the rule addresses two of them by forbidding
the deliverable, and the largest one is triggered by an agent *editing a
`.tex` file* and so is untouched by the rule entirely.

The prompt for this was `Live_AIWorkFlow/yolobox-writing`, whose
`beamer/build.sh` builds the project PDF in place and defends itself with an
atomic rename instead. That script turned out to be closer to right than our
guideline.

## What actually goes wrong

Four separate mechanisms, all confirmed inside this container.

### 1. pdflatex publishes non-atomically

`pdflatex` opens the output PDF with truncate-and-grow semantics, on the same
inode. Sampling `stat` during a build of a 120-page article in `/workspace`:
the file appears at size 0, then grows to 503 KB over roughly 0.3 s of wall
clock. Any reader inside that window sees a truncated PDF. A beamer deck with
graphics widens it.

### 2. `tomoki1207.pdf` reloads with no debounce and never retries

From the installed extension's `out/src/pdfPreview.js` (v1.2.2):

```js
const watcher = vscode.workspace.createFileSystemWatcher(resource.fsPath);
watcher.onDidChange(e => { ... this.reload(); });   // postMessage 'reload'
watcher.onDidDelete(e => { ... this.webviewEditor.dispose(); });
```

One reload per change event, fired immediately, with no debounce and no
re-check. A single badly timed event hands PDF.js a truncated file, and the
tab stays broken until the *next* write. The `onDidDelete` branch disposes the
editor outright, which is what is really happening when a tab "closes itself"
after an aux-clean or a rebuild-from-scratch.

LaTeX Workshop's own viewer behaves better here: it debounces, via
`latex-workshop.latex.watch.pdf.delay` (default 250 ms). Which viewer owns the
tab depends on how the PDF was opened, which is why the symptom has always
felt inconsistent.

### 3. The Dropbox mount multiplies change events

`/workspace` is a `fakeowner` mount over `/run/host_mark/Users` — Docker
Desktop's VirtioFS bind mount of a Dropbox folder. An inotify probe of a
single 50 KB write, run against `/workspace` and against container-local
`/tmp` for comparison:

| | `/workspace` | `/tmp` |
|---|---|---|
| events | 11, spread over 2.11 s | 4, immediate |
| oddities | duplicate `CREATE` at 0.06 s; `ATTRIB`+`MODIFY` at 2.11 s | none |

The late pair is the host Dropbox daemon touching the file after sync, echoed
back into the container through VirtioFS. Every write therefore hands the
no-debounce viewer of mechanism 2 several reload triggers, some of which land
mid-write by construction.

Note what this rules out. inotify *works* over the mount; events are not being
missed. The problem is the opposite of the one that would be intuitive.

### 4. LaTeX Workshop auto-builds into the project directory

This is the one nothing in our configuration accounts for, and probably the
worst. `james-yu.latex-workshop` 10.18.0 is installed by `devcontainer.json`,
and nothing in that file or in the generated Machine settings overrides its
build defaults:

- `latex.autoBuild.run = "onFileChange"`, with a 250 ms watch delay
- `latex.outDir = "%DIR%"` — into the project directory
- `latex.autoBuild.cleanAndRetry.enabled = true`

Once a root `.tex` has been detected, an agent *editing the source* is enough
to make the extension launch its own `pdflatex` into the project directory. If
the agent also builds, two runs share a jobname and clobber each other's
`.aux` and `.pdf`, and `cleanAndRetry` can delete aux files out from under the
agent's run.

The trigger is the edit, not the build. Our temporary-output-directory rule
does nothing about it.

## What yolobox-writing does about it

`beamer/build.sh` ends with:

```bash
tmp_pdf="$(mktemp slides.pdf.XXXXXX)"
cp slides.pdf "$tmp_pdf"
mv -f "$tmp_pdf" slides.pdf
touch slides.pdf
```

A same-directory temporary file plus `mv -f` is an atomic rename: a reader
sees either the whole old file or the whole new one, never a truncation. That
eliminates mechanism 1 and blunts 3. It does nothing for 4.

One caveat to carry into testing. In the inotify probe, `rename()` on the
Dropbox mount produced `MOVED_TO` followed a few milliseconds later by
`DELETE` and `CREATE` on the target path — Dropbox's own churn. If VS Code's
watcher ever surfaces that `DELETE` without coalescing it, the `onDidDelete`
branch above disposes the tab. This was not observed end to end, and
parcel-watcher most likely collapses it, but it is the failure mode to watch
for if the atomic publish ever closes a tab.

## Where the fix belongs: settings scope

VS Code's UI runs on the host, but the server and extension host run in the
container. Local User settings do propagate into the remote window, so a
`devcontainer.json` settings entry is not automatically necessary. What
decides it is each setting's declared scope:

| setting | scope | settable from local User settings |
|---|---|---|
| `latex-workshop.latex.autoBuild.run` | `resource` | yes |
| `latex-workshop.latex.outDir` | `resource` | yes |
| `prettier.prettierPath` | `resource` | yes |
| `python.defaultInterpreterPath` | `machine-overridable` | no |

So our existing `customizations.vscode.settings` block is a mix.
`python.defaultInterpreterPath` and `terminal.integrated.defaultProfile.linux`
are machine-scoped and genuinely cannot come from host settings; the formatter
entries are resource-scoped and would mostly be inherited anyway.

`autoBuild.run` is resource-scoped, which means a line in the host's User
settings would fix it here today with no rebuild. It should still go in
`devcontainer.json`, for two reasons:

1. **This repo ships.** `econyolobox` is the public export of this setup.
   Someone who clones it has none of these personal settings, so for them
   `devcontainer.json` *is* the configuration. A fix living only in one host's
   User settings would ship a container that still has the concurrent-writer
   bug, and the author would never see it.
2. It documents intent next to the extension that causes the problem, and it
   does not silently diverge between macbook25 and macstudio25.

One operational note found while planning: `customizations.vscode.settings` is
written to `/home/node/.vscode-server/data/Machine/settings.json` once, at
container create, guarded by `.writeMachineSettingsMarker` (both dated
2026-08-20 21:09 in the current container). Editing `devcontainer.json`
therefore changes nothing until a rebuild. Test loops must not be built on it.

## Plan

Ordered so that the single rebuild is a confirmation step rather than a test
iteration.

1. **Establish a control.** Reproduce the current breakage with current
   settings, deliberately. The failures are races; if they cannot be made to
   fail on demand, then "it did not break after the change" carries no
   information.
2. **Live-test `autoBuild.run = "never"`** via `/workspace/.vscode/`
   `settings.json`. That path is already gitignored (`.gitignore:22`), takes
   effect on window reload, and needs no rebuild. Workspace settings outrank
   Machine settings, so this genuinely exercises the change. Confirm no build
   starts when an agent edits a watched `.tex`: LaTeX Workshop's output
   channel stays silent and `.aux` mtimes do not move.
3. **Test the atomic publish** by adopting yolobox's rename-and-touch ending
   in a build script, with the PDF open in a tab. Run it five or more times —
   a single clean pass proves very little against a race. Watch for a blank
   render and for the tab disposing itself (the `DELETE` caveat above).
4. **Branch.** Move the verified `autoBuild.run` value into
   `devcontainer.json`, rewrite the PDF-viewer-safety rule in
   `.devcontainer/agents/SANDBOX-CLAUDE.md`, and add the atomic-publish
   convention.
5. **Rebuild once from the branch** to confirm the setting lands in Machine
   settings. Volumes are keyed by `${devcontainerId}`, derived from the host
   path rather than the branch, so this neither orphans them nor triggers a
   package reinstall; checking out `main` and rebuilding reverts it.
6. **Merge.**

Steps 3 and 4 are documentation and a shell snippet, with no container risk
and no rebuild; only step 2's outcome gates the `devcontainer.json` edit.

## Proposed replacement for the rule

The current rule prevents the acute symptom by preventing the deliverable, and
leaves mechanism 4 in place. The intended shape after testing:

- Turn off `latex-workshop.latex.autoBuild.run`. This is the only change that
  removes a genuine concurrent-writer bug rather than working around a race.
- Let agents build the project PDF in place, publishing through an atomic
  rename, rather than forbidding them to produce what was asked for.
- Keep the temporary-output-directory advice for what it is actually good at:
  throwaway compile checks where the deliverable should not be touched at all.

Nothing in this entry has been tested against a live viewer tab. The failures
live in a webview that a human has to look at, and every claim above about
what the *viewer* does is read from extension source rather than observed.
