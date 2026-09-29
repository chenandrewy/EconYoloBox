# EconYoloBox

EconYoloBox is an ergonomic, AI-forward environment for economics research. It
was built by obsessively improving my research workflow (instead of doing
actual research work).

— Andrew Chen

Key features:

1. **Sandboxed YOLO mode, with an easy "Normie" mode switch**

   - **YOLO mode** is the default. It has a firewall and filtered system calls,
     so Claude Code and Codex can run unsupervised and efficiently. Don't waste
     time or tokens approving commands. *Cook!*
     - Is the *cooking* too spicy? Adjust `.devcontainer/init-firewall.sh`
       to your palate. Turn off all internet, except for the model providers, if
       you prefer mild.
   - **Normie mode** opens a second container with open internet and
     unfiltered system calls. Use it for work blocked in YOLO mode (searching
     arbitrary websites, installing packages and VS Code extensions, trying
     random software). Like normies, use Claude "auto mode" and Codex
     `auto_review` for safety.
   - **The two modes share package volumes.** R, Python, TeX Live and the
     VS Code extensions each live in their own volume. Normie mode can write to
     them, but YOLO mode mounts them read-only. Any packages you install in
     normie mode are available in YOLO mode, but YOLO agents can't install R,
     Python or TeX packages (and thus can't install any malicious packages).
   - See [switching modes](#switching-modes) and
     [isolation and approval limits](docs/features.md#1-safe-yolo-agents).

2. **Ergonomic container and AI access**

   - Enter the container at a project path with one command: `ybcode My-Project`
     opens it in VS Code and `ybe My-Project` in a terminal. Add `--normie` to
     either for normie mode. These need the
     [host launcher](#optional-host-command-workflow).
   - Start unsupervised agents in YOLO mode with `cchat-yolo` (Claude Code) or
     `gptchat-yolo` (Codex).
   - Edit agent guidance in
     [agents/YOLOBOX-CLAUDE.md](agents/YOLOBOX-CLAUDE.md) and keep settings as
     code, with optional Dropbox synchronization.
   - Synchronize AI chat sessions across machines via Dropbox.

3. **Economics-research AI tooling**

   - Use a container image designed for fast R and Python package installation.
   - Chat with AI about math with equations rendered by a custom VS Code
     extension.
   - Search the literature with a custom OpenAlex citation-lookup tool.
   - Convert PDFs to Markdown with high fidelity using a tool built on Mistral
     OCR (h/t Don Bowen).

More concretely, the whole checkout is bind-mounted at `/yolobox` in the
container. The yolobox itself is these tracked folders:

- `.devcontainer/`: container definitions, runtime support, host launchers,
  provisioning, and tests
- `agents/`: agent guidance, settings and skills; `agents/managed/` is the
  policy baked into the image
- `credentials/`: user-maintained credential mapping and host credential
  management
- `docs/`: design notes and the feature tour
- `tools/`: custom research tooling

Put your projects in `workshop/` (active) and `hangar/` (finished). Both are
ignored by the outer repo, so each project is its own Git repository.

See [Yolobox Features](docs/features.md) for a detailed tour.

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

2. **Install the host VS Code extensions.** Open VS Code and select the
   Extensions icon in the left sidebar. Install `Dev Containers` by Microsoft.
   If you use the PDF viewer, also install `PDF` by tomoki1207 here; it runs in
   host VS Code, not in the container.

3. **Clone EconYoloBox in VS Code.** Open the Command Palette with
   **Shift–Command–P**, select **Git: Clone**, and enter:

   ```text
   https://github.com/chenandrewy/EconYoloBox.git
   ```

   Choose a destination folder, then click **Open** when VS Code
   asks whether to open the cloned repository.

4. **Build and open the container.** In the cloned repository's VS Code window,
   open the Command Palette and select **Dev Containers: Reopen in Container**.
   When VS Code asks which configuration for a fresh checkout, pick the one
   named `(normie)` to install extensions first.

   Wait for the first build to finish. It also installs the base R, Python
   and TeX Live stacks and, at first start, the Claude Code and Codex CLIs, so
   expect it to take a while longer than later rebuilds. VS Code reloads with
   `Dev Container` shown in the lower-left corner when it is ready. In its
   integrated terminal, run `bash .devcontainer/setup/install-vscode-extensions.sh`
   and check that all 12 workspace extensions pass. Then reopen the plain
   configuration for everyday YOLO mode.

   The YOLO container starts with its firewall on, allowing only the network
   allowlist, with read-only package volumes and builtin seccomp. For open
   internet access and package installs, use normie mode: the `(normie)`
   configuration, or `ybcode --normie` with the
   [host launcher](#optional-host-command-workflow).
   The default allowlist is one point on the risk/return tradeoff. 
   Adjust the internet access in `.devcontainer/init-firewall.sh` to match
   your own preferences.
   Normie mode also disables Docker's outer syscall filter for every
   container process; see
   [sandbox validation and limits](.devcontainer/README.md#codex-sandbox-modes-and-launchers).

5. **Create or clone a project.** Select **Terminal → New Terminal** in VS Code.
   The yolobox repository is mounted at `/yolobox`; all user content goes
   under `/yolobox/workshop/`, which `.gitignore` excludes wholesale, so the
   outer EconYoloBox repository never sees your projects whatever they are
   named. Each project must therefore be its own Git repository. Projects that
   are finished or retired move to `/yolobox/hangar/`, which is ignored the same
   way; `workshop/` holds only active work.

   For a new project:

   ```bash
   mkdir -p /yolobox/workshop/My-Project
   git -C /yolobox/workshop/My-Project init
   ```

   For an existing project, clone its repository instead:

   ```bash
   cd /yolobox/workshop
   git clone https://github.com/your-name/your-project.git My-Project
   ```

6. **Start an AI agent from the project directory.** The first launch may ask
   you to authenticate. Start Claude with auto mode selected:

   ```bash
   cd /yolobox/workshop/My-Project
   claude --permission-mode auto
   ```

   This uses Claude's automatic permission checks where
   [auto mode is available](https://code.claude.com/docs/en/permissions#permission-modes).
   If unavailable for your account or model, use `claude` with manual approvals.

   Or start Codex with:

   ```bash
   cd /yolobox/workshop/My-Project
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
ybcode             # the YOLO container, in VS Code (ybe: in a terminal)
ybcode --normie    # the normie container
ybox --status      # both containers and their modes, changing nothing
ybox --stop --normie   # stop the normie container
```

Both can run at once, and neither replaces the other, so switching is instant
and ends nothing. They share volumes for logins, the AI CLIs, shell history
and the packages and VS Code extensions normie mode installs. YOLO mounts
those extensions read-only. A normie container keeps
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
already exists needs recreating to see new ones: `ybox --rebuild`, which
recreates both modes' containers.

### Update the AI CLIs

The first start installs the Claude Code and Codex CLIs into a persistent
volume, so a rebuild does not undo an update. They do not update themselves;
to update both, in any mode:

```bash
bash /yolobox/.devcontainer/setup/install-base.sh cli
```

### Add to the package stacks

R, Python and TeX Live live in shared volumes that every project mounts,
read-only by default. The first build fills them with a lean base. For the rest
of the usual stack, or any other package, switch to normie mode with
`ybcode --normie` on the host. Then, in the container:

```bash
bash .devcontainer/setup/install-optional.sh      # the rest of the usual stack
```

or `install.packages()`, `pip install` or `tlmgr install`. Switch back to YOLO
mode (`ybcode`, then `ybox --stop --normie`) and run
`bash .devcontainer/setup/tests/test-packages.sh`. See [setup](.devcontainer/setup/README.md) and
the [devcontainer README](.devcontainer/README.md#working-modes) for the
details.

## Optional host command workflow

The general-purpose `ybox` launcher brings up the requested mode's container,
verifies it, and can open a shell or VS Code at a project path. Ensure the
VS Code `code` CLI is installed if using `--code`. To install the launcher, run the
following from the checkout root in a host zsh terminal:

```zsh
npm install -g @devcontainers/cli
bash .devcontainer/host/setup.sh
exec zsh
type ybox
```

Run `ybox` to bring the container up, `ybcode My-Project` (`ybox --code`) to
open a project in VS Code, or `ybe My-Project` (`ybox --shell`) to enter it in
a terminal. Each takes `--normie` (or an explicit `--yolo`), and
`ybox --rebuild` recreates both modes' containers after a Dockerfile or
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
yolobox checkout: 4.7GB of shared R, Python and TeX volumes, and 1GB of
per-checkout volumes (AI CLIs and their config). Each additional checkout adds
about 1GB, since the image and the package volumes are shared.

Docker's default 20GB BuildKit garbage-collection budget is adequate. If you
hit repeated slow rebuilds, raising it to 35GB gives headroom. See
[Devcontainer storage needs](docs/storage-needs.md) for the settings and for how
to confirm that eviction is the actual problem.

## TeX Live setup

The devcontainer uses a shared, pdfLaTeX-only TeX Live volume, read-only by
default, which the first build fills. See [setup](.devcontainer/setup/README.md) for adding
packages and for validation.

## License

EconYoloBox is released under the [MIT License](LICENSE).
