# EconYoloBox

EconYoloBox is an ergonomic, AI-forward environment for economics research. It
was built by obsessively improving my research workflow (instead of doing
actual research work).

— Andrew Chen

Key features:

1. **Safe YOLO agents**

   - Don't waste time approving agent actions.
   - Rely on a sandbox design that follows
     [`anthropics/claude-code`](https://github.com/anthropics/claude-code)
     security practices.

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

   Choose your home folder as the destination, then click **Open** when VS Code
   asks whether to open the cloned repository.

4. **Build and open the container.** Open the Command Palette with
   **Shift–Command–P**, select **Dev Containers: Reopen in Container**, and wait
   for the first build to finish. VS Code reloads with `Dev Container` shown in
   the lower-left corner when it is ready.

5. **Create or clone a project.** Select **Terminal → New Terminal** in VS Code.
   Project folders are listed in `.gitignore` so the outer EconYoloBox
   repository deliberately ignores them. Each project must therefore be its own
   Git repository; add any differently named project folder to `.gitignore`
   too.

   For a new project:

   ```bash
   cd /workspace
   mkdir -p My-Project
   git -C My-Project init
   ```

   For an existing project, clone its repository instead:

   ```bash
   cd /workspace
   git clone https://github.com/your-name/your-project.git My-Project
   ```

6. **Install the AI CLIs.** They are not baked into the image — they live in a
   persistent volume so that updating them is not undone by the next rebuild.
   A newly created npm-global volume therefore starts without them:

   ```bash
   /workspace/.devcontainer/install-packages.sh cli
   ```

   This takes a few seconds and installs the current Claude Code and Codex
   releases. It is needed once when the volume is first created, not per session
   or ordinary container rebuild; an interactive shell prints a reminder while
   either CLI is missing. Re-run the same command to update either npm-managed
   CLI. A new volume is created only when the old one is removed or its
   distro/Node version token changes in `devcontainer.json`.

7. **Start an AI agent from the project directory.** The first launch may ask
   you to authenticate. Start Claude with:

   ```bash
   cd /workspace/My-Project
   cchat-yolo
   ```

   Or start Codex with:

   ```bash
   cd /workspace/My-Project
   gptchat-yolo
   ```

   Both commands intentionally run their agent without permission prompts; the
   container and its firewall provide the safety boundary.

## Recommended additions

The minimal setup works without these steps. Add the pieces needed for your
workflow after the container is running.

### Give the Mac a short name

A short computer name keeps Claude session names readable: `MacBook25` is
clearer than `Andrews-MacBook-Pro`. Set it under **System Settings → General →
About → Name**. Reopen the container afterward so it picks up the new name.

### Save credentials for research tools

These credentials support WRDS, Mistral, OpenRouter, and OpenAlex tools; they
are not needed to authenticate Claude or Codex. In the Mac's Terminal, run:

```bash
cd "$HOME/EconYoloBox"
python3 .credentials/setup.py
python3 .devcontainer/inject-credentials.py
```

Press Enter to skip any service you do not use. The final command refreshes the
credential file mounted in an already-running container; skip it if you have
not built the container yet.

### Install the analysis stacks

The base container omits the optional R and Python packages. Install both
stacks—or only the one you need—from a VS Code terminal inside the container:

```bash
cd /workspace
.devcontainer/install-packages.sh          # stacks and CLIs, a few minutes
.devcontainer/install-packages.sh python   # Python only
.devcontainer/install-packages.sh r        # R only
.devcontainer/install-packages.sh cli      # AI CLIs only (step 6 above)
.devcontainer/install-packages.sh --force  # reinstall even if present
```

## Optional command-line workflow

The VS Code workflow above is sufficient. To start and enter EconYoloBox from
the Mac's Terminal instead, install the `devcontainer` CLI and the VS Code
`code` CLI, then load the included shell helpers:

```zsh
npm install -g @devcontainers/cli
echo 'source "$HOME/EconYoloBox/.host/devcontainer.zsh"' >> ~/.zshrc
exec zsh
type dcu dce dccode
```

Run `dcu` from the EconYoloBox root to start the container. Then use
`dccode My-Project` to open a project in VS Code or `dce My-Project` to enter it
in a terminal.

Optional: the container picks up the Mac's timezone automatically. To force a
different one, export it on the host before the container starts.

```bash
export TZ=America/Chicago
```

## Devcontainer storage

Budget roughly **5.5GB for the first checkout**, plus about 2GB of persistent
volumes for each additional checkout. The container image is shared.

Docker's default 20GB BuildKit garbage-collection budget is adequate. If you
hit repeated slow rebuilds, raising it to 35GB gives headroom. See
[Devcontainer storage needs](docs/storage-needs.md) for the settings and for how
to confirm that eviction is the actual problem.

## License

EconYoloBox is released under the [MIT License](LICENSE).
