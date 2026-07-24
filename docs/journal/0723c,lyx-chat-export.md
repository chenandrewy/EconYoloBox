# MathPanel v0.3: export the visible chat to a project-local LyX snapshot

**Date:** 2026-07-23  
**Status:** detailed implementation plan, not built. Builds on the installed
MathPanel v0.2 (`.tools/mathpanel/`, commit `31bdceb` plus the subsequent
review fixes).

## Goal

Add one VS Code command that exports the chat currently represented by
MathPanel to an editable LyX document in a predictable, project-specific
folder:

```text
<workspace>/mathpanel/
```

There is no save dialog, no synchronization with a running LyX process, and no
automatic insertion back into Claude Code or Codex CLI. The output is a static
snapshot that the user can open in LyX, read in WYSIWYM form, and extend with a
visually edited response.

The command is:

```text
MathPanel: Export Visible Chat to LyX
```

Command identifier:

```text
mathpanel.exportLyx
```

## User flow

1. Run **MathPanel: Export Visible Chat to LyX** from the Command Palette.
2. MathPanel synchronously refreshes the active Claude Code/Codex CLI candidate
   using its existing newest-mtime rule.
3. It snapshots the messages currently retained by MathPanel.
4. It creates `<workspace>/mathpanel/` if needed.
5. It converts the snapshot to a native `.lyx` document using the installed
   `tex2lyx` converter.
6. It reports the project-relative output path and offers a non-blocking
   **Reveal in Explorer** action.
7. The user opens the file in LyX and edits or adds a response manually.

No chooser, confirmation dialog, LyX launch, clipboard mutation, prompt
insertion, or chat send occurs.

## Fixed scope decisions

### Export the visible history, not the entire rollout

“Visible chat” means the same newest 50 normalized messages that MathPanel
retains and sends to its webview:

```js
follower.messages
```

This deliberately reuses:

- the active-source selection already used by the panel;
- Claude/Codex record filtering;
- assistant deduplication;
- user-message discrimination;
- text and math segmentation;
- message and formula size limits; and
- the existing newest-50 retention limit.

The exporter does not reread an uncapped transcript and does not introduce a
second parsing path. If full-session export is wanted later, it should be a
separate command with an explicit resource limit and separate tests.

### Static, immutable snapshots

Each invocation creates a new file. It never overwrites an earlier snapshot.
This avoids replacing a document that may already be open in LyX and makes
failed conversions non-destructive.

Filename format, using New York time:

```text
YYYYMMDD-HHmmss-<source>-chat.lyx
```

Examples:

```text
20260723-154512-codex-chat.lyx
20260723-160044-claude-chat.lyx
```

`<source>` is the fixed string `codex` or `claude`; no session UUID, workspace
name, prompt text, or transcript content appears in the filename.

If two exports occur during the same second, append a deterministic numeric
suffix:

```text
20260723-154512-codex-chat-2.lyx
```

### Project-local output

For the single supported file-scheme workspace folder:

```text
outputDir = path.join(workspaceFolder.uri.fsPath, "mathpanel")
```

Use the literal workspace location for user-facing output, not the realpath
used to match transcript metadata. This places the folder where the user
opened the project while retaining the existing realpath behavior for session
discovery.

Before writing:

- Reject zero, multiple, or non-file workspace folders using the same wording
  and conditions as the existing follower.
- If `mathpanel` exists as a symlink, regular file, or non-directory, fail with
  a clear notification. Do not follow a symlink out of the project.
- If the folder does not exist, create it with mode `0700` where supported.
- Resolve the created/existing folder and verify that it remains beneath the
  workspace realpath.
- Do not change permissions on a pre-existing user-owned directory.

Snapshot files are created with mode `0600` where supported.

### Keep snapshots out of Git by default

The exported file contains a second at-rest copy of chat content. The command
is explicitly requesting that copy, but accidental commits should still be
discouraged.

When MathPanel creates a new `mathpanel/` folder, also create:

```text
mathpanel/.gitignore
```

with:

```gitignore
*
!.gitignore
```

If `mathpanel/` already exists:

