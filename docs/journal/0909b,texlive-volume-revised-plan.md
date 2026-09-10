# Revised plan: TeX Live in a shared read-only volume

Date: 2026-09-09 (NY)

Status: proposed; no implementation in this entry.

Revises [the September 2 plan](0902a,texlive-out-of-the-image-plan.md)
following review against the current Dockerfile and startup configuration.
That entry retains the original motivation, storage measurements, and Docker
experiments. Its experiments establish mount behavior, not a validated TeX or
LyX installation.

## Decision

Install upstream TeX Live with the full scheme into a named Docker volume,
using an explicit host-side builder. Mount it read-only in devcontainers and
share it across projects on the same Docker daemon. Remove apt's `texlive-full`
and `biber` from the image once the replacement passes the checks below.

Use one volume per TeX Live year and Ubuntu compatibility token, with a fixed
name: `texlive-2026-noble`. Support one target architecture per daemon in this
initial design; the name itself does not encode architecture. TeX Live 2026
was released on March 1, 2026; see [TUG's release page](https://tug.org/texlive/).

Keep the first implementation small: serialize builders, record successful
completion, and require TeX work to stop during updates. Separate revision
volumes, automatic rollback, and uninterrupted updates are outside this plan.

## Host setup and architecture

Add a builder under `.setup/`, with a README and script header documenting how
to run it, its inputs, and its outputs. Describe this directory as host-side
machine setup and maintenance: the builder runs again for explicit updates,
not just once per machine. Link it from `.host/README.md` while keeping that
directory's navigation scope. Both READMEs must state the lifecycle distinction:
`.host/` is session navigation, `.setup/` is host machine setup and maintenance,
and `.devcontainer/` defines the container. Do not copy the original plan's
"once per machine" wording verbatim.

The builder uses a throwaway Ubuntu container with the volume mounted
read-write. Explicitly install `perl`, `wget`, `ca-certificates`, and
`xz-utils` in the bare Ubuntu builder before running `install-tl` with an
explicit noninteractive full-scheme profile. All system TeX trees must be inside the mounted prefix; user cache paths must
remain writable outside that prefix. Do not use portable mode, which changes
the relationship between user and system trees.

The builder runs outside the devcontainer firewall. This is a user-invoked
host setup action; opening a folder must never initiate a download or update.

Hardcode the mount in `devcontainer.json`:

```text
source=texlive-2026-noble,target=/usr/local/texlive,type=volume,readonly
```

Keep the year/token in the builder and Dockerfile year argument consistent
with this literal, and check their agreement during implementation validation.
No new host environment variable is required. The existing Docker `--env-file`
mechanism cannot supply values for devcontainer mount-string interpolation.

Derive the builder architecture with `dpkg --print-architecture` in its Ubuntu
container: `amd64` maps to `x86_64-linux`, `arm64` to `aarch64-linux`. Before
mutating an existing installation, verify its recorded architecture and binary
directory match the builder target; refuse a mismatch. The consumer readiness
check must also compare its own architecture with the metadata and binary
path, since users may change their Docker platform selection without running
the builder again.

This supports either native arm64 or native amd64 Docker setups with the same
configuration. Mixed architectures on one daemon, including switching a
populated volume to an emulated target, are outside the initial scope and must
produce a clear mismatch diagnostic. Supporting both architectures in one
installation can be considered later; it is not needed to remove the host
environment-variable plumbing.

As part of host setup, verify the selected release against TUG's release
information and repository metadata. The repository year check below is the
machine-enforced guard; the release-page citation alone is not validation.

## One rerunnable setup script

Run the same `.setup/` script to install or update. No subcommands or status
mode. Before rerunning it, stop TeX/LyX work in every project sharing the volume.
Read-only consumers still see changes made by the builder.

The script uses `docker run --rm --name texlive-builder` to prevent concurrent
builders. Keep all mutations inside that container. If the name is already
reserved, fail clearly; never remove another running builder automatically.
Report any stopped container that needs explicit cleanup after a failure.

After checking the repository year and installed architecture:

- Empty volume: install the full scheme with `install-tl`.
- Completed installation: run `tlmgr update --self --all`.
- Nonempty installation without a completion marker: stop and print a concrete
  recovery instruction appropriate to the failed install or update. Preserve
  the tree and logs; do not silently delete it or treat it as healthy.

Use `/usr/local/texlive/.tl-ready.json` as the completion marker, containing
only the year and architecture. Remove it before mutation. Check installation
commands and format/font-map generation, then run a small PDF compilation
check. Installer exit status alone is insufficient because some
post-installation failures are nonfatal by default; see the
[installer manual](https://www.tug.org/texlive/doc/install-tl.html).
After success, write a temporary marker in the same directory and rename it
into place. On failure, leave the marker absent and print the recovery
instruction. Print the in-container LyX refresh command after success.

No package revision inventory, generation tracking, automatic rollback, or
live updates. The normal procedure is: stop TeX work, rerun setup, refresh LyX
in each consuming container, resume work.

Initially use the current repository for the configured release, with a year
check before mutation. This deliberately allows package versions to change
between runs and affects all projects sharing the volume. A frozen repository
can be selected later without a devcontainer firewall change; once available,
2026's `tlnet-final` is a candidate. Exact recreation from an older snapshot
requires a fresh installation, not simply repointing an updated tree. A new
release year uses a new volume and matching image/path configuration.

## Image dependencies and PATH

Remove `texlive-full` and apt `biber`; use upstream's matching biber/biblatex
pair. Keep the existing latexindent Perl modules and `librsvg2-bin`.

Add an explicit `ghostscript` apt entry to preserve the tool currently supplied
transitively by `texlive-full`. Do not add
ImageMagick solely for EPS conversion. EPS and ImageMagick-dependent workflows
are outside the initial acceptance criteria; any workflow that needs them
must declare and test those dependencies separately. Retaining Ghostscript
alone is not a claim of complete graphics-conversion parity.

Audit the dependencies lost when `texlive-full` is removed, especially shared
libraries or utilities required by the upstream binaries, and dependencies
needed by subsequent image build steps. Validate both a clean image build and
runtime: success in the old image could rely on those transitive packages.
Add the dependencies needed for the image build and accepted workflows.

Use the original plan's architecture mapping to create
`/usr/local/texlive-bin` as an image-side symlink into the selected year's
volume tree, and put it on `ENV PATH`. It may dangle at image build time.
Ensure TeX is available to noninteractive processes as well as login shells.

## LyX configuration and startup

Remove the Dockerfile's system-wide `configure.py` scan. At runtime, run the
scan as `node` from LyX's actual writable user configuration directory, using
the installed configuration script. The existing `/usr/local/share/lyx`
directory and defaults are root-owned and cannot simply be reused as the
working directory for this runtime command.

Add one in-container refresh helper that checks readiness and runs the user
scan. Run it at startup when TeX is ready, and explicitly after rerunning host
setup. No generation comparisons or successful-scan tracking. Avoid running
multiple refreshes at once in the same container.

This accepts the per-project and startup scan cost the system-wide scan
avoided. The current mount list does not persist `~/.lyx`, so container
recreation also needs a fresh scan. Adding LyX persistence is outside this
change. Check that existing user configuration does not retain stale converter
detection after refresh.

Run the helper at startup after the mandatory firewall step. Handle only the
helper's failure locally, with a warning; never append `|| true` to the whole
startup chain. Missing TeX must not prevent the rest of the container from
starting. Append the guarded helper to the existing successful chain:

```sh
mandatory_steps && { tex-refresh || { echo "TeX/LyX refresh failed" >&2; true; }; }
```

Do not append `; { tex-refresh || true; }`: that runs even after an earlier
failure and can replace the firewall failure's exit status with success.

When the volume is populated after startup, binaries become visible without a
container restart, but LyX still needs a refresh. Have the builder print the
in-container refresh command, and document that each consuming container must
run it before its next LyX export. Account for an already-running LyX process
needing reconfiguration or reopening. Do not promise automatic recovery from
filesystem visibility alone.

Add a concise interactive-shell warning for an empty, incomplete, or
incompatible installation, with the host setup command and recovery guidance. Check the
readiness metadata as well as binary presence. This warning helps diagnosis;
it does not enforce the update maintenance window.

## Acceptance checks

Run these against the rebuilt image, as `node`, with the real volume mounted
read-only and fresh user caches:

- Compile a representative PDF with pdflatex, biber, and the required repeat
  pdflatex passes; verify references resolve.
- Export a representative math-and-bibliography document through LyX after
  running the user configuration helper.
- Run latexindent and any other engines or tools claimed as supported by the
  migration. Check upstream binaries for missing runtime libraries.
- Confirm generated caches stay in writable user locations and that the TeX
  tree remains read-only to the consumer.
- Start with an empty volume, verify the container and firewall start, then
  populate it and verify PDF compilation and LyX export after refresh.
- Interrupt an installation and verify the marker remains absent and rerunning
  setup reports recovery instructions. Attempt concurrent builders and verify
  the fixed container name prevents overlap.
- Rerun the setup script on a completed installation while TeX work is stopped,
  refresh LyX explicitly, and repeat the representative exports.
- Check volume-name/platform consistency on arm64 and amd64. If one platform
  cannot be exercised, record that limitation rather than claiming validation.

The marker and installer checks should be lightweight operational checks;
the full migration acceptance exercise need not run on every startup.

## Rollout

Removing `texlive-full` invalidates the layer above the LyX source build, so
LyX and the subsequent layers must rebuild. The Dockerfile estimates a
roughly 30-minute rebuild, but no measured LyX-only duration was found; do not
attribute that estimate to LyX compilation alone. Record layer timings during
implementation. Use this already-required rebuild
to fold `libfontconfig-dev`, `libjpeg-dev`, and `libtiff-dev` into the earlier
system-library block, as its comment requests. Consolidate the latexindent
Perl dependencies and `librsvg2-bin` into an appropriate earlier apt block too.

Implement host setup and validate a real upstream installation first. Then
change the Dockerfile, mount configuration, LyX helper, and startup warning
together. Complete the clean-image acceptance checks before retiring the apt
setup. Update environment documentation and canonical agent guidelines to
describe the host-managed read-only TeX installation and rerunnable setup script.

Keep the old image and volume state until acceptance is complete; disk pruning
is a separate explicit action. Remote Docker setups require a shell able to
operate the relevant daemon, and Codespaces need a separate provisioning path.
Neither is claimed as supported by this initial rollout.

## Rollback if acceptance fails

Restore the prior Dockerfile dependency layout, including `texlive-full` and
`biber`, and restore its build-time system-wide LyX `configure.py` scan. Remove
the TeX volume mount and image-side PATH/symlink additions, and revert the
runtime refresh hook and shell warning. Rebuild and recreate the container
(or explicitly select the retained old image with the reverted configuration),
then check the previous PDF and LyX workflows. If reusing a user configuration
directory, refresh it against the restored apt toolchain.

Leave the external TeX volume intact for diagnosis; removing the mount does
not require deleting its data. This rollback restores the apt-based
architecture, not a previous upstream package revision after an in-place
volume update. Recovery from such an update remains the explicit repair/retry
procedure described above.
