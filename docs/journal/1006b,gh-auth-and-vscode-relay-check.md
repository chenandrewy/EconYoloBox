# GitHub authentication and VS Code relay check

Date: 2026-10-06
Status: checks completed; startup cleanup discussed, not implemented. The user
manually removed the global VS Code credential helper. No container setup or
VS Code settings were changed by the agent.

Related: [GitHub access in normie only](1006a,plan-gh-normie-only.md).

## Findings

The user asked to test GitHub authentication blocking in this container.
`gh auth status` exited with code 1 and reported that no GitHub hosts were
logged in. This establishes the current `gh` login state, not that login
attempts are blocked or that Git cannot obtain credentials elsewhere.

The posture check reported:

```text
yolo internet=firewalled package_access=readonly seccomp=builtin
```

Both `/usr/local/etc/gitconfig` and `/home/ubuntu/.gitconfig` contained a
VS Code credential helper. Each invoked VS Code's bundled Node executable
and a `/tmp/vscode-remote-containers-*.js` script with
`git-credential-helper`. VS Code Dev Containers creates these entries to
relay credential requests to the host when a window attaches.

The agent invoked the configured relay script's `get` operation for HTTPS
`github.com`, capturing output without displaying credential values. It
exited with code 255, returned no username or password/token, and produced
no stderr. All six discovered `vscode-remote-containers-ipc-*.sock` sockets
refused connections. Relay scripts, Git sockets, and SSH-agent socket paths
were present, but their presence alone does not establish a working relay.
The SSH-agent sockets were not tested.

Conclusion: the tested credential relay was inactive at that moment. This
does not establish permanent isolation; a later VS Code attachment can
start a relay again. No credentials were displayed or saved, and no
credential was submitted to GitHub for validation.

## Commands discussed for manual checks

Run inside the container; running these on the Mac tests the host instead.
The following works directly in zsh and reports credential presence without
printing the values:

```zsh
printf 'protocol=https\nhost=github.com\n\n' |
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false git credential fill |
  awk '
    /^username=./ { user = 1 }
    /^password=./ { token = 1 }
    END {
      print "Username returned:", user ? "yes" : "no"
      print "Token returned:", token ? "yes" : "no"
    }
  '
```

Immediately afterward, zsh can show each pipeline process's exit code:

```zsh
print -r -- "printf / git / awk exit codes: ${pipestatus[*]}"
```

Git asks its configured helpers for the credential. The environment settings
disable Git's terminal and fallback askpass prompts for this command. The
credential, if returned, passes through the pipe in memory; `awk` prints
only presence flags. This does not validate it against GitHub. Running bare
`git credential fill` can print the token.

Inspect helper configuration without requesting credentials:

```zsh
git config --show-origin --show-scope --get-all credential.helper
git config --show-origin --get-regexp '^credential\..*helper$'
```

The second command also includes URL-specific helper settings.

## User's manual change and remaining system helper

The user ran:

```zsh
git config --global --unset-all credential.helper 'vscode'
```

The subsequent listing contained only the system helper in
`/usr/local/etc/gitconfig`. Removing the user entry does not mask the system
entry: Git still tries the inherited helper. In its value, `!` introduces a
shell command, `f() { ...; }; f` defines and calls a function, and `$*`
passes Git's arguments, such as `get`, to the relay script.

The agent had also suggested removing the system entry using sudo. The
user clarified that sudo is restricted to container setup, so this was not
an appropriate interactive instruction here. The system entry was not
removed during this conversation.

An alternative discussed, but not reported as executed, was:

```zsh
git config --global --add credential.helper ''
```

An empty helper resets the accumulated helper list. It disables inherited
helpers for Git unless a later setting adds another helper; it does not
stop a process from contacting a live relay directly.

## Proposed YOLO startup cleanup

The user asked whether startup could remove both the global and system
VS Code helper entries, explicitly requesting no implementation yet.
The proposed operations are:

```zsh
git config --global --unset-all credential.helper 'vscode'
# In the privileged container setup context:
git config --system --unset-all credential.helper 'vscode'
```

Implementation requirements discussed:

- Apply only to YOLO; preserve normie's authentication setup.
- Run the global operation as `ubuntu` so it targets the correct home.
- Run the system operation where container setup already has the necessary
  privileges; do not broaden interactive sudo access.
- Treat exit code 5 (no matching entry for this operation) as an expected
  outcome, while preserving other errors.

`.devcontainer/post-start.sh` already removes stale VS Code relay files
outside normie. Helper cleanup is related to that logic, but the exact
privileged setup hook still needs to be selected when implementing it.
No startup code was edited.

For prevention of newly written helper entries, the host VS Code user
setting discussed was:

```json
"dev.containers.gitCredentialHelperConfigLocation": "none"
```

This setting was not changed. As documented in the
[container README](../../.devcontainer/README.md#github-auth), preventing
helper entries is not known to stop the relay from answering direct
requests, and SSH forwarding is separate. Startup cleanup likewise only
removes what exists at startup. The intended isolation remains: keep
VS Code local and use `ybe`, `ybcc`, or `ybgpt` rather than attaching a
VS Code window to YOLO.
