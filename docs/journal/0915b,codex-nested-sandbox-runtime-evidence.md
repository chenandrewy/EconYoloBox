# Nested Codex sandbox — live runtime evidence

2026-09-15. Follow-up to [the source audit](0915a,codex-nested-sandbox-investigation.md).
Doctor Mister Andrew authorized elevated read-only Docker inspection and harmless
probes in the existing container. No configuration changes or new containers.
The earlier journal entry remains an unchanged snapshot.

## Result

**Failure reproduced; Docker's built-in seccomp filter is the strongly supported
cause of the initial namespace failure.** Bubblewrap is installed, the host's
unprivileged-user-namespace switch is enabled, and no container AppArmor profile
is active. There is no evidence supporting an AppArmor exception or a host sysctl
change on this machine.

The remaining distinction: this establishes the failing operation and rules out
several alternatives, but does not experimentally prove a sufficient replacement
seccomp profile. No filter was removed, no custom profile was tried, and no syscall
trace was collected (`strace` is absent). Do not describe an exact allowlist as
tested. A missing-tool replacement was not written or installed.

## Observed runtime

Container `ef1743ea6291`, name `practical_visvesvaraya`; its devcontainer workspace
label matches this checkout. Inspection deliberately excluded environment values
and credential contents.

| Item | Observed value |
| --- | --- |
| Docker | Docker Desktop, Engine 29.7.2 |
| Linux kernel | `7.0.12-linuxkit` |
| Engine security options | `name=seccomp,profile=builtin`; `name=cgroupns` |
| Container security overrides | `SecurityOpt=null`; empty AppArmor profile |
| Privileged | `false` |
| Added capabilities | `CAP_NET_ADMIN`, `CAP_NET_RAW` |
| Capability drops | `null` (no explicit additions to Docker's default drop set) |
| User / identity | `node`, UID/GID 1000 |
| Effective process capabilities | `0000000000000000` |
| Bounding capabilities | `00000000a80435fb` |
| NoNewPrivs | `0` |
| Seccomp | `2` (filter mode), one filter |
| Userns mode / PID mode | empty (no explicit override) |
| Network mode | `bridge` |
| `user.max_user_namespaces` | `256875` |
| `kernel.unprivileged_userns_clone` | `1` |
| Codex | `codex-cli 0.154.0` |
| System Bubblewrap | `bubblewrap 0.9.0` |
| `/usr/bin/bwrap` | root-owned, mode `0755`, no setuid bit |

Reading `/proc/self/attr/current` returned `Invalid argument`; it did not supply
an AppArmor label. The Engine options and empty container AppArmor profile are
the affirmative evidence for not pursuing AppArmor here. The AppArmor userns
sysctl was not readable/present in the checked path. A readable LSM list was not
available at `/sys/kernel/security/lsm`.

Mount destinations include `/workspace`, persistent CLI/config/runtime volumes,
`/vscode`, the TeX volume, and `/run/secrets/credentials.env`. No Docker socket
destination appeared. No host PID/network namespace sharing was configured.

## Probe results

Each was run via `docker exec --user node` in the existing container. All three
exited 1. These commands request only an ephemeral namespace/read-only root view
and `/bin/true`; no file-write or network probes were used.

| Command inside container | Result |
| --- | --- |
| `unshare --user --map-root-user /bin/true` | `unshare: unshare failed: Operation not permitted` |
| `bwrap --unshare-user --ro-bind / / /bin/true` | Bubblewrap: no permissions to create new namespace |
| `codex sandbox linux /bin/true` | Same Bubblewrap namespace-permission failure |

Even `codex sandbox linux --help` attempted the sandbox path in this invocation
and produced the same error. The direct `/bin/true` probe independently reproduced
it. The npm `codex` entry point is the standard JS launcher, pointing into the
persistent npm volume; it is not a local shell alias. We did not establish whether
Codex selected the system bwrap or a bundled executable internally.

Bubblewrap's suggestion that the kernel may disallow unprivileged namespaces is
generic error guidance, not proof that `kernel.unprivileged_userns_clone=0`.
Here it is **1**, and the outer seccomp filter is active. Docker documents namespace
and mount syscall restrictions in its default profile, consistent with these
results. [Docker seccomp documentation](https://docs.docker.com/engine/security/seccomp/)

A guessed URL for the Engine-tagged `profiles/seccomp/default.json` returned 404;
no version-matched profile source was obtained. The documentation is supporting
context, not a byte-for-byte representation of this running filter.

## Firewall state and mode-policy implication

Read-only `docker exec --user root` inspected kernel rules (no sudo grant or
firewall behavior was changed):

- IPv4 filter table: INPUT, FORWARD, OUTPUT all `ACCEPT`, no other rules listed.
- IPv6 filter table: likewise all `ACCEPT`, no other rules listed.
- No IPv6 routes were printed at inspection time. This is not a durable IPv6
  security policy.
- Installed initializer is root-owned mode `0755`; sudoers file is root-owned
  mode `0440` and grants only `/usr/local/bin/init-firewall.sh` to `node`.

**The container firewall is open now.** This is live evidence, beyond the TOML
setting. Existing YOLO helpers have no firewall gate, as recorded in the source
audit. They should be considered ineligible under the requested operating policy
until that gate exists and the firewall is verified active. No YOLO session was
launched during this investigation.

A targeted text search of system and user Codex config found no sandbox/approval/
network/profile keys in the inspected files. This does not exhaust every possible
CLI override, project setting, or permissions mechanism; explicit ordinary-launch
defaults and acceptance tests remain appropriate.

## Narrowed proposed plan — not implemented

1. **Change the container's seccomp policy, not AppArmor or host sysctls, as the
   first compatibility experiment.** Keep `node`, non-privileged mode, existing
   capabilities, mounts, and networking. A single
   `--security-opt=seccomp=unconfined` argument is the smallest textual experiment,
   but disables the outer syscall filter for every process. It is not established
   as sufficient here and is not the preferred permanent policy.
2. **Preferred permanent change:** one per-container seccomp-profile reference
   plus a version-matched Docker profile with only the required Bubblewrap setup
   exceptions. Determine those through controlled testing after separate
   authorization for a disposable test container or recreation. `unshare` is an
   observed initial failure; Bubblewrap also needs namespace and mount/root setup,
   so allowing only that syscall may simply reveal the next denial. Do not add
   `SYS_ADMIN`, privileged mode, setuid bwrap, or AppArmor-unconfined preemptively.
3. **Retain normal open firewall plus working ordinary sandbox.** Explicitly
   select/verify workspace-write for ordinary launches; sandbox failure must
   stop the launch, never silently select full access. Then gate YOLO on live
   firewall verification through protected, narrowly privileged inspection.
   Marker files and shell warnings cannot establish this condition. The earlier
   entry details wrapper-bypass limits and the stronger separate-container option.
4. **Validate both layers together after an approved change.** Repeat these
   probes, verify allowed workspace writes and denied outside writes with safe
   scratch locations, and check the chosen command-network policy. Test YOLO
   refusal with the firewall open/unknown and eligibility only when armed,
   including restart behavior. Do not reopen the firewall during YOLO sessions.

The central tradeoff remains: permitting nested namespaces exposes more Linux
kernel operations to every process in the container, while restoring Codex's
inner filesystem/network restrictions for ordinary commands. Disabling Docker
seccomp wholesale also removes unrelated protections from YOLO and other
unsandboxed processes; the firewall cannot replace those protections. A targeted
profile costs maintenance/testing but preserves more of Docker's outer boundary.

This completes the authorized live inspection. No packages installed, container
created/restarted, firewall armed, runtime flag changed, or old journal modified.