- create this `.gitignore` only if it is absent;
- never overwrite or append to an existing `.gitignore`; and
- never run `git add`, modify the repository’s root `.gitignore`, or make a
  commit automatically.

If a pre-existing `.gitignore` does not ignore snapshots, leave it untouched
and include a warning in the success notification. Git-ignore protection is
guaranteed only for a folder created by MathPanel or one whose existing rules
already cover the snapshot.

The success notification should state that a chat snapshot was written, not
imply that it is ephemeral.

## Conversion design

### Use an intermediate LaTeX document

The normalized MathPanel history already has the source-neutral shape:

```js
{
  ts: "2026-07-23T18:00:00.000Z",
  role: "assistant",
  spans: [
    { t: "text", s: "By " },
    { t: "math", m: "inline", s: "E=mc^2" }
  ]
}
```

Convert that structure to a small, synthetic LaTeX `article`, then use LyX’s
installed converter to produce the native `.lyx` file. Do not generate the LyX
file format by hand.

The staging LaTeX document contains:

- a fixed title: `MathPanel chat snapshot`;
- workspace basename;
- source (`Claude Code` or `Codex CLI`);
- New York export timestamp;
- a note that the export contains the newest 50 messages at most; and
- one unnumbered subsection per message, labeled with its role and displayed
  timestamp.

Suggested generated structure:

```latex
\documentclass{article}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage{amsmath,amssymb}
\begin{document}
\section*{MathPanel chat snapshot}
\textbf{Source:} Codex CLI

\subsection*{User --- Jul 23, 2:00 PM}
...

\subsection*{Assistant --- Jul 23, 2:01 PM}
...
\end{document}
```

The source is generated from structured spans, never by interpolating an
entire raw JSONL record.

### Text-span conversion

Text spans are inert prose. Escape all LaTeX-special characters before placing
them in the intermediate document:

| Input | LaTeX text output |
|---|---|
| `\` | `\textbackslash{}` |
| `{` / `}` | `\{` / `\}` |
| `$` | `\$` |
| `&` | `\&` |
| `#` | `\#` |
| `_` | `\_` |
| `%` | `\%` |
| `~` | `\textasciitilde{}` |
| `^` | `\textasciicircum{}` |

Rules:

- Do not interpret Markdown.
- Backticks and fenced-code markers remain visible prose.
- Preserve Unicode as UTF-8.
- Convert a single newline to an explicit line break.
- Convert runs of two or more newlines to paragraph boundaries.
- Preserve ordering across adjacent text and math spans.
- A prose string such as `\end{document}` must remain visible text and must
  not affect the generated document structure.

Put escaping and newline handling in a pure function with direct unit tests.

### Math-span conversion

Math spans have already passed MathPanel’s delimiter scanner and resource
limits. Emit:

```text
inline  -> \( <source> \)
display -> \[ <source> \]
```

Do not:

- run a second delimiter scanner;
- add equation numbers;
- wrap display math in raw `equation` environments;
- truncate formulas a second time;
- rewrite macros; or
- attempt to “repair” invalid LaTeX.

`tex2lyx` copies supported LaTeX math into native LyX formula insets, which is
the WYSIWYM result this feature is intended to provide. Unsupported constructs
may remain as TeX/ERT inside the LyX document; that is preferable to silently
changing their meaning.

## Converter invocation

Use the installed `/usr/bin/tex2lyx` through `child_process.spawn` or
`spawnSync` with an argument array and `shell: false`.

The intended command shape is:

```text
tex2lyx -q -skipchildren -fixedenc utf8 <staging.tex> <staging.lyx>
```

Build-time verification must confirm the exact accepted UTF-8 encoding name
for LyX 2.4.3. If `utf8` is not accepted, use the name listed by the installed
LyX encodings file; do not guess or install anything.

Required restrictions:

- Include `-skipchildren`, so transcript text containing `\input` or
  `\include` cannot make `tex2lyx` translate child documents.
