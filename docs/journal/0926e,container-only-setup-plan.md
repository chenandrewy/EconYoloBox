# 0926e — plan: both .setup/ scripts run only in the container

2026-09-26, branch `feature/package-install-modes`. Replaces the host half of
[0926d](0926d,package-scripts-reorg-plan.md) (implemented in `299552a`); the
folder moves and reference updates from 0926d stay. Not started.

## why

0926d made `install-base.sh` two scripts in one file: a host driver that runs
itself in a throwaway root container, and the in-container installer. That
costs a `/.dockerenv` dispatch, a bash 3.2 constraint on the whole file, Docker
lookups for the image and the CLI volume, `dc-resolve.py package-volumes`, and
the `// install-base.sh:` staging directive.

The optional set already installs from inside, as node, in normie mode. If the
base does too, both scripts work the same way, and the rule is one sentence:
packages change only in normie mode, from inside.

Trade accepted: a base change is no longer one host command with the container
left in YOLO mode. It takes a normie round trip (rebuild, install, rebuild
back). Base changes are rare. First setup gets shorter: today it is host build,
normie rebuild, optional, YOLO rebuild; after, normie rebuild, base (+
optional), YOLO rebuild.

0921a's "agents only execute; the human maintains" still holds: the human
opens normie mode and watches. It no longer means "from the host".

## security (settled in conversation)

Node ownership of the package folders is not a new exposure: the volumes have
been node-owned (755) since 0926b, because `packages.sh` chowned them. The
read-only mount is the protection. The kernel refuses every write on it
whatever the owner; node has no effective capabilities, `CAP_SYS_ADMIN` is not
in the bounding set, and node's only sudo rule is `init-firewall.sh`, so it
cannot remount. Writable only when `packages = "writable"` reaches
`devcontainer up`; anything else falls back to read-only. Root ownership would
add a second layer only against an accidental writable mount, and would break
normie mode. The real exposure is sharing: a normie container of one checkout
can change what a YOLO container of another runs. Unchanged by this plan.

## steps

- [x] 1. Dockerfile: create `/usr/local/texlive` (else Docker makes the mount
  point root-owned) and hand it, `/opt/venv` and the R site library to node,
  so fresh volumes are seeded node-owned. Existing volumes already are.
- [x] 2. `install-base.sh`: remove the host driver; refuse outside a container.
  `python`, `r`, `tex` require normie mode, with `install-optional.sh`'s
  check copied in (node; mounts writable and node-owned; firewall open), and
  the refusal says `cli` works now. `cli` needs only its mount; `--verify`
  works anywhere. TeX runs as node, keeping the smoke test's private LyX
  userdir.
- [x] 3. Remove `dc-resolve.py package-volumes` and the staging directive. A
  new volume is tried by renaming it in `devcontainer.json` and rebuilding.
- [x] 4. Messages and docs: "on the host run: bash .setup/install-base.sh X"
  becomes "in normie mode, in the container: ..." (post-start, shellrc,
  tex-refresh, both scripts); READMEs, features, agent guidance and comments
  drop host building. `.setup/README.md` states the one first-setup and
  version-bump procedure: normie mode, `bbox --rebuild`, `install-base.sh`,
  optionally `install-optional.sh`, YOLO mode, `bbox --rebuild`,
  `test-packages.sh`. Journals keep old text.

## checks

- [x] 5. YOLO mode: `install-base.sh python` refuses; `cli` and `--verify`
  work; on the host it refuses; `test-packages.sh` passes (closes 0926d
  step 11). Plus `test-optional.sh`, `test-seccomp.sh`,
  `test-agent-policy.sh`, shellcheck, `test-bbox.zsh`, `test-setup.py`.
- [ ] 6. (later) Fresh volumes from empty, in normie mode: temporary volume names in
  `devcontainer.json`, `bbox --rebuild`, mounts node-owned, `install-base.sh`,
  `test-packages.sh`. Revert and remove the temporary volumes.

## log

- Steps 1–4 implemented. `install-base.sh` checks normie mode for all of
  python/r/tex up front, so a refusal writes nothing; the check also requires
  the mounts to be node-owned (install-optional.sh only checks writable), and
  its message points to a new "Volume ownership" section in `.setup/README.md`
  with the one-off host chown for a pre-0926e volume. A tex install ends by
  running `tex-refresh`. `test-packages.sh` now also asserts the YOLO refusal
  points to `cli`.
- Check 5 (YOLO, this container, image not yet rebuilt): `install-base.sh
  python` and the default target refuse; the host refusal was exercised by
  disabling the container markers in a copy; `--verify` passes;
  `test-packages.sh`, `test-optional.sh`, `test-seccomp.sh`,
  `test-agent-policy.sh`, `test-bbox.zsh` and `test-setup.py` pass;
  shellcheck is clean on the changed scripts (its remaining warnings, in
  `init-firewall.sh`, `shellrc.sh` and `ai-sesh/_common.sh`, predate this).
  Not run: `install-base.sh cli` for real (it would update both CLIs), and the
  Dockerfile change, which needs `bbox --rebuild`.
- Check 6 needs normie mode and the host; not started.

## not in this plan

- The stale-`bbox` guard (see 0926d). Still pending a yes.
- npm's `allowScripts` warning for claude-code's postinstall (see 0926d log).
