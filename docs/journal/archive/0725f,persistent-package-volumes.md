# Persistent package volumes: runtime installs that survive recreation

Date: 2026-07-25 (NY)

## The goals clarification that settled it

[0725e]'s postscript left open whether to bake tricky packages (`arrow`) into
the image. Discussing it surfaced that I had the goals wrong. The point of
moving installs to runtime ([f12d37c]) is **fast, debuggable image builds and
a low barrier for other users to try the container**. Runtime install speed
was never a goal, and runtime compiles were never assumed cheap.

That kills the baking idea in both forms:

- Baking the whole stack restores the 20+ minute build that made Dockerfile
  debugging miserable — any change at or before the install layer re-pays it,
  and a failed build restarts from zero, whereas a failed
  `install-packages.sh` run resumes (it skips what is installed).
- Baking only the "tricky" packages is worse than it sounds: `arrow` is the
  single most expensive compile in the stack, so it is precisely the package
  that would reinstall the build-time deterrent.

Also noted: the aarch64 compile pain is local to this machine class. x86_64
users get P3M binaries for everything, `arrow` included — the adoption story
is mostly an x86 story, and there runtime installs are already fast.

## The remaining cost, and the fix

With installs at runtime, packages live in the container's writable scratch
layer, so every container **recreate** ("Rebuild Container", devcontainer.json
edits) silently discards them and the next install run recompiles everything —
acute here, where everything builds from source. The fix that preserves fast
builds is persistence, not baking: two named volumes in `devcontainer.json`:

```
<workspace>-r-site-library-4.5.3  ->  /opt/R/4.5.3/lib/R/site-library
<workspace>-venv-py3.11           ->  /opt/venv
```

First install on a machine fills the volume; recreates find it full and the
install script skips everything. Compiles become per-machine, not
per-container, and the image build gains zero seconds.

## Design notes

- **Zero-config library path ("option A").** R automatically prepends
  `$R_HOME/site-library` to `.libPaths()` whenever the directory exists, and
  `install.packages()` targets `.libPaths()[1]`. So no `R_LIBS_SITE`, no
  `Renviron.site` edit — the Dockerfile just creates the directory. One less
  setting in existence beats one well-placed setting.
- **Ownership via copy-on-first-use.** The Dockerfile creates `site-library`
  owned by `node` (`/opt/venv` already was). An empty named volume inherits
  the image directory's contents and ownership on first mount, so there is no
  postCreate chown step.
- **Version-stamped names.** Guards the one staleness mode that is not benign:
  a volume of 4.5.3 binaries mounted into a future R 4.6 image would crash,
  not just lag. Stamping the version into the name makes an upgrade start a
  fresh volume automatically — at the cost of manually bumping the mount
  lines alongside `R_VERSION` (devcontainer.json cannot read Dockerfile ARGs).
- **Python volume buys less but costs nothing.** PyPI has aarch64 wheels for
  the whole stack, so venv fills are minutes, not tens of minutes. Included
  anyway: one line, saves ~2GB of re-downloading, and keeps both stacks'
  recreate semantics identical — no "packages survive, except for R" trap.
- **Accepted staleness.** With full volumes, `install-packages.sh` is a no-op
  and the install path goes untested until the package list changes; the
  delta path stays exercised exactly when someone is watching. Deliberate
  trade, per the goals above.
- **Truly fresh** now means deleting the volumes too:
  `docker volume rm <workspace>-r-site-library-4.5.3 <workspace>-venv-py3.11`
  (after removing the container that holds them).

## First fill

Next rebuild starts with an empty site-library, so `install-packages.sh`
installs all 36 R packages once — `arrow` through the apache/jfrog allowlist
entries added in [0725e]. The 35 packages installed earlier today lived in
the old container's scratch layer and are discarded with it.

[0725e]: 0725e,rspm-cdn-rotation.md
[f12d37c]: ../../.devcontainer/Dockerfile
