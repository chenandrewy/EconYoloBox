# 0925b — implementation: read-only package volumes (handoff checklist)

Working checklist, 2026-09-25, branch `feature/read-only-package-volumes`.
BUMP: this is the live implementation of
[0921a](0921a,BUMP-read-only-package-volumes-plan.md). Read 0921a first for
the reasoning. This file records the decisions made since then, which
override 0921a where they differ, and it is the checklist to work through.

**How to use this file.** Tick a box (`- [x]`) as soon as its step is done
and verified, not in a batch at the end. Add a dated line under
[log](#log) for anything surprising: a failure, a changed decision, a
workaround you were given permission for. If a session dies halfway, the
next agent resumes from the first unticked box. Commit this file together
with the code it describes.

**Host steps.** The container has no Docker socket. Steps marked **HOST**
are run by the user on the host. Stop at each one, give the exact command,
and wait for the user to report the output. Never try to reach Docker, and
never build a volume some other way.

## terminology

- **Sandbox:** this infrastructure repo, bind-mounted at `/sandbox`.
- **Devcontainer:** the one container `bbox` builds from the sandbox's
  `.devcontainer/devcontainer.json`. `${devcontainerId}` identifies it.
  A **per-devcontainer volume** has `${devcontainerId}` in its name.
- **Workspace:** `/sandbox/workspace/`, the folder that holds the projects.
- **Project:** one folder in the workspace, such as `Research-vs/`. It
  reaches the container through the sandbox's bind mount. A **new project**
  is a new folder there. It gets no container or volumes of its own: every
  project runs in the same devcontainer and sees the same package volumes.

0921a uses "project" to mean a separate devcontainer (for example "leaking
between projects", "every new project pays a multi-minute stack rebuild").
In this file, "project" always means a workspace folder.

## decisions since 0921a

The user answered these on 2026-09-25.

1. **R list.** Add these to the installer: `BiocManager`, `pcaMethods`
   (Bioconductor), `dotenv`, `extrafont`, `fuzzyjoin`, `huxtable`, `janitor`,
   `latex2exp`, `lexicon`, `quanteda.textstats`, `roll`, `splitstackshape`,
   `strucchange`. **Leave out `spacyr`**: it needs a Python spaCy
   environment. The new volume is built fresh, so spacyr simply won't be in
   it. Only these 13 were undeclared in the current site library;
   everything else there is a dependency.
2. **Python list.** No change. All top-level installed distributions are
   already in `PY_PKGS`.
3. **TeX becomes minimal and can have packages added.** This overturns
   0921a's "full scheme, install once, `--force` refused".
   - Fresh volume **`texlive-2026-small-noble`**. The old
     `texlive-2026-noble` (11 GB, full scheme, no marker) stays mounted
     until the cutover passes. The user then removes it by hand. Never
     delete it yourself.
   - Profile: `selected_scheme scheme-small`, **plus**
     `collection-latexextra`, `collection-fontsrecommended`,
     `collection-bibtexextra` (biblatex, biber), `collection-pictures`
     (tikz), `collection-mathscience` and `collection-fontsextra`
     (fontawesome5); **minus** `collection-xetex` (`collection-xetex 0`).
     Also exclude LuaTeX if scheme-small pulls it in and it can be dropped
     cleanly. Record what you find in the log. Expect roughly 2–3 GB.
   - **pdfLaTeX only.** A survey of 327 `.tex`/`.lyx` files in the
     workspace found no `fontspec` or `unicode-math`. The smoke tests are
     pdflatex, biber and a LyX export. Drop the xelatex smoke test.
   - **Adding packages:** a `TEX_PKGS` list in `install-packages.sh`
     (possibly empty at first; collections cover the survey). Re-running
     `tex` on a marked tree runs `tlmgr install` for anything missing. If
     tlmgr refuses because tlmgr itself is outdated (tlnet is rolling), run
     `tlmgr update --self` and retry. **Never `tlmgr update --all`.**
     Existing packages keep their install-time versions until the volume is
     deliberately rebuilt. Re-run the smoke tests after any change.
   - **Marker:** write it only after the smoke tests pass (for example
     `/usr/local/texlive/.sandbox-installed`, recording the profile and
     date). No tree means install. An unmarked nonempty tree means refuse,
     pointing at `install.log`. A marked tree means add any missing
     packages.
4. **Image resolution.** `.setup/packages.sh` uses the **exact image ID of
   the sandbox's running devcontainer**: find the container by its
   `devcontainer.local_folder` label, then `docker inspect -f '{{.Image}}'`.
   If there is no container, or more than one, refuse with "run
   `bbox --rebuild` first". Never fall back to another image. Run the
   builder with `--user root`, because the image ends in `USER node`.
5. **Delivery in two commits**, below. Build before cutover (0921a
   checkpoint). Leave the old per-devcontainer R, venv and TeX volumes
   untouched throughout, so rollback is simply reverting commit 2.
6. **Default targets.** With no arguments on the host, `packages.sh` builds
   `python r`. `tex` is opt-in, and `all` = `python r tex`. With no
   arguments inside the container, `install-packages.sh` means `cli`. The
   read-only targets refuse with "on the host run
   `bash .setup/packages.sh <target>`".
7. **Volume names:** `r-site-library-noble-4.5.3-2026-07-15`,
   `venv-noble-py3.12`, `texlive-2026-small-noble`. They are written once, in
   `devcontainer.json`; `packages.sh` reads them from there (JSONC, so reuse
   the parser in `.host/dc-resolve.py` or `find-python.sh` rather than
   writing a new one).

## traps already known

- **Bioconductor must not update CRAN packages.** Call
  `BiocManager::install("pcaMethods", version = "3.22", ask = FALSE, update = FALSE)`.
  Bioc 3.22 matches R 4.5 and the currently installed `BiocVersion`. The
  default `update = TRUE` would upgrade snapshot-pinned CRAN packages past
  the P3M date. The host builder runs outside the firewall, so Bioconductor
  hosts are reachable there ([0925a](0925a,bioconductor-firewall-toggle.md)).
- **Checking R in the same process** that loaded namespaces gives false
  positives. Verify in a fresh `Rscript`.
- **Target parsing** currently lets the last argument win
  (`install-packages.sh` arg loop). It needs to accept several targets.
- **Docker seeds an empty volume** from the image directory, even under a
  read-only mount. `/opt/venv` therefore always holds the venv skeleton, so
  test for a sentinel (`import pyfixest`, `requireNamespace("fixest")`, the
  TeX marker), never for emptiness.
- **Overlap with [0923a](0923a,BUMP-lyx-config-volume-plan.md)**, the other
  pending BUMP. It also edits the Dockerfile `mkdir`/`chown` line and the
  `tex-refresh` line in `post-start.sh`. Check whether it has landed
  before editing those lines, and don't undo it.
- **The TeX path is unchanged:** the mount target stays
  `/usr/local/texlive` and the year stays 2026, so the Dockerfile's
  `texlive-bin` symlink and `TEXLIVE_YEAR` need no edit. Only the volume
  name changes.
- The read-only install test must use a package **not already present**, or
  it passes without testing anything. Test both creation orders (consumer
  first, builder first).

## phase 1 — builder (commit 1; mounts unchanged, still writable)

- [x] `install-packages.sh`: accept several targets (`python r tex cli`,
      `all`), and update the usage text and header comment.
- [x] `install-packages.sh`: add the 13 R packages from decision 1.
      Bioconductor step as in the traps section.
- [x] `install-packages.sh`: verify R in a fresh `Rscript` after the install.
- [x] `install-packages.sh`: `tex` target, per decision 3. Move the logic
      from `.setup/texlive.sh` (tlpdb year check, profile, `install-tl`,
      `fmtutil-sys`, `updmap-sys`) into it, adapted to the minimal profile.
      Smoke-test pdflatex, biber and a LyX export (LyX is in the image), log
      to `install.log`, then write the marker.
- [x] `install-packages.sh`: in-container default is `cli`, per decision 6.
      (The read-only guards themselves belong to phase 2, since the mounts
      are still writable now.)
- [x] `.setup/packages.sh [targets]`: resolve the image (decision 4), read
      volume names from `devcontainer.json` (decision 7), and
      `docker run --rm --user root` with the three volumes read-write and
      `.devcontainer/` bind-mounted read-only at `/setup`. Header documents
      how to run it, its inputs and its outputs.
- [x] Add the new volume names to `devcontainer.json` so `packages.sh` can
      read them, **without switching any mount yet**. For example, a
      commented block or a `// packages.sh:` key the parser recognises;
      pick whatever is least fragile and explain it in a comment.
- [x] Delete `.setup/texlive.sh`. Update `.setup/README.md` for
      `packages.sh`.
- [x] `shellcheck` both scripts, and `bash -n` them.
- [x] Commit 1. Show the user the diff summary first; commit only when they
      approve.
- [x] **HOST:** `bbox --rebuild` if the Dockerfile changed (it shouldn't in
      phase 1), then `bash .setup/packages.sh all`. Collect the tail of the
      output and each stack's OK line.
- [x] **HOST:** check the new volumes from a throwaway container of the
      same image, mounted read-only: `library()` every R package, import
      every Python package, and a pdflatex + biber + LyX export against
      `texlive-2026-small-noble`. Give the user the exact `docker run`
      lines, adapted from `.setup/README.md`'s texlive-check recipe.
- [x] Re-run `packages.sh python r` on the host and confirm it downloads
      nothing (idempotence).

## phase 2 — cutover (commit 2)

- [x] `devcontainer.json`: switch the R, venv and TeX mounts to the shared
      names with `readonly`, drop `${devcontainerId}` from them, and
      rewrite the comment block to match. Remove the three
      `// packages.sh:` staging lines (their names become the live mounts);
      keep the explanation of staging for future bumps. Leave `npm-global`
      alone.
- [x] `Dockerfile`: remove `chmod -R a+w .../lib/R/library`, and the
      `chown` on site-library and `/opt/venv`. Keep the `mkdir` of
      site-library, since R only adds it to `.libPaths()` if it exists.
- [x] `install-packages.sh`: `python`, `r` and `tex` refuse inside the
      container when their target is read-only, with the host command. This
      mirrors `tex-refresh`.
- [x] `post-start.sh` / `shellrc.sh`: warn on a missing stack using
      sentinels (traps section). Fix the wording at `shellrc.sh:26,166`
      and `tex-refresh.sh:12` so it points to `packages.sh`.
- [x] `.devcontainer/tests/test-packages.sh` absorbs `test-texlive.sh`
      (0921a scope item 7). Mounts are read-only; `library()` and import
      of everything; a `fixest` regression; an `arrow`↔`pyarrow` parquet
      round-trip; the existing LyX checks (pdflatex, no xelatex); and
      `install.packages()` / `pip install` of an absent package must
      fail. Delete `test-texlive.sh`.
- [x] Agent guidance: in `.devcontainer/agents/SANDBOX-CLAUDE.md` and
      `SANDBOX-AGENTS.md`, "installing packages is fine" becomes "ask the
      user to add it". Update the TeX paragraph (new volume name,
      `packages.sh`, minimal scheme). Tell the user that their
      `~/.claude/CLAUDE.md` copy is seeded from here.
- [x] Docs: `docs/features.md:137` and around `:66`/`:89`,
      `.devcontainer/README.md` (TeX section around `:66`, stacks section
      around `:329`), `.setup/README.md`. Include "how a user adds a package"
      from 0921a, plus the `TEX_PKGS` path.
- [x] `grep -rn 'texlive.sh\|texlive-2026-noble\|install-packages.sh'`
      across the repo (excluding `docs/journal/`) turns up nothing stale.
- [x] Commit 2, after the user approves.
- [x] **HOST:** `bbox --rebuild`, then in the new container run
      `bash .devcontainer/tests/test-packages.sh`. No second run is needed:
      all projects share the one devcontainer, so they already share the
      volumes (see log, 2026-09-26).
- [x] **HOST:** consumer-first creation order. Mount a fresh throwaway
      venv volume read-only in a consumer container first (Docker seeds the
      skeleton), then build into it, then `--verify python` read-only. Remove
      the throwaway volume afterwards.
- [x] Re-measure the shared volumes from the rebuilt container (`du -sh`)
      and update `docs/storage-needs.md` and the root README's storage
      budget.
- [ ] Test the new setup for a few days of real research work.
      Suggestions, as time allows:
      - Rerun an existing R and a Python analysis end to end in a real
        project. The new R library was built fresh from the declared list,
        so anything only in the old per-devcontainer volume is gone
        (`spacyr`, for one). Note each missing package.
      - Build a real paper with pdflatex + biber, and export a real LyX
        note. The TeX tree is now minimal, so expect the odd missing
        `.sty`; add it to `TEX_PKGS`. Also watch for documents that
        need XeLaTeX.
      - Try LaTeX Workshop's build and `latexindent` formatting in VS Code.
      - Add one missing package the documented way (list,
        `packages.sh`, restart the session), and confirm that no rebuild
        is needed.
      - Watch agents: they should ask for missing packages, not install
        them. Also look for project scripts that call
        `install.packages()` or `pip install` themselves; those now fail.
      - Check that container start is quiet, with no missing-stack warning
        and no `tex-refresh` error.
- [ ] **HOST, only after everything passes:** the user prunes the old
      volumes (`texlive-2026-noble` and the per-devcontainer
      `*-r-site-library-*` / `*-venv-*`). Suggest the commands; don't
      push for it.
- [ ] Update the 0921a header to say it has been implemented, pointing
      here.

## log

- 2026-09-25: decisions recorded; nothing implemented yet. Starting state:
  the site library holds 227 packages (34 top-level, spacyr included); the
  old TeX volume is 11 GB with no marker.
- 2026-09-25, TeX selection, from the full tree's `texlive.tlpdb` (CTAN is
  firewalled in the container). LuaTeX cannot be dropped: `luatex` and
  `luahbtex` are in `collection-basic`, and profiles cannot deselect
  packages. No selected collection pulls in `collection-xetex`. Estimated
  size is about 3.0 GB without docs and 5.7 GB with them. The user agreed to
  `tlpdbopt_install_docfiles 0` and `tlpdbopt_install_srcfiles 0`, so
  `texdoc` will not work. `latexindent` and `latexmk` are not in the
  collections; the user agreed to put them in `TEX_PKGS` (latexindent's Perl
  deps are in the Dockerfile, and latexmk is LaTeX Workshop's default).
- 2026-09-25, install-tl profile trap: once a profile names any collection,
  the scheme's collection list is ignored (install-tl manual, "Profiles").
  The scheme's own packages still install (`calc_depends`). So
  `TEX_COLLECTIONS` lists scheme-small's four collections explicitly, and
  a marked tree's add step checks collections as well as `TEX_PKGS`.
- 2026-09-25, **accidental write to an old volume.** While testing the R
  script in the container, `verify` reported `fuzzyjoin`, `lexicon` and
  `quanteda.textstats` absent from *this* container's site library. That
  contradicts decision 1's inventory, which was presumably taken from
  another devcontainer's per-devcontainer volume. The follow-up `install`
  run then put them and 12 dependencies from P3M into this devcontainer's
  old per-devcontainer R volume. Nothing existing was replaced. Reported to the user, who chose
  to leave the 15 packages in place. Decision 1's list stands.
- 2026-09-25, phase 1 code checks done in the container: the TeX smoke test
  passes against the old full tree (about 12 s); R `verify` then passes
  (50 packages) and a rerun of `install` downloads nothing; `packages.sh`
  was dry-run against a stub `docker` (0, 1 and 2 containers; targets;
  `cli` rejected); `install-packages.sh tex` in the container refuses the
  old unmarked volume without writing. The `install-tl` path itself is
  verified only by the host build.
- 2026-09-25, `packages.sh` details: it is bash 3.2-safe (macOS `/bin/bash`).
  It looks up the container label under the symlink-resolved path first, as
  `bbox` does, then the logical path. Volume names are staged as
  `// packages.sh: <mount>` comment lines, read by
  `.host/dc-resolve.py package-volumes`, which refuses `${...}` names.
  `shellrc.sh:26` now says `install-packages.sh python r`, because a bare
  call means `cli`.
- 2026-09-26: host ran `bash .setup/packages.sh all` successfully. The pasted
  tail began inside the TeX step and ended with `pdflatex, biber,
  latexindent, latexmk OK`, `LyX export OK`, `TeX stack OK (10 collections,
  2 extra packages)` and `Done.`. The Python and R OK lines and the
  `Builder image:` line were above the paste. Both stacks must have passed:
  the installer runs python, r, tex in order under `set -e`, so tex is only
  reached after both verifications succeed.
- 2026-09-26: phase 1 host checks all passed, per the user. The checks ran
  as node against each new volume mounted read-only, in the devcontainer's
  image. R: `library()` of every package in the site library, each in a
  fresh process. Python: import of all 22 `PY_PKGS` modules. TeX:
  read-only mount, marker, the installer's `tex_smoke`, `tex-refresh`, no
  xetex. Idempotence: `packages.sh python r` rerun. Phase 1 is complete.
- 2026-09-26, phase 2 code. `install-packages.sh` gains `--verify`, which
  checks without writing. `test-packages.sh` uses it, so the package lists
  stay in one place. The Python check now imports every public top-level
  module of each `PY_PKGS` distribution, 27 modules in total, with import
  noise captured. The read-only guard uses `findmnt` options. It covers
  python, r and tex, and `--verify` bypasses it.
- 2026-09-26: `SANDBOX-AGENTS.md` is a symlink to `SANDBOX-CLAUDE.md`, and
  `seed-agent-guidelines.sh` symlinks `~/.claude/CLAUDE.md` and
  `~/.codex/AGENTS.md` to them. So one edit changed the guidance, and it
  was live in this container at once. A correction to my own draft:
  scheme-small does install `fontspec` and `unicode-math`, and LuaLaTeX
  works. The guidance now says "no XeLaTeX; build with pdflatex" and no
  longer claims those packages are absent.
- 2026-09-26: `init-firewall.sh` got a comment change only. The allowlist is
  unchanged, since P3M and PyPI still serve in-container downloads.
  Shellcheck's SC2154 at its line 21 predates this branch.
  `docs/storage-needs.md` got a dated note instead of new numbers;
  re-measuring is a checklist item for after the rebuild.
- 2026-09-26: 0923a has not landed. Phase 2 removed the venv `chown` and
  the site-library `chmod`/`chown` lines, left the
  `mkdir -p /sandbox /home/node/...` line alone, and added the post-start
  package check *before* the unchanged `tex-refresh` line.
- 2026-09-26: `test-packages.sh` partial run in the old (phase 1) container
  passed in 39 s: `--verify python r`, 223 R packages load, fixest, parquet
  round trip, and the TeX/LyX checks against the old full tree. The
  read-only and refused-install sections need the rebuilt container. R's
  refusal wording (`not writable`) was confirmed on a read-only directory.
- 2026-09-26: dropped the phase 2 step "repeat `test-packages.sh` in a second
  project". That step took "project" in 0921a's sense, a separate
  devcontainer. A new project (a workspace folder) runs in the existing
  devcontainer, for example via `bbcode Research-vs/`, so it tests nothing
  new. Only a second sandbox checkout gets its own devcontainer, and the
  design doesn't use one. One pass in the rebuilt devcontainer is enough.
  `packages.sh` builds each volume under the literal name in
  `devcontainer.json`. If the mounted name didn't match, Docker would mount
  an empty volume and the test's R and Python loads would fail.
- 2026-09-26: consumer-first creation order passed on the host, per the
  user: a throwaway venv volume mounted read-only first held the skeleton and
  failed `--verify python`; building into it and re-verifying read-only
  passed.
- 2026-09-26, re-measured with `du -sh` in the rebuilt devcontainer (all
  three package mounts `ro`): TeX 3.0 GB, venv 1.2 GB, R 536 MB (4.7 GB
  shared); npm-global 560 MB, codex 396 MB, claude 26 MB, history 48 KB
  (1.0 GB per checkout). `docs/storage-needs.md` and the README budget now
  use these figures. The image itself was not re-measured (no Docker in the
  container); its 3.42 GB figure predates TeX Live and the CLIs leaving it.
