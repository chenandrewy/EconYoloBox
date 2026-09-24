# Codex / Bubblewrap inside the devcontainer — investigation notes

2026-09-15. Requested posture: firewall normally open; ordinary Codex sessions
sandboxed; YOLO requires an active firewall. Investigation and proposed plan
only. No configuration changes, installs, restarts, or firewall operations.

## Finding / confidence

**Leading hypothesis: Docker's outer syscall policy blocks Bubblewrap's inner
namespace/mount setup. Not yet a reproduced diagnosis.** Installing Bubblewrap
does not grant permission to use the kernel operations it needs. AppArmor and
host user-namespace controls can independently block the same setup.

This investigation is running on macOS (`uname -s`: `Darwin`), outside the
container. The Docker CLI exists, but `docker ps` failed with permission denied
connecting to `/Users/chen1678/.docker/run/docker.sock`. Consequently no live
container ID, Engine version, security profile, kernel settings, in-container
Codex version, or exact Bubblewrap error was obtained. Permission to retry
read-only Docker access and harmless probes was requested under the user-level
AGENTS.md rule about permission workarounds; no workaround was attempted.
Do not call any proposed runtime flag a verified minimum until those checks run.

## Evidence in this checkout

- `.devcontainer/devcontainer.json:21`: `runArgs` adds `NET_ADMIN`, `NET_RAW`,
  and an env file. No seccomp/AppArmor override, `SYS_ADMIN`, or privileged mode.
  Docker defaults are therefore the expected baseline, subject to daemon and
  tooling overrides. Source configuration is not proof of the existing container.
- `.devcontainer/Dockerfile:68` already installs `bubblewrap`; the image uses
  Ubuntu 24.04 and runs as `node`. Reinstalling a missing tool is not the first
  proposed fix. Check the actual running image and executable before concluding
  the package is present there.
- Codex is installed into a persistent npm volume at runtime. A rebuild alone
  does not establish which Codex binary/version runs. The Mac's Codex symlink
  points to 0.154.0, which says nothing about the container version.
- `SANDBOX.toml:11` currently says `firewall = false`; this was an existing local
  modification at investigation start. `post-start.sh` skips firewall setup in
  that mode. It does not actively remove pre-existing rules.
- `.devcontainer/shellrc.sh:113` and `:117`: `gptchat-yolo` and `gptmini-yolo`
  unconditionally pass `--dangerously-bypass-approvals-and-sandbox`. No firewall
  check. `cchat-yolo` likewise bypasses Claude permissions. The warning marker
  is explicitly documented as startup intent, not live kernel state.
- The system Codex config supplies TUI defaults, without an explicit ordinary
  sandbox mode. Requirements constrain plugins/apps, not sandbox modes. The
  persisted user config must be inspected selectively for sandbox overrides.
- Dockerfile copies the firewall initializer into `/usr/local/bin` and grants
  `node` sudo for that root-owned initializer only. No root-owned, read-only
  firewall-status helper exists in the inspected configuration.
- `.host/` supplies navigation; personal remote launchers live elsewhere. Their
  behavior is not verified here and must be covered before claiming all YOLO
  entry points are gated.

## Which outer restriction matters?

Codex's current Linux sandbox uses Bubblewrap plus seccomp. OpenAI explicitly
notes that containers can block the namespace, setuid-bwrap, or seccomp operations
it needs. Its container-only/full-access alternative does not satisfy this
request's ordinary-session requirement. [OpenAI sandbox documentation][openai]

