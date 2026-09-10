# TeX Live volume: simplify the first implementation

Date: 2026-09-09 (NY)

Status: proposed implementation scope; nothing installed or changed yet.

Follow-up to [0909b](0909b,texlive-volume-revised-plan.md). That plan added too
much operational machinery for the immediate objective: install TeX Live into
a Docker volume using `install-tl`, then use it from the devcontainer.

## First implementation

1. Add one host-side script under `.setup/`, with a short README and a script
   header documenting invocation, inputs, and outputs. Run a temporary Ubuntu
   24.04 container with `texlive-2026-noble` mounted read-write at
   `/usr/local/texlive`. Install the installer prerequisites (`perl`, `wget`,
   `ca-certificates`, `xz-utils`) there, then run `install-tl` with an explicit
   noninteractive full-scheme profile for the selected release.
2. Mount that volume read-only at `/usr/local/texlive` in the devcontainer.
   Select the binary directory from the container architecture: amd64 uses
   `x86_64-linux`, arm64 uses `aarch64-linux`. Put an image-side symlink on
   `ENV PATH` so noninteractive commands can find TeX too. Support one
   architecture per populated volume.
3. Remove apt `texlive-full` and `biber` once the upstream installation has
   been checked. Retain the latexindent Perl dependencies and `librsvg2-bin`,
   explicitly retain Ghostscript, and consolidate the deferred graphics
   development libraries during the already-required rebuild. Check for
   dependencies accidentally lost with apt TeX.
4. Move the LyX converter scan from image build time to runtime, as `node`,
   in its writable user configuration directory. Provide a small refresh
   helper and run it after the mandatory firewall startup step. Missing TeX
   or a failed refresh should warn without hiding a firewall failure. Run
   the helper manually if the volume is populated after container startup;
   an already-running LyX may need reopening.
5. Validate the rebuilt image with the real volume mounted read-only:
   compile a document with math and a biber bibliography, export through
   LyX, and run latexindent. Check that user caches are writable outside the
   installation. Check that the container still starts with an empty volume.
   Record the architecture actually tested.

Keep the installation profile explicit about system trees staying inside the
volume and user caches staying outside it. Verify that the repository serves
the intended release before installing. These are basic installation details,
not a new lifecycle framework.

## Deliberately deferred

- Automatic or rerunnable update management.
- Completion markers and installation-state machinery.
- Builder locking and concurrency tests.
- Automated recovery, rollback, revision inventories, or generation tracking.
- Cross-architecture validation beyond the platform available for this work.

Treat the successfully installed volume as fixed for this first version.
Do not run multiple installers against it, and do not mutate it while TeX/LyX
work is using it. A second invocation should refuse an existing nonempty
installation rather than silently update or overwrite it. Updates can get a
separate explicit procedure when needed.

If installation fails, inspect and retain the installer output before deciding
whether to retry or explicitly recreate the volume. No automatic deletion or
claim of a general recovery procedure. Preserve the existing image until the
replacement passes the practical checks; disk pruning is separate work.

Document the host setup command and the lifecycle distinction: `.setup/` is
host machine setup and maintenance, `.host/` is session navigation, and
`.devcontainer/` defines the container. Update the canonical environment and
agent documentation when implementing. Opening a project must not download
TeX Live.

The earlier entries remain useful background, but their larger acceptance
matrix and maintenance machinery are outside this first implementation.