- Do not pass `-copyfiles`.
- Do not invoke `latex`, `pdflatex`, `biber`, shell escape, or a PDF build.
- Run with the staging directory as `cwd`.
- Use fixed executable/argument positions; no shell command construction.
- Impose a short timeout (suggested: 15 seconds).
- Cap captured stdout/stderr and never log generated transcript content.
- Treat any nonzero exit, timeout, signal, or absent output file as a failed
  export.

`tex2lyx` is already installed with LyX 2.4.3 in this devcontainer. Missing
`tex2lyx` is an environment problem: report it and stop. Do not install a
replacement or write a native LyX serializer.

## Staging and atomic publication

All runtime writes stay within the explicitly requested project-local
`mathpanel/` folder.

For each export:

1. Create a random private staging directory:

   ```text
   <workspace>/mathpanel/.export-<random>/
   ```

2. Write `snapshot.tex` with mode `0600`.
3. Ask `tex2lyx` to create `snapshot.lyx` in that staging directory.
4. Verify:
   - the converter exited successfully;
   - `snapshot.lyx` exists;
   - it is a regular file, not a symlink;
   - it is nonempty; and
   - its first line identifies a LyX document.
5. Choose the collision-free final filename.
6. Rename the staging `.lyx` into its final path within `mathpanel/`. The rename
   is on one filesystem and is therefore atomic.
7. Remove the staging `.tex` and staging directory in a narrow `finally`
   cleanup.

On failure:

- publish no final `.lyx` file;
- remove only the exact random staging directory created by this invocation;
- preserve every prior snapshot;
- show a concise VS Code error; and
- never print transcript text or converter input.

Do not maintain a mutable `latest.lyx` symlink or overwrite a fixed
`chat.lyx`; either could surprise a LyX instance with an externally replaced
open document.

## Extension lifecycle

### Command registration

In `activate(context)`, register:

```js
vscode.commands.registerCommand(
  "mathpanel.exportLyx",
  () => exportVisibleChat(context)
)
```

Add the command to `package.json`:

```json
{
  "command": "mathpanel.exportLyx",
  "title": "MathPanel: Export Visible Chat to LyX"
}
```

Also add:

```text
onCommand:mathpanel.exportLyx
```

to the explicit activation events.

### Work with the panel open or closed

The export command must not require the webview to be open.

Use the existing follower synchronously:

1. Record whether a follower already exists.
2. If absent, call `startFollower()`. Its initial `discover()` and `poll()` are
   synchronous and populate the current history.
3. If a follower already exists, call `discover()` once before snapshotting so
   the export uses the current newest-mtime candidate.
4. Copy the normalized messages and source into export-local immutable data.
5. If the command created a transient follower, call `stopFollower()` in a
   `finally` block after the snapshot has been copied.
6. If the panel owns the follower, leave its timer/watch lifecycle unchanged.

Do not let an export command leave a discovery timer running when no panel is
open.

If there is no selected session or no renderable message:

- write nothing;
- show the current no-session/unsupported-workspace status; and
- stop any transient follower.

### Do not block the extension host

Transcript discovery and snapshot construction are small and synchronous
today. `tex2lyx` must run asynchronously so conversion cannot freeze the
extension host.

Disable only concurrent exports, not normal panel updates:

- keep a module-level `exportInProgress` boolean or promise;
- if invoked again while exporting, reveal a non-blocking “export already in
  progress” message;
- always clear the guard in `finally`.

The snapshot data is copied before the asynchronous conversion begins, so
subsequent transcript updates do not alter the file being produced.

## Pure export module

Add:

```text
.tools/mathpanel/extension/export-lyx.js
```

Keep this module free of `vscode` imports. It should contain:

- New York filename/timestamp generation;
- collision suffix selection;
- LaTeX text escaping;
- newline/paragraph conversion;
- message/spans-to-LaTeX serialization;
- safe output-directory validation helpers that do not depend on VS Code
  objects; and
- converter result validation where practical.

Keep VS Code notifications, workspace access, child-process orchestration, and
the follower lifecycle in `extension.js`.

The exporter consumes only the normalized `{ts, role, spans}` shape. It must
not know Claude or Codex JSONL record formats.

## Security-contract update

