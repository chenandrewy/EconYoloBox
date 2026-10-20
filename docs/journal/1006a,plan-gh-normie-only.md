# Plan: GitHub access in normie only

Date: 2026-10-06
Status: chosen by the user; no container or authentication changes made. Derived from
the favored plan in [1002a](1002a,plan-git-separation.md), which also holds
the background, findings, and rejected options. Revised 2026-10-06: a manual
`gh` login in normie replaces 1002a's per-session `GH_TOKEN` injection.

## Objective

YOLO agents work and commit in local clones but hold no GitHub credentials,
including read tokens. Pushes and GitHub issue writes happen only in normie
sessions or on the host. Normie capability does not itself authorize an agent
to publish; explicit user authorization is still required.

| Operation | YOLO | Normie |
| --- | --- | --- |
| Local commits, branches, diffs | Allowed | Allowed |
| Fetch/clone public repositories over HTTPS | Available without authentication | Allowed |
| Fetch/clone private repositories | Use normie or the host | Allowed with authentication |
| Read issues | Public unauthenticated access only | Allowed with authentication |
| Push branches or tags to GitHub | Blocked through absence of credentials | Allowed with authentication |
| Create, comment on, or modify issues | Blocked through absence of credentials | Allowed with authentication |

## Shape

VS Code always runs on the host, as a local window on the checkout. Agents
run from its integrated terminal through the host launchers in
`.devcontainer/host/agents.zsh`:

| Command | Container | Agent |
| --- | --- | --- |
| `ybcc` | YOLO | Claude |
| `ybgpt` | YOLO | Codex |
| `nbcc` | normie | Claude |
| `nbcodex` | normie | Codex |

Each takes `[DIRECTORY] [-- AGENT_ARGS...]` and goes through `ybox --shell`
(`devcontainer exec`), the same path as `ybe`. Use `ybe` or `ybe --normie`
for a plain container shell. File links in agent output are clickable from
these terminals (tested with Codex).

GitHub access follows the launcher:

1. **`yb*` sessions run without GitHub credentials.** `devcontainer exec`
   starts no VS Code relay, so YOLO has no credential, Git askpass, or SSH
   agent sockets. Local commits work as usual.
2. **Log in to `gh` once in normie.** In an `nb*` or `ybe --normie`
   session, run `gh auth login --with-token` with a dedicated fine-grained
   token scoped to the needed repositories (plain `gh auth login` also works,
   but its browser flow grants broad default scopes). `gh` stores the login
   in `~/.config/gh/hosts.yml`, in plain text since the container has no
   keyring. `~/.config` lives on each container's own filesystem layer, not
   on a shared volume or the bind mount, so YOLO cannot see it.
3. **Point normie Git at `gh`.** Run `gh auth setup-git` in the same
   session. It writes the credential helper into normie's `~/.gitconfig`, so
   `git push` uses the same login. No `devcontainer.json` or
   `test_config_twins.py` change is needed.
4. **Host pushes still work.** The bind mount shares the working tree and
   `.git`, so a plain host terminal tab in the same window can push with the
   host login.

`gh` stays installed in both containers. Without credentials it cannot push
or write issues, and removing it would not block `git push` or direct API
calls with a token. Agent guidance can point YOLO agents to `nbcc` or
`nbcodex` for GitHub work.

## Resulting access

| Session | GitHub access |
| --- | --- |
| `ybcc`, `ybgpt`, `ybe` | None |
| `nbcc`, `nbcodex`, `ybe --normie` | Stored `gh` login, used by `gh` and Git |
| Host terminal | Host login |
| VS Code window attached to a container | VS Code relay, reachable by any process there; in YOLO this breaks the separation |

The login is standing access: any normie process can use it while the
container exists, not only during an agent session. This is accepted. The
YOLO-to-normie escalation paths in
[1003a](1003a,aichatrender-ybcc-and-yolo-escalation-paths.md) run inside
normie agent sessions, which would hold a per-session token anyway. The login
survives container stop and start but not a rebuild; log in again after a
rebuild.

## Checks before relying on it

- After `gh auth setup-git`, confirm normie's `~/.gitconfig` has the `gh`
  helper and that YOLO's `~/.gitconfig` and `~/.config/gh` have none. Test a
  push against a disposable repository, with explicit user authorization.
- Confirm a container restart keeps the login and a rebuild drops it.

## Attaching VS Code to YOLO

