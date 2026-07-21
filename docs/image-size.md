# Devcontainer image size and build cache

The shared workspace devcontainer is built locally from
`.devcontainer/Dockerfile`, starting from the official `node:20` image. It is a
large image: a measurement on 2026-07-20 found a 24.2GB image and about 25.05GB
of BuildKit cache use.

## BuildKit garbage-collection budget

Docker's `20GB` default garbage-collection budget is smaller than the build's
working set. BuildKit consequently evicts large cached layers, especially the R
toolchain and package layers. Even a minor devcontainer change can then cause
those unchanged layers to rebuild, turning a routine rebuild into a roughly
20-minute operation.

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
- globally installed AI CLIs, LyX, Pandoc, and related tooling.

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