| Layer | What to establish | Consequence for the proposed change |
| --- | --- | --- |
| Docker seccomp (syscall filtering) | Effective Engine profile and first denied syscall | Leading suspect. Namespace creation and mount operations are restricted in Docker's default profile. |
| AppArmor | Engine security options, container profile, process label, matching audit denial | A separate block may remain after a seccomp exception. Do not disable it speculatively. |
| Host user namespaces | Kernel support, namespace limits, any unprivileged-userns restriction | Needs host-specific handling if disabled; installing tools inside Ubuntu cannot change the host kernel policy. |
| Identity and executable | `node` UID/caps, bwrap version/mode, actual executable selected by Codex, `NoNewPrivs` | Distinguish unprivileged user namespaces from a setuid fallback. A setuid path can fail under no-new-privileges or nosuid mounts. |
| Other runtime controls | Userns remapping/rootless mode, mounts, proc masks, LSMs | Investigate only when error evidence points here; do not broadly unmask proc or expose host namespaces. |

Docker documents restrictions on `clone`, `unshare`, `mount`, `pivot_root`,
`umount2`, and `setns`; exact rules depend on Engine version and capabilities.
Its default filter is inherited by children: creating an inner user namespace
does not remove the outer filter. A custom profile should start from the matching
Docker default, retaining unrelated denials. [Docker seccomp documentation][seccomp]

AppArmor is another independent layer, with per-container profile selection and
audit logs for denials. [Docker AppArmor documentation][apparmor] Ubuntu also
supports application-specific permission for unprivileged user namespaces,
because these expose additional kernel attack surface. The image's Ubuntu
version alone does **not** establish that such a host restriction is active;
on Docker Desktop the relevant Linux kernel is in its VM. [Ubuntu explanation][ubuntu]

## Minimum changes to evaluate, after authorization

1. **First establish the denial without changing runtime configuration.** Identify
   the container by this workspace's devcontainer label. Read selected inspect
   fields: security options, AppArmor profile, capabilities, privileged flag,
   userns mode, process user, network mode, and mount destinations. Avoid dumping
   environment variables or credentials. Record Engine/kernel versions and
   `/proc/self/status` fields `Seccomp`, `Seccomp_filters`, `NoNewPrivs`, `CapEff`,
   `CapBnd`; read the process AppArmor label and available userns sysctls.
2. **Run progressively scoped probes as `node`.** Check `codex --version`,
   `bwrap --version`, executable modes, and `codex sandbox linux --help`. Test
   `unshare --user --map-root-user true`, then Bubblewrap with a read-only root
   bind and `/bin/true`, then the installed Codex sandbox command with `/bin/true`.
   Capture stderr and exit codes. An `EPERM` alone does not distinguish seccomp,
   AppArmor, or kernel policy. Use existing tracing/audit tools if available;
   request permission before installing absent tools. Passing plain bwrap does
   not establish that Codex's complete invocation works.
3. **Preferred durable fix: a per-container seccomp profile allowing only the
   demonstrated setup operations.** Add one `--security-opt=seccomp=...` run
   argument referencing a host-readable profile derived from the actual Engine
   baseline. Candidate operations include namespace creation and mount/root
   setup; this is not an approved syscall allowlist. Filter scalar flags where
   practical; classic seccomp cannot inspect path strings or a `clone3` argument
   structure. Keep its existing `clone3` fallback behavior unless evidence
   requires a change. Preserve `node` and current outer capability limits.
4. **Smallest textual experiment, broader security cost:** a disposable,
   explicitly authorized test container with only
   `--security-opt=seccomp=unconfined` changed can isolate seccomp as the cause.
   No such container was created here. This disables Docker's syscall filter
   for every process, including unsandboxed YOLO processes; Codex's inner filter
   can still operate, but cannot protect processes outside it. Treat this as a
   diagnostic or an explicitly accepted compromise, not least privilege.
5. **Only if AppArmor denies the probe:** propose a dedicated container profile
   permitting the needed userns/mount operations while keeping other denials.
   `--security-opt=apparmor=unconfined` is a broader alternative to measure
   separately, not an automatic companion to seccomp unconfined. Avoid global
   daemon changes or disabling host userns restrictions globally.

