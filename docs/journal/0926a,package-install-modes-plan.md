# 0926a — plan: three working modes, writable package volumes, lean builds

Discussion snapshot, 2026-09-26, branch `feature/read-only-package-volumes`.
Decided in outline; not yet implemented. Builds on
[0921a](0921a,BUMP-read-only-package-volumes-plan.md) and
[0925b](0925b,BUMP-package-volumes-implementation.md), and uses 0925b's terms.

## the idea

Read-only package volumes keep agents from changing the environment. The cost
is that every missing package means a trip to the host. Keep read-only as the
default, and add a switch that makes the volumes writable, so the user can
install packages the usual way (`install.packages()`, `pip install`,
`tlmgr install`) while watching.

With that route available, the host build shrinks to a lean base. Everything
else we use today moves to a script the user runs once in the writable mode.

## three modes

Two independent switches in `SANDBOX.toml`: the existing `firewall`, and a new
`packages = "readonly" | "writable"`. (0923b rejected a single `yolo` switch.)

| Mode | `firewall` | `packages` | Use |
|---|---|---|---|
| 1. YOLO work (default) | `true` | `"readonly"` | everyday work; agents ask when a package is missing |
| 2. Chaperoned internet work | `false` | `"readonly"` | open web access, with the user watching |
| 3. Careful package installs | `false` | `"writable"` | the user installs packages, then switches back |

Changing `firewall` takes a container restart. Changing `packages` takes
`bbox --rebuild`, because mounts are fixed at container creation. That
recreates the container from the cached image. In mode 3, agents install only
when the user asks.

## the switch

It works the same way as the `seccomp` switch:

- `bbox` reads `packages` from `SANDBOX.toml` and exports it.
- The three package mounts in `devcontainer.json` end in
  `readonly=${localEnv:SANDBOX_PKG_READONLY:true}`, so a folder opened without
  `bbox` stays read-only.
- `bbox` checks the created container's mounts, as it checks seccomp.

`packages.sh` also runs `chown -R node:node` over the volumes it builds, so
installs in mode 3 work as `node` without sudo. `post-start.sh` prints the
current mode, and in mode 3 a reminder to switch back.

## lean base and standard set

**Base (host build, `packages.sh`):** only what the sandbox itself needs, plus
a small core. Proposal, for the user to adjust:

- **Python:**
  - tools: `requests`, `PyMuPDF`, `pikepdf`, `openai`, `mistralai`;
  - core: `numpy`, `pandas`, `pyarrow`, `matplotlib`, `statsmodels`,
    `pyfixest`.
- **R:**
  - tooling: `languageserver`;
  - tests: `arrow`, `fixest`;
  - core: `data.table`, `tidyverse`, `modelsummary`, `sandwich`, `lmtest`.
- **TeX:** `scheme-small`, `collection-bibtexextra`, `latexindent`, `latexmk`,
  and whatever a default LyX export needs.

**Standard set (mode 3, `install-standard-set.sh`):** everything else we use
today, including `pryr` and Bioconductor. This removes the archive and
Bioconductor code from the host builder. The script:

- refuses unless the mounts are writable;
- uses the ordinary commands, so reading it also shows how to add a package by
  hand;
- skips what is already installed, and checks the result at the end.

Its lists are the record of what we use. A package that turns out to be
generally useful is added there. Anything installed ad hoc in mode 3 and not
added is lost when a volume is rebuilt, which is acceptable.

Setup becomes:

1. On the host, `bash .setup/packages.sh all`.
2. Switch to mode 3.
3. Run `bash .devcontainer/install-standard-set.sh`.
4. Switch back to mode 1.

After a version bump, repeat.

## work list

1. `SANDBOX.toml` key and parser; `bbox` export and mount check.
2. `devcontainer.json` mounts; `chown` in `packages.sh`.
3. Lean lists in `install-packages.sh`. Remove its archive and Bioconductor
   code. Point the startup sentinels at base packages.
4. `install-standard-set.sh`.
5. `post-start.sh` mode line; agent guidance for the three modes.
6. Tests:
   - `test-packages.sh` checks that the mounts match the mode;
   - an optional check of the standard set.
7. Docs: `.setup/README.md`, `.devcontainer/README.md`, `docs/features.md`,
   root README.
8. On the host:
   - build the lean base under new volume names;
   - `bbox --rebuild` in mode 1 and run the tests;
   - switch to mode 3, run the standard set, switch back.

## things to check

- In mode 3, `install.packages()` writes to the shared site library, not a
  personal library.
- `tlmgr install` works as `node`; run `tex-refresh` afterwards.
- pip installs resolve against current PyPI and can replace dependencies.
  That is one reason mode 3 is supervised.
