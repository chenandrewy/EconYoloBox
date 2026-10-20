# Plan: separate Git and GitHub write access by container mode

Date: 2026-10-02
Status: proposed; no container or authentication changes made.

## Objective

The user wants Git pushes and GitHub issue writes blocked in YOLO mode and
allowed in normie mode. This plan interprets issue writes as creation, comments,
edits, closing, and similar mutations; issue reads remain allowed. Confirm that
interpretation if the intended restriction is on all `gh issue` commands.

The user clarified that YOLO agents should work and make commits in local
clones; the repositories are often public. YOLO therefore needs no GitHub
credentials, including read tokens. Local work also functions in an existing
clone of a private repository without remote authentication.

| Operation | YOLO | Normie |
| --- | --- | --- |
| Local commits, branches, diffs | Allowed | Allowed |
| Fetch/clone public repositories over HTTPS | Available without authentication | Allowed |
| Fetch/clone private repositories | Use normie or the host | Allowed with authentication |
| Read issues | Public unauthenticated access only; no authenticated `gh` setup | Allowed with authentication |
| Push branches or tags to GitHub | Blocked through absence of GitHub credentials | Allowed with authentication |
| Create, comment on, or modify issues | Blocked through absence of GitHub credentials | Allowed with authentication |

Normie capability does not itself authorize an agent to publish: the existing
requirement for explicit user authorization still applies.

## Current setup

The two configurations, `.devcontainer/devcontainer.json` and
`.devcontainer/normie/devcontainer.json`, create separate containers. They share
the workspace, including repository `.git/config` files, and several volumes.
Their current mode differences concern the firewall, seccomp, package and
extension mount permissions, and mode identification. GitHub authentication is
not separated by mode.

- `.devcontainer/init-firewall.sh` explicitly allows GitHub's web, API, and Git
  IP ranges. This IP firewall cannot distinguish fetching from pushing or
  reading an issue from writing one.
- VS Code's Dev Containers extension forwards host HTTPS Git credentials.
  `.devcontainer/README.md` documents that forwarding as deliberate. Neither
  mode configuration disables it.
- VS Code can also forward the host SSH agent. HTTPS credential-helper settings
  alone do not cover that separate authentication route.
- The common Dockerfile installs Git, the SSH client, and `gh`. There is no
  mode-specific command restriction.
- Both configurations invoke the same credential injector and consume
  `/tmp/devcontainer-credentials.env` on the host. The current
  `credentials/credentials-map.json` contains WRDS, Mistral, and OpenRouter
  entries, with no GitHub token.
- No dedicated persistent `gh` authentication volume is configured.

The current restriction on pushing is agent guidance, not a technical block.

### Observations from the running session

Read-only inspection on 2026-10-02 found:

- This session is in the normie container. `posture.sh` reported
  `normie internet=open package_access=readonly seccomp=unconfined`; the command
  sandbox can make package mounts appear read-only even in normie mode.
- This repository's `origin` uses
  `https://github.com/chenandrewy/EconYoloBox.git` for both fetch and push, with
  no separate push URL.
- VS Code's Git credential helper is configured in both
  `/usr/local/etc/gitconfig` and `/home/ubuntu/.gitconfig`.
- `SSH_AUTH_SOCK` and `VSCODE_GIT_IPC_HANDLE` are set.
- `/usr/bin/gh` exists. `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN`,
  `GITHUB_ENTERPRISE_TOKEN`, and `GH_CONFIG_DIR` are unset.
- The usual `~/.config/gh/hosts.yml` and `~/.git-credentials` files are absent.

These observations establish configured authentication paths, not that any
forwarded credential works or has write permission. No authentication, push,
or GitHub mutation was attempted. Git credential forwarding also does not
automatically authenticate `gh`, which normally uses an environment token or
its own saved login.

## Proposed design

### 1. Remove host GitHub credential access from YOLO

Disable host HTTPS credential forwarding and SSH agent forwarding for YOLO.
Also account for editor authentication and askpass paths that could expose a
host credential independently of the configured Git helper.

The README currently identifies the host VS Code setting
`dev.containers.gitCredentialHelperConfigLocation: "none"`. Verify the installed
extension's behavior and setting scope before choosing the implementation.
Do not assume that putting a host setting in `customizations.vscode.settings`
will control how the host attaches, or that this setting disables SSH forwarding.

Clearing environment variables or deleting a helper entry is not sufficient if
the underlying forwarding socket or service remains accessible. The design must
prevent access to the forwarding capability and survive editor reconnects.

