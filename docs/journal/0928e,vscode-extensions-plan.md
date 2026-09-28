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