This feature intentionally changes one original MathPanel invariant:

> MathPanel previously created no at-rest transcript copy.

The updated contract is:

- Normal viewing remains read-only and creates no files.
- Only the explicit export command creates a copy.
- The copy is written only under `<workspace>/mathpanel/`.
- The directory is ignored by Git by default.
- No writes occur under `~/.claude/` or `~/.codex/`.
- No network or listener is introduced.
- No transcript content is logged.
- No TeX engine is run.
- `tex2lyx` child-document traversal and file copying are disabled.
- Export never sends, pastes, or modifies chat input.

The README must make the at-rest-copy change prominent rather than leaving the
v0.1 “no second copy” statement unqualified.

## Files to change

```text
.tools/mathpanel/
├── README.md
├── install-extension.sh
└── extension/
    ├── export-lyx.js                  # NEW pure serializer/naming helpers
    ├── extension.js                   # command + lifecycle + converter spawn
    ├── package.json                   # command and v0.3 version
    ├── test/
    │   └── export-lyx.test.js         # NEW synthetic-only tests
    ├── codex.js                       # unchanged
    ├── transcript.js                  # unchanged
    └── media/                         # unchanged
```

No npm packages, node_modules, marketplace dependencies, LyX user-preference
changes, or server pipes.

## Version and installation

This is a user-visible feature and a material security-contract change. Bump:

```text
package.json: 0.2.0 -> 0.3.0
install target: local.mathpanel-0.3.0
```

Update installer and README paths together. After a successful 0.3.0 copy, the
installer may remove the exact superseded `local.mathpanel-0.2.0` directory,
following the current upgrade pattern.

Do not install during planning. When implementation is requested, run the
installer only under that implementation/install authorization, verify the
installed tree matches the source, and tell the user to reload VS Code.

## Automated tests

All fixtures and content must be synthetic. Never commit a real transcript or
real exported chat.

### Pure serializer tests

1. **Text escaping**
   - every LaTeX-special character is inert;
   - `\end{document}` remains visible prose;
   - Unicode survives;
   - currency and underscores remain text.

2. **Newline handling**
   - one newline becomes a line break;
   - blank-line runs become paragraph boundaries;
   - boundaries across adjacent spans preserve order.

3. **Math conversion**
   - inline spans become `\(...\)`;
   - display spans become `\[...\]`;
   - formula source is neither truncated nor rescanned;
   - text `$5` remains escaped prose.

4. **Message structure**
   - chronological order is preserved;
   - fixed user/assistant labels are correct;
   - missing/invalid timestamps display safely;
   - export metadata says “newest 50 at most.”

5. **Naming**
   - New York timestamps are used at UTC-midnight and DST boundaries;
   - source names are fixed;
   - collisions receive `-2`, `-3`, and so on;
   - no transcript-derived string reaches the filename.

6. **Path safety**
   - ordinary project folder accepted;
   - symlinked `mathpanel/` rejected;
   - file-at-output-path rejected;
   - resolved path outside workspace rejected;
   - pre-existing `.gitignore` is not replaced.

### Synthetic converter integration test

In a private temporary test directory:

1. Generate a synthetic transcript containing prose, Unicode, inline math,
   display math, code markers, and LaTeX-special prose.
2. Produce the intermediate `.tex`.
3. Invoke installed `tex2lyx` with the production argument list.
4. Assert a nonempty native LyX file is produced.
5. Assert the file contains native formula insets for normal inline/display
   formulas.
6. Include a synthetic child file and a literal `\input` attempt; verify
   `-skipchildren` prevents that child’s contents from appearing in the output.
7. Clean up the exact temporary directory.

If `tex2lyx` is missing in this configured environment, the test should fail
with an environment message rather than silently skip or install anything.

### Extension-level behavior

Factor enough orchestration to test with injected filesystem/spawn functions:

- converter success publishes one final snapshot atomically;
- converter failure publishes none;
- timeout publishes none;
- prior snapshots survive failure;
- staging cleanup is exact;
- concurrent invocation is rejected;
- a transient follower is always stopped;
- a panel-owned follower remains running.

