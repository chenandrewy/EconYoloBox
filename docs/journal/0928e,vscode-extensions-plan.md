# 0928b — VS Code extensions: no marketplace in YOLO, and a volume

2026-09-28, branch `security/tighten-firewall`. Plan only; nothing implemented.

## Why

**Firewall.** The YOLO allowlist carries `marketplace.visualstudio.com`,
`open-vsx.org`, `ms-vscode.gallery.vsassets.io` and 14 per-publisher
`*.gallerycdn.vsassets.io` names. All 14 CNAME onto one Akamai edge
([0720c]), so allowing them allows whatever else that edge serves — the same
problem as Google's ranges, on a CDN. And they barely work: they are pinned
once at container start, Akamai rotates, and the comment in `init-firewall.sh`
saying each new publisher needs its own entry has been known wrong since
[0720c].

**Speed.** `~/.vscode-server` is not a volume, so recreating the container or
updating VS Code reinstalls every extension ([0922a]). Today's container,
created at 08:50, did exactly that.

## What today's log shows

`~/.vscode-server/data/logs/*/remoteagent.log`, 2026-09-28: the container's own
downloads of `ms-python.debugpy` and `ms-python.vscode-python-envs` failed with
`EHOSTUNREACH` (they come from `ms-python.gallery.vsassets.io`, which is not
listed). VS Code then installed them, along with `ms-python.python` and
`ms-python.vscode-pylance`, with `downloadExtensionsLocally:true`: the host
downloaded each VSIX and pushed it into the container. So the container-side
path is already unreliable, and the host relay already carries real installs.

That makes installing extensions only in normie mode unnecessary. YOLO can keep
installing its own, through the host.

## Design

1. **Download extensions on the host, always.** Set
   `remote.downloadExtensionsLocally` to `true`, so the container never tries
   the marketplace. Open question: whether it takes effect from
   `customizations.vscode.settings` in `devcontainer.json` or must be a host
   user setting; test both.
2. **Remove the marketplace names from the YOLO allowlist**: the 14
   `gallerycdn` names, `ms-vscode.gallery.vsassets.io`,
   `marketplace.visualstudio.com` and `open-vsx.org`. Blocked requests are
   REJECTed, so leftover update checks fail instantly ([0720e]).
3. **Persist `~/.vscode-server/extensions` in a volume.** Only that folder: the
   server binary under `bin/` is keyed by VS Code version, and the Dev
   Containers extension brings it in.
   - **One volume per mode**, not shared. With the relay each mode can install
     for itself, and sharing would let two running containers write
     `extensions.json` at once.
   - Named like the other volumes after [0927a], by basename, with a mode
     suffix: `${localWorkspaceFolderBasename}-vscode-extensions` and
     `${localWorkspaceFolderBasename}-vscode-extensions-normie`.
   - The Dockerfile must create `/home/node/.vscode-server/extensions` owned by
     `node`, or the new volume comes up root-owned.

## Open questions

- **Where the relay setting has to live** (above).
- **How the VS Code server reaches the container.** `update.code.visualstudio.com`
  is not allowlisted, yet servers install, so the download presumably happens
  on the host. Confirm before relying on it.
- **Whether anything else needs the marketplace names**, e.g. extension update
  checks or the Extensions view's search. With the relay these should also run
  on the host; check the log after a day of use.
- **An older extension in a volume after a VS Code update.** Extensions
  normally update themselves; check that a VS Code bump does not leave an
  incompatible version stuck in the volume.

## Files

- `.devcontainer/init-firewall.sh`: remove the 17 names and the wrong comment.
- `.devcontainer/devcontainer.json` and `.devcontainer/normie/devcontainer.json`:
  the mount, and the relay setting if it works there.
