# Devcontainer image size and build cache

The shared workspace devcontainer is built locally from
`.devcontainer/Dockerfile`, starting from the official `ubuntu:24.04` image.

Sizing has changed substantially and the older figures below should be read as
history, not as current numbers. A measurement on 2026-07-20 found a 24.2GB
image and about 25.05GB of BuildKit cache use. A measurement on 2026-07-26,
after the Ubuntu base migration (docs/journal/0726a), found a **3.42GB image
built cold in about 9 minutes** on arm64. Two changes account for the drop, and
only one of them is the base swap:

- the analysis stacks moved out of the image to runtime installs
  (docs/journal/0725f), which removed the R and Python package layers entirely;
- the base migration itself, which mostly moved cost around rather than down —
  it added a Qt5 toolchain for the LyX source build (about a minute of compile)
  and TeX Live 2023 at 3.2GB is still the single largest component.

## BuildKit garbage-collection budget

Against the old ~24GB working set, Docker's `20GB` default garbage-collection
budget was too small. BuildKit consequently evicted large cached layers,
especially the R toolchain and package layers, and even a minor devcontainer
change could then force those unchanged layers to rebuild — turning a routine
rebuild into a roughly 20-minute operation.

At the current ~3.4GB that no longer applies, so treat the `35GB` recommendation
below as headroom rather than a fix for an active problem. The diagnostic at the
end of this file is the way to tell whether eviction is actually happening to
you.

Set the cache budget to `35GB`. In Docker Desktop, open **Settings → Docker
Engine** and set the `builder.gc` section of `daemon.json` to:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "35GB"
    }
  }
}
```

Apply the change and restart Docker Desktop. The **Settings → Resources →
Advanced → Disk usage limit** control is different: it sizes the Docker VM disk
rather than the BuildKit cache budget.

The first rebuild after raising the budget may still be slow because previously
evicted layers must be rebuilt once. The benefit appears on subsequent
rebuilds.

## Why the image is large

The main contributors are:

- the system-package layer containing `texlive-full`;
- the R toolchain and package libraries;
- the Python environment and installed packages;
- recursive ownership and permission changes, which create filesystem-layer
  metadata; and
- globally installed AI CLIs, Pandoc, and related tooling; and
- LyX, which is compiled from source and keeps its Qt5 `-dev` packages in the
  image (they carry the Qt runtime it links against).

An older build measurement attributed roughly 13.09GB to the system-package
layer containing `texlive-full`, 1.33GB to Python packages, 1.37GB to a
recursive ownership change on `/opt/venv`, 762MB to a recursive permission
change on the R library, and 852MB to the global npm AI CLIs. These figures are
historical rather than current sizing guarantees.

## Diagnosing cache eviction

Docker commands can report different sizes because they measure different
things. `docker image inspect`, `docker system df -v`, `docker history`, and
`docker buildx du --verbose` are therefore not directly interchangeable.
BuildKit's disk-usage view is the relevant one when comparing the working set
with `defaultKeepStorage`.

If an unexpectedly slow rebuild follows a small edit, inspect the image with
`docker history <image>`. An age discontinuity in an otherwise unchanged
Dockerfile indicates eviction: older layers below the discontinuity remained
cached, while a newer band of unchanged layers had to be rebuilt.