The existing Claude, Codex, segmentation, limits, and line-buffer tests must
remain green.

## Manual validation

After implementation and explicit installation:

1. Reload the VS Code window.
2. With MathPanel closed and an active Codex session, run the export command.
3. Confirm a timestamped Codex `.lyx` file appears under
   `<workspace>/mathpanel/`.
4. Open it in LyX and verify:
   - role/timestamp structure is readable;
   - prose is ordinary editable LyX text;
   - inline formulas are editable inline math insets;
   - display formulas are editable display math insets; and
   - code/backticks remain inert visible text.
5. Repeat with the panel open; confirm the live panel continues updating.
6. Make Claude the newest source and export again; confirm the filename and
   content source switch to Claude.
7. Export twice in one second and confirm collision-safe distinct filenames.
8. Test prose containing `#`, `%`, `_`, `$`, braces, backslashes, and Unicode.
9. Test a malformed/unsupported formula; the command must fail cleanly or
   preserve it as TeX/ERT without corrupting prior snapshots.
10. Confirm:
    - folder mode is private where supported;
    - snapshot mode is `0600`;
    - a tool-created folder’s `.gitignore` protects snapshots;
    - `git status` does not list exported chat in that tool-created-folder case;
    - no writes occurred under transcript roots;
    - listener table is unchanged; and
    - no temporary staging directory remains.

## Failure messages

Use short, actionable notifications:

- `MathPanel supports exactly one local workspace folder.`
- `No Claude Code or Codex CLI session found for this workspace.`
- `The project mathpanel path is not a safe directory.`
- `LyX export is already in progress.`
- `tex2lyx is not available in this environment.`
- `MathPanel could not convert this chat to LyX. No snapshot was written.`
- Success:
  `Exported visible chat to mathpanel/<filename>.`

Do not include transcript content, raw converter input, or full converter
stderr in notifications or logs.

## Build order

1. Verify the exact `tex2lyx` UTF-8 invocation against a synthetic file in a
   temporary directory.
2. Write the pure `export-lyx.js` serializer and its unit tests.
3. Add safe project-folder creation, staging, atomic publication, and injected
   converter orchestration tests.
4. Wire the command into `extension.js` using the transient-follower lifecycle.
5. Update `package.json`, README, threat model, installer, and version paths.
6. Run the complete `node --test` suite, syntax checks, shell syntax check, and
   `git diff --check`.
7. Run the synthetic real-`tex2lyx` integration test.
8. Under explicit implementation/install authorization, install 0.3.0 and
   verify the installed tree matches source.
9. Reload and complete the manual Codex/Claude export checks.

## Accepted limitations

- Only the newest 50 rendered messages are exported.
- Export is a point-in-time snapshot; it never updates automatically.
- Markdown is not rendered as rich LyX formatting.
- Code is preserved as visible prose, not converted into syntax-highlighted
  listings.
- Unsupported LaTeX may appear as ERT rather than a native LyX inset.
- The user manually opens LyX and manually transfers any drafted response back
  to chat.
- Repeated exports accumulate private snapshots until the user deletes them.

## Explicitly not doing

- No save dialog.
- No LyX server pipe, `lyxclient`, socket discovery, or running-instance
  control.
- No automatic LyX launch.
- No file watcher or live synchronization.
- No reverse import from LyX into MathPanel.
- No clipboard write.
- No prompt insertion or message send.
- No full-transcript reread.
- No PDF build.
- No TeX compilation.
- No network.
- No writes under Claude or Codex storage.
- No automatic Git changes beyond the project-local protective `.gitignore`.

## Acceptance criteria

The feature is complete when one command, invoked with the panel either open or
closed, creates exactly one collision-safe, private, editable LyX snapshot
under `<workspace>/mathpanel/`; normal formulas are native LyX math insets;
prose cannot alter the generated LaTeX structure; failed conversion publishes
nothing; prior snapshots remain untouched; a tool-created folder is ignored by
Git; an existing `.gitignore` is never modified; and all existing MathPanel
behavior remains unchanged until the command is explicitly invoked.
