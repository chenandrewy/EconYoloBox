# EconYoloBox

EconYoloBox is an ergonomic, AI-forward environment for economics research. It
was built by obsessively improving my research workflow (instead of doing
actual research work).

— Andrew Chen

Key features:

1. **YOLO agents by default, with a toggle for "normie" mode**

   - **YOLO mode:** open the container with `bbcode` (or `bbe` for a
     terminal); it is the default. Then run Claude Code and Codex in yolo mode
     using the convenient aliases `cchat-yolo` and `gptchat-yolo`. Cook!
   - **Normie mode:** open it with `bbcode --normie` (or `bbe --normie`)
     instead. Then you can work with the sandbox like a normie to do stuff
     that requires internet access and (probably) babysitting of the agents
     (e.g. install R packages, test new software, search arbitrary websites).
     The VS Code window title starts with `normie:`, the prompt says `normie`,
     and every new shell warns what is loosened, until you switch back.
   - See [isolation and approval limits](docs/features.md#1-safe-yolo-agents).

2. **Ergonomic container and AI access**

   - Enter the container at a project-specific path with one command.
   - Edit agent guidance in [SANDBOX-CLAUDE.md](SANDBOX-CLAUDE.md) and keep
     settings as code, with optional Dropbox synchronization.
   - Synchronize AI chat sessions across machines via Dropbox.

3. **Economics-research AI tooling**

   - Use a container image designed for fast R and Python package installation.
   - Chat with AI about math with equations rendered by a custom VS Code
     extension.
   - Search the literature with a custom OpenAlex citation-lookup tool.
   - Convert PDFs to Markdown with high fidelity using a tool built on Mistral
     OCR (h/t Don Bowen).

More concretely, it's a shared sandbox built around the following folders:

- `credentials/`: credential injection mechanism
- `.devcontainer/`: sandbox implementation
- `agents/`: shared agent settings and skills
- `host/`: ergonomic container access
- `setup/`: package and CLI provisioning
- `tools/`: custom AI tooling

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
   When VS Code asks which configuration, pick the plain one (YOLO mode); the
   one named `(normie)` is normie mode.

   Wait for the first build to finish. It also installs the base R, Python
   and TeX Live stacks and, at first start, the Claude Code and Codex CLIs, so
   expect it to take a while longer than later rebuilds. VS Code reloads with
   `Dev Container` shown in the lower-left corner when it is ready.

   The container starts in YOLO mode: firewall on, allowing only the network
   allowlist, with read-only package volumes and builtin seccomp. For open
   internet access and package installs, use normie mode: the `(normie)`
   configuration, or `bbcode --normie` with the
   [host launcher](#optional-host-command-workflow).
   Normie mode also disables Docker's outer syscall filter for every
   container process; see
   [sandbox validation and limits](.devcontainer/README.md#codex-sandbox-modes-and-launchers).

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

6. **Start an AI agent from the project directory.** The first launch may ask
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

### Switching modes

Each mode is its own container, built from its own configuration:
`.devcontainer/devcontainer.json` for YOLO mode (firewalled internet,
read-only package volumes, `builtin` seccomp) and
`.devcontainer/normie/devcontainer.json` for normie mode (open internet,
writable package volumes, `unconfined` seccomp), which is for supervised work.
The launcher's flag picks which one to open:

```zsh
bbcode             # the YOLO container, in VS Code (bbe: in a terminal)
bbcode --normie    # the normie container
bbox --status      # both containers and their modes, changing nothing
bbox --stop --normie   # stop the normie container
```

Both can run at once, and neither replaces the other, so switching is instant
and ends nothing. They share one set of volumes: logins, the AI CLIs, shell
history and the packages normie mode installs. A normie container keeps
running, firewall open, until it is stopped (or, possibly, until its last VS
Code window closes), so every YOLO bring-up mentions a running one.

The mode stays in view: in the normie container the VS Code window title
starts with `normie:`, the shell prompt and Claude's status line carry a
`normie` tag, and every new shell prints a warning banner spelling out the
security posture.
Startup prints `YOLO mode`, `Normie mode`, or `Custom posture` for a container
made before the per-mode configurations.

The `cchat-yolo`, `gptchat-yolo`, and `gptmini-yolo` launchers skip permission
checks and refuse to start unless the firewall is enabled and PID 1 has a
filtered seccomp mode, so they run only in YOLO mode. In normie mode, keep
agents in ordinary approval modes; neither a firewall nor automatic review
guarantees the safety of mounted files or accessible credentials.

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
python3 credentials/setup.py
```

Press Enter to skip any service you do not use. The container receives the
credentials as environment variables when it is created, so a container that
already exists needs recreating to see new ones: `bbox --rebuild`, which
recreates both modes' containers.

### Update the AI CLIs

The first start installs the Claude Code and Codex CLIs into a persistent
volume, so a rebuild does not undo an update. They do not update themselves;
to update both, in any mode:

```bash
bash /sandbox/setup/install-base.sh cli
```

### Add to the package stacks

R, Python and TeX Live live in shared volumes that every project mounts,
read-only by default. The first build fills them with a lean base. For the rest
of the usual stack, or any other package, switch to normie mode with
`bbcode --normie` on the host. Then, in the container:

```bash
bash setup/install-optional.sh      # the rest of the usual stack
```

or `install.packages()`, `pip install` or `tlmgr install`. Switch back to YOLO
mode (`bbcode`, then `bbox --stop --normie`) and run
`bash .devcontainer/tests/test-packages.sh`. See [setup](setup/README.md) and
the [devcontainer README](.devcontainer/README.md#working-modes) for the
details.

## Optional host command workflow

The general-purpose `bbox` launcher brings up the requested mode's container,
verifies it, and can open a shell or VS Code at a project path. Ensure the
VS Code `code` CLI is installed if using `--code`. To install the launcher, run the
following from the checkout root in a host zsh terminal:

```zsh
npm install -g @devcontainers/cli
bash host/setup.sh
exec zsh
type bbox
```

Run `bbox` to bring the container up, `bbcode My-Project` (`bbox --code`) to
open a project in VS Code, or `bbe My-Project` (`bbox --shell`) to enter it in
a terminal. Each takes `--normie` (or an explicit `--yolo`), and
`bbox --rebuild` recreates both modes' containers after a Dockerfile or
config change, then opens the chosen one. VS Code's own **Rebuild Container**
rebuilds only the window's mode, from its configuration.

Optional: the container picks up the Mac's timezone automatically. To force a
different one, export it on the host before the container starts.

```bash
export TZ=America/Chicago
```

## Devcontainer storage

Budget the container image (which carries a copy of the base stacks, about
1.5GB, to seed the volumes) plus about **5.7GB of volumes** for the first
sandbox checkout: 4.7GB of shared R, Python and TeX volumes, and 1GB of
per-checkout volumes (AI CLIs and their config). Each additional checkout adds
about 1GB, since the image and the package volumes are shared.

Docker's default 20GB BuildKit garbage-collection budget is adequate. If you
hit repeated slow rebuilds, raising it to 35GB gives headroom. See
[Devcontainer storage needs](docs/storage-needs.md) for the settings and for how
to confirm that eviction is the actual problem.

## TeX Live setup

The devcontainer uses a shared, pdfLaTeX-only TeX Live volume, read-only by
default, which the first build fills. See [setup](setup/README.md) for adding
packages and for validation.

## License

EconYoloBox is released under the [MIT License](LICENSE).
