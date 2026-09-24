# 0915d — plan: enable Codex "approve for me" in the container

Messy notes / snapshot. Follows [0915a](0915a,codex-nested-sandbox-investigation.md),
[0915b](0915b,codex-nested-sandbox-runtime-evidence.md),
[0915c](0915c,codex-devcontainer-removed-upstream.md). Plan only, nothing implemented.

## goal
Ordinary `codex` runs as **on-request approval + workspace-write sandbox (network
off)**, OS-enforced by bwrap — the same thing the TUI calls "Approve for me".
YOLO stays the explicit escape hatch.

## why this is the whole game (recap)
- "Approve for me" = TUI preset that sets `approval_policy=on-request` +
  `sandbox_mode=workspace-write`. (label lives only in codex-rs/tui, not documented)
- network-off in workspace-write is enforced by bwrap `--unshare-net`
  (codex-rs/linux-sandbox/src/bwrap.rs:288). NOT by a firewall.
- our container can't bwrap: `unshare` EPERM, Docker's builtin seccomp blocks it
  (0915b). So "approve for me" simply doesn't work here right now.
- chosen path (decided this session): FIX BWRAP by relaxing outer seccomp.
  rejected alts: external-sandbox+firewall (gives up fs isolation), custom
  seccomp profile (more work, untested allowlist).

## current state of OUR setup (verified this session)
- .devcontainer/devcontainer.json runArgs = NET_ADMIN, NET_RAW, --env-file only.
  no seccomp relaxation, no SYS_ADMIN → bwrap fails.
- shellrc.sh has ONLY yolo codex launchers: gptchat-yolo / gptmini-yolo, both
  `--dangerously-bypass-approvals-and-sandbox`. no ordinary sandboxed launcher.
  => today you can only run codex in yolo; the safe mode is broken, not chosen against.
- Codex config lives in volume /home/node/.codex (CODEX_HOME), NOT in repo.
- SANDBOX.toml firewall = false (normal posture).

## key code fact that shapes step 1
bwrap.rs:282-286 uses `--unshare-user` *specifically so root-in-container does
NOT need ambient CAP_SYS_ADMIN*. + 0915b failure was seccomp EPERM, not a cap
denial. => minimal fix is likely `seccomp=unconfined` ALONE, no caps. Test that first.

## the plan

### step 1 — unblock bwrap (minimal first)
edit .devcontainer/devcontainer.json runArgs, add ONLY:
    "--security-opt=seccomp=unconfined"
keep NET_ADMIN/NET_RAW/--env-file. rebuild container.

### step 2 — verify denial gone (rerun 0915b probes as node)
- unshare --user --map-root-user /bin/true
- bwrap --unshare-user --ro-bind / / /bin/true
- codex sandbox linux /bin/true
ACCEPT = all exit 0.
if still failing: add --cap-add=SYS_ADMIN,SYS_CHROOT,SETUID,SETGID (secure-profile
set), rebuild, re-probe. skip apparmor=unconfined (AppArmor inactive per 0915b)
unless a probe proves otherwise.

### step 3 — make "approve for me" the default
write ~/.codex/config.toml idempotently FROM post-start.sh (volume, not repo;
same pattern as firewall/TeX):
    approval_policy = "on-request"
    sandbox_mode    = "workspace-write"
    # network_access defaults false
plain `codex` then launches sandboxed+network-off; sandbox-setup failure makes
codex refuse, not silently go full-access.

### step 4 — ordinary launchers (symmetry)
add non-yolo gptchat / gptmini in shellrc.sh beside the yolo pair. discoverability;
plain codex already safe after step 3.

### step 5 — firewall interaction
--unshare-net enforces network-off per ordinary command → container firewall NOT
required for ordinary sessions. keep firewall=false normal posture (0915a).
YOLO firewall-gate = SEPARATE task, deferred (not in this plan unless folded in).

### step 6 — document tradeoff
README.md + a journal entry: seccomp=unconfined weakens Docker's outer syscall
filter for ALL container processes (incl. yolo), traded for a working inner
sandbox. accepted posture.

## acceptance tests
- bwrap probes exit 0 (step 2)
- ordinary codex: write under /workspace OK; write outside DENIED; curl blocked
  during a workspace-write command
- gptchat-yolo still works
- test-firewall.sh behavior unchanged

## open decisions (asked, pending)
1. fold in the bigger 0915a YOLO firewall-gate, or keep this plan tight? (rec: tight)
2. config.toml via post-start vs flags-in-aliases? (rec: post-start)

## the tradeoff, stated plainly
seccomp=unconfined removes Docker's outer syscall filter for every process here.
inner bwrap sandbox is restored for ordinary commands, but yolo/full-access
processes lose that outer net too. firewall can't replace a kernel-escape guard.
this is the cost of running codex's real sandbox nested inside Docker.
