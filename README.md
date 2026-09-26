# EconYoloBox

EconYoloBox is an ergonomic, AI-forward environment for economics research. It
was built by obsessively improving my research workflow (instead of doing
actual research work).

— Andrew Chen

Key features:

1. **YOLO agents by default, with a chaperoned switch**

   - **Everyday work:** run the YOLO launchers (`cchat-yolo`, `gptchat-yolo`)
     behind the container's deny-by-default firewall and Docker's builtin
     seccomp filter. These are the container defaults (`firewall = true`,
     `seccomp = "builtin"`); the launchers refuse to start without both.
   - **Internet access:** set `firewall = false` in `SANDBOX.toml`, rebuild,
     and use Claude's auto mode. Its permission classifier is much cheaper than
     Codex's automatic review, which runs a full model call per escalation.
   - **Codex sandboxed modes:** also set `seccomp = "unconfined"` and run
     `bbox --rebuild`, since builtin blocks Bubblewrap setup here. This
     disables Docker's outer syscall filter for every process.
   - See [isolation and approval limits](docs/features.md#1-safe-yolo-agents).

2. **Ergonomic container and AI access**

   - Enter the container at a project-specific path with one command.
   - Organize agent guidance and settings as code, with optional Dropbox
     synchronization.
   - Synchronize AI chat sessions across machines via Dropbox.

3. **Economics-research AI tooling**

   - Use a container image designed for fast R and Python package installation.
   - Chat with AI about math with equations rendered by a custom VS Code
     extension.
   - Search the literature with a custom OpenAlex citation-lookup tool.
   - Convert PDFs to Markdown with high fidelity using a tool built on Mistral
     OCR (h/t Don Bowen).

More concretely, it's a shared sandbox built around the following folders:

- `.credentials/`: credential injection mechanism
- `.devcontainer/`: sandbox implementation
- `.host/`: ergonomic container access
- `.tools/`: custom AI tooling

See [Sandbox Features](docs/features.md) for a detailed tour.

## Minimal setup

These instructions are for macOS and use VS Code as the primary interface. This
minimal path gets the container and AI agents running without research
credentials or the optional R and Python package stacks.
Windows and Linux support is partially wired but has not been tested.

1. **Install the host applications:**

   - [Git](https://git-scm.com/download/mac)
   - [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   - [Visual Studio Code](https://code.visualstudio.com/)
   - Python 3 (macOS: `xcode-select --install`)

   Open Docker Desktop after installing it and wait until it reports that the
   Docker engine is running. Leave Docker Desktop running while using
   EconYoloBox.

2. **Install the Dev Containers extension.** Open VS Code, select the Extensions
   icon in the left sidebar, search for `Dev Containers` by Microsoft, and click
   **Install**.

3. **Clone EconYoloBox in VS Code.** Open the Command Palette with
   **Shift–Command–P**, select **Git: Clone**, and enter:

   ```text
   https://github.com/chenandrewy/EconYoloBox.git
   ```

   Choose a destination folder, then click **Open** when VS Code
   asks whether to open the cloned repository.

4. **Build and open the container.** In the cloned repository's VS Code window,
   open the Command Palette and select **Dev Containers: Reopen in Container**.
   Direct VS Code creation uses the default `builtin` seccomp filter.

   Wait for the first build to finish. VS Code reloads with `Dev Container`
   shown in the lower-left corner when it is ready.

   The container firewall defaults on, allowing only the network allowlist.
   For open internet access, set `firewall = false` in `SANDBOX.toml` before
   starting the container; a shell warning then confirms that posture.
   Codex's sandboxed modes additionally need `seccomp = "unconfined"`, which
   disables Docker's outer syscall filter for every container process;
   see [sandbox validation and limits](.devcontainer/README.md#codex-sandbox-modes-and-launchers).

5. **Create or clone a project.** Select **Terminal → New Terminal** in VS Code.
   The sandbox repository is mounted at `/sandbox`; all user content goes
   under `/sandbox/workspace/`, which `.gitignore` excludes wholesale, so the
   outer EconYoloBox repository never sees your projects whatever they are
   named. Each project must therefore be its own Git repository. Projects that
   are finished or retired move to `/sandbox/done/`, which is ignored the same
   way; `workspace/` holds only active work.

   For a new project:

   ```bash
   mkdir -p /sandbox/workspace/My-Project
   git -C /sandbox/workspace/My-Project init
   ```

   For an existing project, clone its repository instead:

   ```bash
   cd /sandbox/workspace
   git clone https://github.com/your-name/your-project.git My-Project
   ```

6. **Install the AI CLIs.** They are not baked into the image — they live in a
   persistent volume so that updating them is not undone by the next rebuild.
   A newly created npm-global volume therefore starts without them:

   ```bash
   /sandbox/.devcontainer/install-packages.sh cli
   ```

   This takes a few seconds and installs the current Claude Code and Codex
   releases. It is needed once when the volume is first created, not per session
   or ordinary container rebuild; an interactive shell prints a reminder while
   either CLI is missing. Re-run the same command to update either npm-managed
   CLI. A new volume is created only when the old one is removed or its
   distro/Node version token changes in `devcontainer.json`.

7. **Start an AI agent from the project directory.** The first launch may ask
   you to authenticate. Start Claude with auto mode selected:

   ```bash
   cd /sandbox/workspace/My-Project
   claude --permission-mode auto
   ```

   This uses Claude's automatic permission checks where
   [auto mode is available](https://code.claude.com/docs/en/permissions#permission-modes).
   If unavailable for your account or model, use `claude` with manual approvals.

   Or start Codex with:

   ```bash
   cd /sandbox/workspace/My-Project
   codex
   ```

   For Codex, we recommend `approvals_reviewer = "auto_review"` in your
   `~/.codex/config.toml`, alongside on-request approval and workspace-write
   sandboxing. See [Codex setup and limits](.devcontainer/README.md#codex-sandbox-modes-and-launchers)
   for the configuration. To try it for one session, run `codex --approve-for-me`.
   Use `/model` or `codex --model <model>` to choose a model.

   Automatic review is a user choice; disabling the firewall does not enable
   it. Codex also has its own command network policy, so an open container
   firewall does not guarantee that every sandboxed command can reach the web.

### Switching firewall modes

`SANDBOX.toml` controls the container's outbound network allowlist. `false`
leaves the container network open; `true` enables the research and package
allowlist. After changing it, stop the container and reopen it through VS Code
Dev Containers, or use **Dev Containers: Rebuild Container**. Editing the file
does not change the running firewall, and a bare `docker restart` skips the
startup hook that reads the setting.

The `cchat-yolo`, `gptchat-yolo`, and `gptmini-yolo` launchers skip permission
checks and refuse to start unless the firewall is enabled and PID 1 has a
filtered seccomp mode. Set `firewall = true` and `seccomp = "builtin"`, then use
`bbox --rebuild` before starting YOLO work. Keep ordinary approval modes for
tasks that need review; neither a firewall nor automatic review guarantees the
safety of mounted files or accessible credentials.

## Recommended additions

The minimal setup works without these steps. Add the pieces needed for your
workflow after the container is running.

### Give the Mac a short name

A short computer name keeps Claude session names readable: `MacBook25` is
clearer than `Andrews-MacBook-Pro`. Set it under **System Settings → General →
About → Name**. Reopen the container afterward so it picks up the new name.

### Save credentials for research tools

These credentials support WRDS, Mistral, and OpenRouter tools; they
are not needed to authenticate Claude or Codex. In the Mac's Terminal, open
your checkout root and run:

```bash
python3 .credentials/setup.py
python3 .devcontainer/inject-credentials.py
```

Press Enter to skip any service you do not use. The final command refreshes the
credential file mounted in an already-running container; skip it if you have
not built the container yet.

### Build the package stacks

R, Python and TeX Live are not in the image. They live in shared volumes that
you build on the Docker host, and every project mounts them read-only. After
the container exists (it supplies the builder image), run from the checkout
root on the host:

```bash
bash .setup/packages.sh          # Python and R, a few minutes
bash .setup/packages.sh tex      # minimal pdfLaTeX TeX Live, about 3GB
bash .setup/packages.sh all      # all three
```

To add a package later, add it to the list in
`.devcontainer/install-packages.sh` and rerun the same command. See
[host setup](.setup/README.md) for the details.

## Optional host command workflow

The general-purpose `bbox` launcher validates `SANDBOX.toml`, brings the
container up, verifies its seccomp policy, and can open a shell or VS Code.
It is also the required rebuild path when selecting `unconfined`, because
direct VS Code creation always uses the `builtin` default. Ensure the VS
Code `code` CLI is installed if using `--code`. To install the launcher, run the
following from the checkout root in a host zsh terminal:

```zsh
npm install -g @devcontainers/cli
bash .host/setup.sh
exec zsh
type bbox
```

Run `bbox` to bring the container up, `bbox --code My-Project` to open a project
in VS Code, or `bbox --shell My-Project` to enter it in a terminal. Use
`bbox --rebuild` after changing `seccomp` in `SANDBOX.toml`.

VS Code's direct **Rebuild Container** command cannot inherit the validated
setting from this shell launcher. It therefore uses `builtin`, matching the
checked-in default. If `SANDBOX.toml` selects `unconfined`, a direct VS Code
rebuild will produce a mismatch warning and Codex's sandboxed modes will fail;
use `bbox --rebuild --code` to apply that setting.

Optional: the container picks up the Mac's timezone automatically. To force a
different one, export it on the host before the container starts.

```bash
export TZ=America/Chicago
```

## Devcontainer storage

Budget the container image plus about **5.7GB of volumes** for the first
sandbox checkout: 4.7GB of shared R, Python and TeX volumes, and 1GB of
per-checkout volumes (AI CLIs and their config). Each additional checkout adds
about 1GB, since the image and the package volumes are shared.

Docker's default 20GB BuildKit garbage-collection budget is adequate. If you
hit repeated slow rebuilds, raising it to 35GB gives headroom. See
[Devcontainer storage needs](docs/storage-needs.md) for the settings and for how
to confirm that eviction is the actual problem.

## TeX Live host setup

The devcontainer uses a shared, read-only, pdfLaTeX-only TeX Live volume.
Before TeX/LyX work, run `bash .setup/packages.sh tex` on the Docker host; see
[host setup](.setup/README.md) for installation and validation instructions.

## License

EconYoloBox is released under the [MIT License](LICENSE).
