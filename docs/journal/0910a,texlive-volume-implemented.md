# TeX Live volume implementation and validation

Date: 2026-09-10 (NY)

Implemented the small scope from [0909c](0909c,texlive-volume-simple-plan.md).
Earlier plan entries remain unchanged.

- `.setup/texlive.sh`: full-scheme upstream installation into the shared
  `texlive-2026-noble` volume; refuses nonempty volumes. No update machinery.
- Devcontainer: read-only mount, architecture-selected binary symlink on
  image PATH, apt TeX/biber removed, supporting dependencies retained.
- `tex-refresh`: user-level LyX detection in `~/.lyx`, guarded after mandatory
  startup steps. Shell warning and host/environment/agent docs updated.
- `.devcontainer/tests/test-texlive.sh`: repeatable consumer acceptance check.

## Installer failure and repair

All 5,177 packages downloaded, but the initial plain Ubuntu builder lacked
`libfontconfig.so.1`. XeTeX could not start, so strict format generation failed
for five formats and exited 5. The install tree and original `install.log`
survived as intended. This was a missing builder dependency, not a reason to
weaken format checks.

Added `libfontconfig1` to the builder prerequisites. Verified with `ldd` that
this was the missing XeTeX dependency on arm64. With no running containers
consuming the volume, used a temporary Ubuntu builder with the corrected
prerequisites to run `fmtutil-sys --all`, `updmap-sys`, and pdfLaTeX/XeLaTeX
smoke compilations against the existing installation. No TeX package download
or deletion was needed.

Repair passed: **53 enabled formats rebuilt, 3 disabled**, both smoke PDFs
compiled. The volume's `repair-formats-20260910.log` records the successful
repair; its original `install.log` still records the initial failure. The
normal setup script now checks both pdfLaTeX and XeLaTeX before success.

## Validation actually performed

Docker Desktop, native Linux arm64, Ubuntu 24.04. Built the separate image
`codex-texlive:2026-noble`. Existing user images/containers were retained.
The Dockerfile's build steps ran against the new dependency layout; only the
base-image step was cached. Selected BuildKit layer timings:

- Core tools: 23.1 seconds.
- Node install: 8.8 seconds; Git build: 8.8 seconds.
- Workflow libraries: 15.5 seconds.
- LyX dependency installation/source build: 70.0 seconds.
- R installation: 12.4 seconds.
- Image export: 22.0 seconds.

Passed as `node` in a fresh test container, with the real volume read-only
and the firewall enabled:

- pdfLaTeX + biber + repeat passes: equation and bibliography references resolve.
- XeLaTeX smoke compilation; accepted binaries have no missing linked libraries.
- latexindent execution.
- LyX user configuration, then a second scan replacing stale generated detection.
- Native `tex2lyx` import, LyX LaTeX export followed by explicit compilation,
  and direct LyX PDF export. Extracted PDF text includes Knuth (1984), the
  bibliography, and equation (1).
- User TeX trees resolve inside the writable home directory. The volume mount
  reports `ro`; an attempted consumer write fails with “Read-only file system”.

Also passed: exact devcontainer startup chain with an empty anonymous TeX
volume (firewall starts; missing TeX warns; startup succeeds), populated-volume
setup refusal, ShellCheck, shell syntax, JSON/year/mount consistency, and
startup-chain failure propagation checks.

The acceptance run exposed an incorrect import example in the repository LyX
skill: an extra output filename after `lyx -i` is treated as a document to
open. Corrected the example and test to use the installed `tex2lyx` CLI with
its explicit output argument.

Temporary host evidence: `/tmp/texlive-2026-image-build.log`,
`/tmp/texlive-empty-startup.log`, `/tmp/texlive-repair-host.log`,
`/tmp/texlive-acceptance-host-v2.log`, and `/tmp/texlive-acceptance-passed/`.
These host paths are disposable; the installation and repair logs also live
in the TeX volume. The stopped validation containers retain their test files.

amd64 was not exercised. The corrected dependency/format stage was validated
against the already-downloaded installation, not by downloading a second full
copy. No active user devcontainer was replaced. Rebuild/recreate consuming
devcontainers to adopt the new mount/PATH configuration; `tex-refresh` runs
at normal startup. Updates, recovery automation, and disk pruning remain
outside this implementation.