- `.devcontainer/Dockerfile`: create the extensions folder owned by `node`.
- `.devcontainer/test-firewall.sh`: probe that a `gallerycdn` host is rejected.
- Docs: `SANDBOX-CLAUDE.md` (the allowlist's packages bullet),
  `docs/features.md`, `.devcontainer/README.md` (the list of volumes).

## Is this a big change?

Medium. The edits are small, but it changes how every extension gets installed,
in both modes, and it rests on VS Code behavior that has so far only been seen
as a fallback. The work is mostly in the verification below.

## Verification

In a YOLO container rebuilt from the branch:

1. `test-firewall.sh` passes, including the new probe.
2. Every extension in `devcontainer.json` is installed, and the log shows local
   downloads and no container-side marketplace attempts.
3. Install a new extension from the UI; it arrives by the relay.
4. Restart, then recreate: no reinstall pass in the log.
5. Repeat 2–4 in normie mode, with both containers running.

[0720c]: archive/0720c,extension-install-blocked.md
[0720e]: archive/0720e,fail-fast-extension-diagnosis.md
[0922a]: 0922a,vscode-server-reinstall-slow-launch.md
[0927a]: 0927a,two-container-modes-plan.md

## 2026-09-29 addendum — risks of the normie-only installation path

The design above used separate writable extension volumes and VS Code's host
relay. A fresh YOLO attach disproved the host-only assumption: VS Code Server
first requested `marketplace.visualstudio.com` from inside the container, then
relayed installs after the firewall rejected it. Only 12 of the 13 requested
extensions landed; `ms-python.python` was missing. The current implementation
instead gives both modes one extension volume, writable in normie and read-only
in YOLO, with no automatic extension install list. Installation is an explicit
`code --install-extension` command run inside normie.
Validation later showed that `tomoki1207.pdf` is UI-only and already installed
on the host, so the normie script installs 12 workspace extensions; the PDF
viewer stays in host VS Code.

- **Manual bootstrap.** Every fresh checkout or new extension volume needs a
  normie VS Code attach, the install command, and a complete registry check
  before YOLO can rely on its extensions. The command requires VS Code's remote
  `code` CLI, so a shell-only normie session is insufficient.
- **Broader install environment.** Normie has open internet, writable package
  volumes and unconfined Docker seccomp. The selected extensions are installed
  there and later execute in YOLO, where they can access the workspace and the
  container's available credentials and network allowlist.
- **Shared live code.** Normie can change extension files while YOLO is using
  them. Stop or detach YOLO before updating extensions, then reopen it; the
  read-only YOLO mount prevents YOLO writes but does not freeze normie writes.
- **Read-only attach is unverified.** The mount permissions have been checked,
  but VS Code has not yet attached to YOLO with a fully populated read-only
  extension volume. It may try to write registry or metadata even with
  automatic updates disabled; that needs a real attach test.
- **Manual updates and version drift.** Automatic updates are disabled. The
  install script lists IDs, not exact versions, so separate fresh installs may
  resolve different versions; an existing volume may keep an extension that
  becomes incompatible after a VS Code update. Run the installer in normie and
  verify the result after updates.
- **Single-path behavior still needs a log check.** Neither config requests
  automatic installs or host relay. Verify during the normie CLI install that
  extensions are downloaded and installed in the container, with no host relay
  or second install path, before calling the new pipeline validated.

## 2026-09-29 addendum — validation and first-user test

Tests completed on this host after rebuilding both modes with the new shared
extension volume:

- Normie mounted the volume writable and YOLO mounted that same volume
  read-only. The normie `code --install-extension` run installed the workspace
  extensions, and `install-vscode-extensions.sh --verify` found all 12 in both
  modes. The YOLO `ubuntu` user could not write the extension directory.
- `tomoki1207.pdf` refused a container install because it is UI-only. It was
  removed from the container list; it must be installed in host VS Code.
- The normie VS Code Server log showed the CLI installs, with no host relay or
  `downloadExtensionsLocally` activity. The YOLO firewall test passed its
  marketplace, Open VSX and extension CDN probes. A populated read-only YOLO
  VS Code window opened successfully in the user's subsequent check.
- The config twin tests, shell syntax checks and `git diff --check` passed.

These checks use an existing VS Code profile, Docker installation and cached
images. They do not establish the experience of someone starting without VS
Code extensions or a prior container volume. Test that separately:

1. Reset this Mac's VS Code data and this checkout's extension volume. Quit
   **all** VS Code windows with Command-Q first. In Finder, use **Go > Go to
   Folder** for each of these paths and move the folder to Trash:

   - `~/Library/Application Support/Code` (settings, profiles and state)
   - `~/.vscode` (locally installed extensions)
   - `~/.vscode-shared` (other shared VS Code user data, if present)

   This is [VS Code's documented clean-uninstall data set on
   macOS](https://code.visualstudio.com/docs/setup/uninstall); the app remains
   installed. Moving to Trash has the same fresh-start effect as
   deleting the folders but leaves a way to recover settings and extensions.
   Do not sign into Settings Sync during the test, or it may restore them.
   The Docker extension volume is separate and is **not** reset by deleting
   host VS Code data. In a **host macOS Terminal**, `cd` to the root of the
   existing EconYoloBox checkout. Check the exact volume name and every
   container using it:

   ```sh
   # Run: in a host Terminal, from the checkout root, after quitting VS Code.
   # Inputs: the checkout folder name and Docker's container metadata.
   # Outputs: the extension volume name and its attached containers.
   extension_volume="$(basename "$PWD")-vscode-extensions-managed"
   docker ps -a --filter "volume=$extension_volume" \
     --format '{{.ID}} {{.Names}} {{.Status}}'
   ```

   For the current checkout, the volume is
   `1-SANDBOX-vscode-extensions-managed`; the listing should show only its
   YOLO and normie containers. If other containers appear, investigate before
   removing anything. [Docker cannot remove a volume while any container
   references it](https://docs.docker.com/get-started/docker-concepts/running-containers/persisting-container-data/),
   even a stopped one. After confirming the list and with VS Code closed, run
   this in the same Terminal:

   ```sh
   # Run: in the same host Terminal after confirming the list above.
   # Inputs: extension_volume and its attached YOLO/normie containers.
   # Outputs: removes those containers and the named extension volume.
   docker ps -aq --filter "volume=$extension_volume" | while IFS= read -r id; do
     docker rm -f "$id" || break
   done
   docker volume rm "$extension_volume"
   ```

   This removes the two containers and only their named extension volume;
   their other named volumes, Docker images and global package volumes remain.
   Reopen the existing checkout in VS Code for step 2. Choosing `(normie)`
   creates a new, empty extension volume with the same name.

2. Follow the main README exactly. Install Dev Containers in the reset host VS
   Code, and install `tomoki1207.pdf` locally if the PDF viewer is wanted.
   Choose `(normie)` on first Reopen in Container, and wait for the first build
   and VS Code Server attach to finish.
3. Run `bash .devcontainer/setup/install-vscode-extensions.sh` in the normie
   integrated terminal. Require an exit status of zero and `--verify` to find
   all 12 extensions. Check the server log for installs initiated by the remote
   CLI, with no automatic install pass or host relay. Confirm the PDF viewer
   appears as a local extension, not in the remote volume.
4. Reopen the plain YOLO configuration. Require `--verify` to pass, the volume
   to be mounted read-only, and the marketplace firewall probes to pass. Check
   that the VS Code Server log shows no install/update attempt and that the
   editor can activate the workspace extensions. Rebuild or recreate YOLO and
   check that extensions remain available without reinstalling.
5. For a truly cold first-install test, repeat on a clean macOS VM or spare Mac
   with fresh Docker data. The reset-VS-Code test still shares the host's
   Docker images, package volumes and other installed prerequisites.

The reset-VS-Code and clean-machine tests are proposed; they have not been
run. They require reinstalling host extensions after removing local VS Code
data and, for the last step, provisioning a separate machine or VM.
