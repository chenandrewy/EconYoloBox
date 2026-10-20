# VS Code credential relay after GitHub OAuth reset

Date: 2026-10-06
Status: attached-container check completed; no authentication or container
configuration changes made by the agent.

Related: [initial plan](1006a,plan-gh-normie-only.md) and
[earlier relay check](1006b,gh-auth-and-vscode-relay-check.md).

## User procedure

The user reported this sequence:

1. Revoked VS Code's GitHub OAuth credentials on the GitHub website.
2. Signed back into GitHub in VS Code to restore GitHub Copilot.
3. Attached VS Code to a YOLO container for testing.
4. Tested authentication and credential forwarding with the agent.

## Observations

The container posture was `yolo internet=firewalled package_access=readonly
seccomp=builtin`.

Both `/usr/local/etc/gitconfig` and `/home/ubuntu/.gitconfig` contained a
VS Code credential helper invoking its bundled Node executable and a
`/tmp/vscode-remote-containers-*.js` script. Inspection of `/proc/net/unix`
found three listening Dev Containers IPC sockets, three listening SSH-agent
relay sockets, and one listening VS Code Git socket. Other socket files
were present without listeners. No forwarding environment variables were
present in the agent's shell.

`gh auth status` exited with code 1 and reported no logged-in GitHub hosts.
This tests GitHub CLI's login state, separately from Git's credential helper.

With explicit user authorization, the agent ran `git credential fill` for
`protocol=https` and `host=github.com`, with `GIT_TERMINAL_PROMPT=0`, a
15-second timeout, and stdout/stderr captured in memory. Only credential
presence and the exit code were printed:

```text
Credential returned: False
Exit code: 128
```

No secret was printed or saved, and no credential was submitted to GitHub.
Captured stderr was not inspected, so the reason for failure is unresolved.
This tested the configured Git helper path, not a direct request to every
IPC socket. SSH-agent key availability and signing were not tested.

VS Code local history contains a saved host user settings file with:

```json
"git.terminalAuthentication": false,
"dev.containers.gitCredentialHelperConfigLocation": "none"
```

The current host settings file was not accessible from the container, so
their present values and effective scope were not verified. These settings
control integrated-terminal authentication and installation of the container
credential helper, respectively; they do not establish that relay sockets
or SSH-agent forwarding are disabled. Existing helper entries remained.

`post-start.sh` removes leftover relay files outside normie once at startup.
It does not continuously prevent attachments from creating new relays and
does not remove Git credential helper entries.

## Interpretation and documentation

The result is reassuring: after the reported OAuth reset and VS Code sign-in
for Copilot, the tested Git helper did not supply a GitHub HTTPS credential,
even with listening relay sockets. A listening relay is therefore not proof
that a usable GitHub credential is exposed. The earlier inactive-socket
check and this active-socket check should not be conflated.

This does not yet establish that attaching VS Code to YOLO is safe in all
cases. The cause of the failed helper request, direct relay behavior, and
SSH-agent capabilities remain unverified. Copilot access alone is not
evidence that Git can retrieve a credential, nor does this check prove a
general separation between Copilot and Git authentication.

The container README and feature guide now distinguish relay availability
from successful credential retrieval and link to this check. The existing
guidance to keep VS Code detached from YOLO remains pending broader evidence.
No startup code, launcher, or VS Code settings were changed.
