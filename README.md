# Workspace Sandbox

This repository root is a shared sandbox for active projects plus the harness used to build and run agentic tooling around them.

The rest of the root-level files and directories are primarily support infrastructure.

Root-level dot folders:

- `.credentials/`: local credential and environment support
- `.devcontainer/`: shared root devcontainer for the sandbox environment
- `.devcontainer/agents/`: canonical agent guidance and enforced agent settings (see `.devcontainer/README.md`)
- `.git/`: repository metadata
- `.tools/`: local utility scripts for workspace maintenance and document processing

Project-specific setup can still live inside individual project directories. The root `.devcontainer` is the shared workspace container used for the overall sandbox and build/tooling flow.

## Setting up a new machine

Do these once per computer, in order. Steps 1-4 run on the Mac; step 5 runs
inside the container.

1. **Install the host prerequisites:**

   - [Docker](https://www.docker.com/), running
   - the [`devcontainer` CLI](https://github.com/devcontainers/cli):
     `npm i -g @devcontainers/cli`
   - `python3`, and the `code` CLI if you want `dccode`

2. **Load the host-side shell functions.** These open and navigate the
   containers (`dcu`, `dce`, `dccode`). Add one line to `~/.zshrc`, pointing at
   wherever you cloned this repo, then reload with `exec zsh`:

   ```zsh
   source /path/to/1-SANDBOX/.host/devcontainer.zsh
   ```

3. **Give the Mac a short name**, before building the container. It prefixes
   every Claude session name, so `MacBook25` reads better than
   `Andrews-MacBook-Pro`. Set it under **System Settings → General → About →
   Name**. If you change it later, recreate the container so the new value is
   picked up.

4. **Save your credentials**, from the host, so the container can mount them
   through a protected host-side file:

   ```bash
   python .credentials/setup.py
   ```

   Nothing that touches WRDS or an LLM API works until this is done.

5. **Install the analysis stacks**, inside the container, after a fresh build.
   The image ships without the Python and R packages; interactive shells nudge
   you while either is missing.

   ```bash
   .devcontainer/install-packages.sh          # both, a few minutes
   .devcontainer/install-packages.sh python   # or one at a time
   .devcontainer/install-packages.sh r
   .devcontainer/install-packages.sh --force  # reinstall even if present
   ```

Optional: the container picks up the Mac's timezone automatically. To force a
different one, export it on the host before the container starts.

```bash
export TZ=America/Chicago
```

## Devcontainer storage

Budget roughly **5.5GB per checkout**: a 3.42GB image plus about 2.0GB of
persistent volumes (the Python venv and R library dominate), with the BuildKit
build cache on top.

Docker's default `20GB` BuildKit garbage-collection budget was once too small
for this container and caused expensive layers to be evicted between rebuilds.
That is no longer clearly true: after the analysis stacks moved to runtime
installs and the base migrated to `ubuntu:24.04`, a 2026-07-26 measurement found
a **3.42GB** image, down from 24.2GB on 2026-07-20.

So raising the budget to `35GB` is headroom now, not a fix — do it if you hit
slow rebuilds, not by default. See
[Devcontainer storage needs](docs/storage-needs.md) for the settings and for how
to tell whether eviction is actually what is happening to you.

## Plans for eventual public release.

We will **eventually** clean up the git history in a way that allows for public release. But our immediate goal is a quality sandbox for AI powered econ research.