Do not start with `--privileged`, `--cap-add=SYS_ADMIN`, root execution, chmod
setuid on bwrap, host PID/network namespaces, Docker socket mounts, or a legacy
sandbox fallback. These broaden authority or change the security model without
isolating the cause. Capabilities inside a new user namespace can support its
mount setup without granting outer-container `SYS_ADMIN`. Even targeted
namespace/mount exceptions increase kernel exposure for **all** container code;
the firewall cannot mitigate a kernel escape. Any approved runtime-policy edit
requires container recreation and inspection of the effective result.

## Preserve the requested operating modes

- Keep the current explicit `firewall = false` normal posture. Set and verify
  ordinary Codex launches to `workspace-write` with an appropriate approval
  policy (proposed: `on-request`), accounting for user/profile/CLI overrides.
  Container egress being open does not require sandboxed commands to have open
  networking. Leave their network restriction as a separate explicit policy.
  Refuse launch on sandbox setup failure; do not silently switch to full access.
- Gate YOLO on **live firewall state**, using a narrowly scoped root-owned
  status checker and narrowly scoped sudo permission if needed. TOML, a `/tmp`
  marker, `OUTPUT DROP` alone, or a failed curl alone is insufficient evidence.
  Check expected chains/rule order, terminal deny behavior, referenced sets,
  and IPv6 coverage or verified absence of IPv6 routing. Unknown state refuses
  YOLO. Existing firewall tests are useful connectivity smoke tests, not an
  authoritative state check: a failed blocked-site request may just mean outage.
- Apply the gate to both Codex YOLO helpers and any other intended YOLO launch
  paths. A shell wrapper is an accidental-launch guard, **not** enforcement
  against arbitrary `codex --yolo`, full-access config, alternate binaries, or
  node-writable shell code. A hard guarantee requires a protected launcher/policy
  boundary; consider a separately launched firewall-required YOLO container if
  that is the desired strength. Do not claim aliases enforce it.
- Firewall activation affects the entire container, including ordinary sessions.
  It must remain active throughout YOLO, not merely at launch. Do not reopen it
  while such sessions remain. Bare Docker restart can skip the devcontainer
  post-start hook, so every YOLO launch needs fresh verification.
- Existing rules allow broad Google/GitHub ranges, arbitrary outbound SSH/DNS,
  and a host-network subnet; established connections are accepted. An active
  firewall reduces egress but does not prevent all exfiltration. Arming after an
  open interval can preserve existing connections; a fresh firewall-required
  lifecycle before YOLO is cleaner. Inner network namespaces cannot simply
  grant authority over the parent network namespace's firewall, but retain
  no host-network/socket escape paths. These are limits, not a request to
  redesign the firewall in this nested-compatibility task.

## Acceptance checks for the eventual implementation

- Same `node` user: namespace probe, bwrap probe, then actual Codex sandbox work
  with firewall open and armed. Capture exact versions and effective profiles.
- Ordinary sandbox permits a scratch write under its authorized workspace and
  denies a scratch write to a node-writable location outside the allowed roots.
  Choose temporary paths deliberately; `/etc` permission denial proves little.
  Verify command-network behavior against the chosen sandbox policy.
- YOLO refuses with open, missing, stale, or unreadable firewall state; succeeds
  only after verified arming. Include direct restart and alternate launcher paths.
- Confirm IPv4/IPv6 firewall behavior and allowed/blocked connectivity together.
- Confirm no added outer `SYS_ADMIN`, privileged mode, host namespace sharing,
  or socket exposure, and that existing restricted sudo/firewall behavior still
  works. Do not add outer no-new-privileges casually: it can prevent the current
  sudo initializer from becoming root.

**Current stopping point:** source audit and proposed plan complete; runtime
confirmation awaits authorized Docker access. Existing journal entries were not
edited. Pre-existing `SANDBOX.toml` and untracked `Post-hoc/` changes are untouched.

[openai]: https://learn.chatgpt.com/docs/agent-approvals-security
[seccomp]: https://docs.docker.com/engine/security/seccomp/
[apparmor]: https://docs.docker.com/engine/security/apparmor/
[ubuntu]: https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces
