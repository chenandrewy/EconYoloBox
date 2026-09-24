# 0922a — slow container launch is VS Code re-provisioning its server + extensions

Notes, 2026-09-22, branch `yolo-default-posture`. Diagnosis from two Dev
Containers launch logs; no code changed yet. Reads as a candidate addition to
[0921a](0921a,BUMP-read-only-package-volumes-plan.md): same "persist it in a
named volume instead of paying to rebuild it" move, one directory that plan
does not cover.

## symptom

Launches feel very slow, and it correlates with weak or unfamiliar wifi. On a
weak connection it looked like a hang; switching to phone hotspot "fixed" it.

## what the logs actually show

- **Log 1 (weak wifi).** Container was *already running* — everything through
  startup is milliseconds. The log then stops dead at
  `Downloading VS Code Server` (`update.code.visualstudio.com/commit:7debcd0e.../server-linux-arm64`).
  So the "hang" was a stalled TLS download of the server tarball, nothing about
  the container.
- **Log 2 (hotspot).** The download finished (~27s) and the rest is a full
  **re-install of all 16 devcontainer extensions**: download + signature
  verify (~2.5–3s each, serialised on CPU) + extract. ~100s total visible.

So the network was never the disease. The disease is that a launch was
re-downloading the whole VS Code server + every extension; a weak link just
turns that from slow into a stall. "Different network" helped only because the
hotspot could finish the transfers.

## root cause

`/home/node/.vscode-server` — server binary **and** all extensions — is **not**
a mounted volume. `devcontainer.json` persists `/opt/venv`, R site-library,
`npm-global`, `.claude`, `.codex`, TeX… but not this. So it survives a restart
(lives in the container's writable layer) yet is rebuilt from zero on container
recreation, and a **VS Code version bump forces it regardless**: the server
`bin/` dir is keyed by commit hash, so a new commit (`7debcd0e`, 1.138.0,
2026-09-15) means fresh server + a re-install pass over the extension list.
Every VS Code auto-update pays this again.

This is exactly the 0921a shape: expensive-to-build software that today gets
rebuilt per container instead of living in a named volume. Not read-only
(extensions get installed into it at first attach, and that is fine), but the
same "put it in a volume so you stop re-fetching it" principle.

## two things in the log worth remembering

- **`EHOSTUNREACH` spam is benign — it is our firewall.**
  `mobile.events.data.microsoft.com` (MS telemetry) and
  `main.vscode-cdn.net/.../marketplace.json` get rejected by
  [init-firewall.sh](../../.devcontainer/init-firewall.sh). `EHOSTUNREACH`
  fails *instantly*, so it costs ~nothing. Worth keeping the firewall on
  *reject* not *drop* — a drop would turn each of these into a multi-second
  timeout instead.
- **Copilot is wasting real time.** `GitHub.copilot` /
  `GitHub.copilot-chat` are listed in `devcontainer.json` `extensions`, but
  they are **built-in** to 1.138 now, so VS Code tries to downgrade
  (`built-in extension with version '0.66.0' ... cannot be downgraded to
  '0.48.1'`), fails, rolls back, retries, re-downloads — the churn from ~47s
  onward. Pure waste; they should come off the list.

## candidate change (fold into 0921a or its own follow-up)

1. **Persist `.vscode-server` in a volume** so a VS Code update stops
   re-installing all 16 extensions. Same keying question as the rest:

   ```
   source=${localWorkspaceFolderBasename}-vscode-server-${devcontainerId},target=/home/node/.vscode-server,type=volume
   ```

   Caveat: the server *binary* is commit-keyed, so it still re-downloads once
   per VS Code version. The win is the extensions (the bulk of log 2) no longer
   re-installing on every recreate/update. Unlike the 0921a trio this one is
   per-devcontainer and writable, so it does not merge into `.setup/packages.sh`
   cleanly — it is a mount addition, not a host-built read-only volume.

2. **Drop `GitHub.copilot` and `GitHub.copilot-chat`** from the `extensions`
   list — built-in now; listing them only creates the retry loop.

3. Habit, not code: don't let VS Code auto-update right before going somewhere
   with weak wifi — the update is what invalidates the cache.

Open: whether persisting `.vscode-server` interacts badly with the
`${devcontainerId}` orphaning story (folder move ⇒ orphaned volume + a fresh
full extension install). Probably acceptable — it self-heals like the others —
but note it before wiring in.