One attach is a risk for as long as the window stays attached. The relay
serves the whole container, so any YOLO process, including `ybcc`/`ybgpt`
sessions started from a host terminal, can ask it for the host's github.com
credential. Closing the window does not stop the relay: its process keeps
running until the container stops (see the check below). Whether a relay
whose window has closed still gets an answer from the host is unverified. The
lasting case is an agent that captured the token while the relay worked and
saved it.

The 2026-10-06 check from a `ybe` shell found:

- No relay environment variables in the `ybe` session.
- Leftover relay files from six earlier attaches (Oct 1 to Oct 5):
  `vscode-remote-containers-ipc-*`, `vscode-ssh-auth-*` and `vscode-git-*`
  sockets, with matching `vscode-remote-containers-*.js` helper scripts.
  `/tmp` is on the container's own layer, so these survive restarts until a
  rebuild.
- Four relay processes still running (`vscode-remote-containers-server-*.js`
  under VS Code's `node`), one per Oct 5 attach, with no YOLO window in use.
  The Oct 1 relays were gone, so a container restart ends them; their files
  stayed.
- No `~/.config/gh`. The YOLO gitconfig check was garbled by a line wrap and
  still needs rerunning.
- At 13:43 no relay processes were running in YOLO.
- The user logged in to `gh` in normie; `gh auth status` in YOLO then showed
  no login. The shape works with no code changes.

Done: `post-start.sh` now removes leftover relay files
(`/tmp/vscode-remote-containers-*`, `vscode-ssh-auth-*`, `vscode-git-*`) on
every start unless the posture is normie, so any relay file seen later in
YOLO comes from an attach since that start.

Options for YOLO's `devcontainer.json` and the host launchers:

1. **Remove the helper lines** with a `postAttachCommand` or a `GIT_CONFIG_*`
   override. Easy, but it removes pointers only; a process can still talk to
   the socket directly.
2. **Delete the relay sockets** in a YOLO `postAttachCommand`. New connections
   then fail because the socket path is gone. Untested: exposure starts before
   the command runs, VS Code may recreate the sockets on reconnect or a new
   terminal, and other window features that use the same socket may break.
3. **Make the attach hard to do by accident.** Have `ybcode` refuse YOLO, or
   require an explicit override flag (a small change in
   `.devcontainer/host/devcontainer.zsh`), and add a YOLO `postAttachCommand`
   that prints a loud warning and deletes the sockets. More reliable than 1
   or 2 alone.
4. **Host setting `"dev.containers.gitCredentialHelperConfigLocation":
   "none"`** for both modes, since normie now uses its own `gh` login. It
   stops the helper line being written but is not known to stop the relay
   answering.

## Optional: configurable publishing policy in normie

Today the rule against publishing without permission is guidance only, in
`~/.claude/CLAUDE.md`. That file is on the shared `~/.claude` volume, so the
rule is the same in both modes. YOLO cannot push anyway, so a configurable
policy only matters in normie. Three layers, weakest to strongest:

1. **Guidance.** Reword the rule around one setting, for example
   `YB_PUBLISH=ask|branches|any`. The `nb*` launchers would set it (say,
   `nbcc --publish=branches`), with `ask` as the default, and `posture.sh`
   would print it next to the mode. Codex reads the same rule from the shared
   `~/.codex`. This relies on the agent following instructions.
2. **Agent permission rules.** Claude ask/allow rules for
   `Bash(git push:*)`, `Bash(gh pr create:*)`, and `gh issue` writes, with
   the launcher choosing a settings file per level (the launcher rejects a
   user-supplied `--settings`, but can pass its own). Codex rules in
   `~/.codex/rules` can prompt, allow, or forbid commands. `nbcodex`'s
   `workspace-write` sandbox may already route network access through
   approval (unverified), and Claude's auto mode may flag pushes itself
   (unverified). Command-text matching can be dodged by rewording the shell
   command.
3. **GitHub.** The fine-grained token's scope limits which repositories and
   what kinds of writes are possible (Contents, Issues, no admin). A branch
   ruleset on `main` (no direct push, no force push) lets agents push feature
   branches and open PRs without touching `main`. This is the only layer an
   agent cannot talk its way past, and it also applies to the host.

Suggested combination: GitHub caps the worst case, the launcher setting picks
behavior within it, and permission rules make the `ask` level prompt. That
makes "normie may push feature branches and open PRs without asking" a safe
level to offer. The escalation paths in 1003a then reach a session that can
push, so the `main` ruleset also bounds that.