Prefer a reliable mode-specific host/editor configuration. If VS Code cannot
reliably support that split, consider disabling automatic forwarding for both
modes and providing explicit GitHub credentials only to normie. Settle
this detail before claiming that YOLO write access is blocked.

### 2. Keep YOLO local work independent of GitHub authentication

Do not supply any GitHub token, saved login, SSH key, or forwarded authentication
capability to YOLO. There is no need for a separate read token.

Editing files, staging changes, creating branches, and committing operate on
the local clone. A commit records the configured author name and email; those
values are metadata, not GitHub credentials. Preserve that identity configuration
without importing host credential helpers. Local commits must also work without
a forwarded signing agent; account for any inherited commit-signing settings
when implementing the separation.

Public repositories can be cloned or fetched over HTTPS without authentication.
Their public visibility permits reading, not anonymous pushing. Existing private
clones can be edited and committed in YOLO too; fetching private updates or
publishing changes happens in normie or on the host.

The normal workflow is: prepare or update the clone in normie/the host when
needed, let YOLO edit and commit locally, then review and push from normie/the
host. The shared workspace makes the same local commits available in both modes;
avoid concurrent Git mutations in the same working tree.

Authenticated `gh` commands are outside YOLO's setup. Public issue information
can still be read through unauthenticated web/API access. This plan does not
add credentials merely to make `gh` read commands work.

### 3. Keep normie write credentials exclusive to normie

Provide normie with an explicit Git and `gh` authentication arrangement that
supports pushes and issue writes. Host Git forwarding can remain if it can be
isolated reliably by mode; `gh` still needs its own usable authentication source.

Keep any write token or saved-login storage outside the shared workspace and
outside volumes mounted into YOLO. A normie-only `gh` volume is one possible
persistence mechanism; mode-specific injection from the host credential store
is another. Choose one documented source of truth for the credential.

If extending the credential injector, select credentials by mode and use distinct
host output files for YOLO and normie. Both containers can start concurrently;
reusing `/tmp/devcontainer-credentials.env` for different credential sets could
send the wrong set to a container. Exclude GitHub credentials from YOLO's
injected environment entirely.

### 4. Add checks and update documentation

Check the effective authentication exposure after VS Code attaches and after
reconnection, as well as at container startup. Report the GitHub access posture
alongside the existing mode information. A startup-only check cannot establish
what the editor subsequently forwards.

Update `.devcontainer/tests/test_config_twins.py` to recognize the intended
authentication differences between modes. Add focused tests for mode selection,
credential-file separation, and absence of GitHub credential injection into YOLO.
Use dummy credentials in automated tests.

Update `.devcontainer/README.md`, `docs/features.md`, and agent guidance to explain
the enforced access split and how normie authentication is established.

## Remote configuration and command guards

Keep shared repository remote URLs unchanged. Setting `origin.pushurl` to a
disabled destination in `.git/config` would also affect normie and the host.
An explicit push URL could bypass that setting anyway.

Shell wrappers or pre-push hooks can provide a clear message directing the user
to normie, but they are bypassable and cannot establish the access boundary.
Removing `gh` would likewise leave direct API calls possible with any available
write token.

## Validation and rollout

1. Resolve the host/editor forwarding controls and verify how they behave on
   initial attachment and reconnection for both modes.
2. Implement mode-specific credential provision, storage, and configuration
   tests using dummy secrets. Review the host-side changes before activation.
3. Recreate the affected containers and remove stale authentication configuration
   through the approved rollout. Confirm that normie authentication storage and
   forwarding services are inaccessible from YOLO, including while both
   containers are running.
4. Verify local Git operations without GitHub authentication, including commits
   in existing public and private clones. Verify unauthenticated public HTTPS
   reads, and private remote access only from normie.
5. With explicit user authorization, validate remote write rejection from YOLO
   and successful writes from normie against a disposable test repository.
   Include both Git and GitHub API operations and repeat relevant checks after
   an editor reconnect. Do not use the production repository for mutation tests.

Creating credentials, authenticating, changing host settings, and conducting
remote mutation tests are future rollout actions; this planning request does
not authorize them.

## Boundary and unresolved choices

The recommendation prevents writes using the user's credentials by withholding
write authority from YOLO. It is not an absolute network prohibition on every
possible Git push or API mutation: a process supplied with another valid write
credential could still use an allowed destination, and arbitrary remotes may
have different authentication rules.

If the requirement is an absolute prohibition even with newly supplied
credentials, it needs a larger network design: mediate allowed Git/API traffic
through an external policy-enforcing service and prevent direct paths around
it. The existing IP allowlist does not provide that guarantee.

Before implementation, settle:

- Whether issue reads should remain allowed, as assumed here.
- Whether reliable mode-specific VS Code forwarding controls are available, or
  automatic forwarding should be disabled in both modes with explicit GitHub
  authentication provided only to normie.
- Whether withholding the user's write credentials meets the desired boundary,
  or an absolute network-enforced write prohibition is required.

## References

- [VS Code: sharing Git credentials with a container](https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials)
- [GitHub CLI: authentication](https://cli.github.com/manual/gh_auth_login)
- [GitHub CLI: environment variables](https://cli.github.com/manual/gh_help_environment)
- [GitHub: managing personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)

## Addendum (2026-10-02): favored plan and discussion summary

Status: favored plan chosen by the user; still no container or authentication
changes made. This addendum supersedes the open questions in §1 and the
normie authentication choice in §3. The objective table above is unchanged,
except that normie GitHub access comes only through `ybe --normie`.

### Favored plan

1. **Do not attach VS Code to the YOLO container.** Open a local (unattached)
   VS Code window on the checkout and run `ybe` in its integrated terminal.
   `ybe` uses `devcontainer exec`, which starts no VS Code relay, so YOLO has
   no credential, Git askpass, or SSH agent sockets. The user tested this:
   file links in Codex output are clickable from a `ybe` session in a VS Code
   terminal.
2. **Give GitHub access to `ybe --normie` sessions only, per session.** In
   `ybe` (`.devcontainer/host/devcontainer.zsh`), for normie only, read a
   GitHub token on the host and pass it into the exec session as `GH_TOKEN`.
   Preferred source: a dedicated fine-grained token in the host Keychain,
   scoped to the needed repositories. Do not add it to
   `credentials/credentials-map.json`, which feeds both containers' env file.
   `gh auth token` (the host `gh` login) is the simpler fallback.
3. **Route normie Git through `gh`.** Set `credential.helper` to
   `!gh auth git-credential` in `normie/devcontainer.json` so `git push` uses
   the same session token. Update `tests/test_config_twins.py` to permit this
   normie-only difference.
4. **Keep pushing from the host possible.** The bind mount shares the working
   tree and `.git`, so a plain host terminal tab in the same VS Code window can
   also push with the host login.

Resulting access:

| Session | GitHub access |
| --- | --- |
| `ybe` (YOLO) | None |
| `ybe --normie` | `GH_TOKEN` for that session, used by `gh` and Git |
| VS Code attached to normie | VS Code relay (unchanged) |
| VS Code attached to YOLO | Relay returns; avoid |

Properties: the token is not in Docker metadata or a volume, and ends with the
session. Containers have separate PID namespaces, so YOLO cannot read a normie
shell's environment. Within normie, any `ubuntu` process can read the token
from `/proc/<pid>/environ` while the session runs; this is accepted.

Checks before relying on it:

- Pass `GH_TOKEN` by name, inherited from the environment, not as
  `KEY=value` on the `docker exec` command line, which would expose it in the
  host process list for the session's life. Confirm whether
  `devcontainer exec --remote-env` supports that or whether `ybe` should call
  `docker exec` directly.
- Confirm `gh auth git-credential` uses `GH_TOKEN`, with a token scoped to a
  disposable repository and explicit user authorization.
- Consider a startup or prompt warning when
  `/tmp/vscode-remote-containers-ipc-*.sock` exists in YOLO, since one
  attached VS Code window re-enables the relay for every process.

### One-key launch from a VS Code terminal

Opening a terminal, running `ybe`, then starting the agent is three steps
where an attached window needed one keybinding. Restore one key:

1. **Terminal profiles and a keybinding (host user settings only).** In the
   host VS Code user `settings.json`, add profiles that run `ybe` through an
   interactive zsh (`-i` loads `.zshrc`, which defines `ybe`):

   ```jsonc
   "terminal.integrated.profiles.osx": {
     "YOLO": { "path": "zsh", "args": ["-ic", "ybe"] },
     "Normie": { "path": "zsh", "args": ["-ic", "ybe --normie"] }
   }
   ```

   Bind a key in `keybindings.json`:

   ```jsonc
   {
     "key": "ctrl+shift+y",
     "command": "workbench.action.terminal.newWithProfile",
     "args": { "profileName": "YOLO" }
   }
   ```

   The profile starts in the directory VS Code already tracks, and `ybe` maps
   it to the matching container directory, so relative links stay aligned
   without the manual habit described below. Keep these in host user
   settings, not `/yolobox/.vscode/settings.json`: they are machine-specific,
   and attached windows would carry unused entries.
2. **Add `--run <cmd>` to `ybe`.** `ybox --shell` currently only opens a
   shell (`devcontainer.zsh`: `zsh -c "cd … && exec zsh"`). A `--run` option
   (or a wrapper such as `ybclaude`) would exec
   `zsh -ic "cd <remote_path> && <cmd>; exec zsh"`, leaving a container shell
   after the agent exits. Profile args then become
   `["-ic", "ybe --run claude"]` or `codex`. Update the `_ybcode` completion
   and the `devcontainer.zsh` header.
3. **Optional: skip `devcontainer up` when the container is running.** Each
   `ybe` runs `_ybox_up` first. If launch latency is noticeable, go straight
   to `exec` for a running container.

### Relative links in `ybe` sessions

VS Code resolves relative terminal links against the host shell's last known
directory, and it cannot see `cd` inside the container. `ybe` maps the host
directory to the matching container directory, so the habit is: `cd` on the
host, then `ybe`, then start the agent. A `cd` inside the container before
starting the agent misaligns the base; VS Code then falls back to a workspace
search. Absolute `/yolobox/...` links need a root `/yolobox` entry on macOS via
`/etc/synthetic.conf` (reboot required). Optional later: emit VS Code's
current-directory escape sequence from the container shell.

### Findings from the discussion

- **The forwarding is a relay, not a config line.** When VS Code attaches,
  it starts a relay in the container with sockets in `/tmp`:
  `vscode-remote-containers-ipc-*.sock` (`REMOTE_CONTAINERS_IPC`, answered by
  host `git credential fill`), `vscode-git-*.sock` (`VSCODE_GIT_IPC_HANDLE`,
  `GIT_ASKPASS`, the VS Code Git extension), and `vscode-ssh-auth-*.sock`
  (`SSH_AUTH_SOCK`, the host agent, which held no identities when checked).
  The helper script `/tmp/vscode-remote-containers-*.js` simply POSTs the
  request to the IPC socket.
- **Helper locations.** The helper line is in `~/.gitconfig` (user-owned,
  copied from the host, on the container overlay) and in
  `/usr/local/etc/gitconfig` (root-owned). `/etc/gitconfig` does not exist.
  `.devcontainer/README.md`'s "root-owned system gitconfig" wording should
  be corrected when that section is rewritten.
- **The sockets are `srwxr-xr-x ubuntu`.** Any process running as `ubuntu`
  can connect, so any agent can request the host's github.com credential
  directly. If the host Git helper is `gh`, that is the host `gh` OAuth token.
- **No documented switch disables the relay.** VS Code documents forwarding
  as automatic. `dev.containers.gitCredentialHelperConfigLocation: "none"`
  and `dev.containers.copyGitConfig: false` govern the config line and
  gitconfig copy; whether the host still answers socket requests under
  `"none"` is unverified. No setting disables SSH agent forwarding. Host
  settings apply to both modes; a per-mode VS Code profile depends on the
  setting's scope, also unverified.

### Options considered and not chosen

- **Clear configuration in YOLO's `devcontainer.json`** (`GIT_CONFIG_*`
  override of `credential.helper`, blank `GIT_ASKPASS` and `SSH_AUTH_SOCK`,
  `GIT_TERMINAL_PROMPT=0`, `git.terminalAuthentication` and
  `github.gitAuthentication` false). Cheap, but it removes pointers, not the
  relay, so it only prevents accidental use. Still a reasonable extra layer
  if VS Code is ever attached to YOLO.
- **Host-side `"none"` in a YOLO-only VS Code profile** launched by
  `ybcode`. Blocked on the two unverified points above.
- **Run YOLO agents as a separate Unix user.** A real OS boundary, since
  that user cannot connect to `ubuntu`'s sockets, but a larger change
  (ownership, auth volumes, `PATH`, no `sudo` path back to `ubuntu`).
- **Normie-only `~/.config/gh` volume with `gh auth login`.** Simpler than
  per-session injection, but gives every normie process, including VS Code
  windows, standing access.
