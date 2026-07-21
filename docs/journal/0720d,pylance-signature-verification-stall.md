# 0720d — Python outline / F12 dead: extension signature verification stalls on blocked OCSP

2026-07-20 (NY)

Context: added `ms-python.python` and `ms-python.vscode-pylance` to
`devcontainer.json` and rebuilt (the rebuild in `0720b`). Python document
outlines and F12 "go to definition" still did nothing. Working hypothesis going
in was that the firewall was blocking something Pylance needed at runtime.

The hypothesis was directionally right — it is the firewall — but wrong about
both the mechanism and the fix. Nothing was blocking Pylance at runtime.

## Symptom, stated precisely

Neither extension was ever installed. Absent from both
`~/.vscode-server/extensions/` and `extensions.json`:

```
anthropic.claude-code-2.1.215-linux-arm64   esbenp.prettier-vscode-12.4.0
donjayamanne.githistory-0.6.20              github.copilot-1.388.0
ikuyadeu.r-pack-0.0.2                       james-yu.latex-workshop-10.16.1
mhutchie.git-graph-1.30.0                   reditorsupport.r-2.8.8
reditorsupport.r-syntax-0.1.4               tomoki1207.pdf-1.2.2
```

No outline and no F12 because Pylance is not there. `dbaeumer.vscode-eslint` is
missing for the same reason — it had been silently absent already.

## What it is *not*: the gallerycdn allowlist

The obvious suspect — a missing `<publisher>.gallerycdn.vsassets.io` entry, the
failure mode `init-firewall.sh:76-79` warns about — is not it. The
`ms-python.gallerycdn.vsassets.io` entry is present and baked into the image.
Verified the actual VSIX downloads with the firewall applied and live:

```
ms-python/vsextensions/python      code=200 size=8615636  time=1.117s
anthropic/vsextensions/claude-code code=200 size=76847670 time=8.092s
```

8.6MB in about a second. The download path is fine. Manifest fetches
(`marketplace.visualstudio.com`) succeeded too — `Getting Manifest...
ms-python.python` is in the log.

## Actual cause: signature verification blocks on revocation checking

From `~/.vscode-server/data/logs/20260720T181248/remoteagent.log`:

```
18:16:44.141 Extension signature verification result for esbenp.prettier-vscode: Success ... Duration: 90521ms
18:16:44.143 Extension signature verification result for ikuyadeu.r-pack:        Success ... Duration: 90516ms
18:16:44.144 Extension signature verification result for reditorsupport.r-syntax: Success ... Duration: 90511ms
18:16:44.181 Extension signature verification result for reditorsupport.r:       Success ... Duration: 90502ms
```

Every extension burns **~90.5 seconds**, and they all complete within
milliseconds of each other at 18:16:44. Uniform duration plus simultaneous
completion is a fixed network timeout, not work. VS Code's VSIX signature check
performs certificate revocation checking, and those endpoints are off the
allowlist. Confirmed under the live firewall:

```
ocsp.digicert.com                   BLOCKED/HANG
crl3.digicert.com                   BLOCKED/HANG
vscode.download.prss.microsoft.com  BLOCKED/HANG
www.microsoft.com                   BLOCKED/HANG
update.code.visualstudio.com        BLOCKED/HANG
```

They **hang** to timeout rather than failing fast, because there is no terminal
`REJECT` rule under the `DROP` policy.

## Timeline — why there is no error in the log

| Time | Event |
|---|---|
| 18:15:13 | Install starts: eslint, `ms-python.python`, pylance, + deps (`vscode-python-envs`, `debugpy`) |
| 18:15:14 → 18:16:44 | First batch sits in the 90s verification timeout, then extracts |
| 18:16:45 | `anthropic.claude-code` extracted — last successful extraction |
| 18:18:36 | Client disconnects **gracefully**; extension host exits code 0 |

The ms-python batch queued behind the first for its own 90-second window and was
still inside it when the window closed. **The installs never failed — they were
still stalled.** That is why the log contains no error for them, which is
exactly what made this look inexplicable. The only errors present are unrelated:
telemetry `ETIMEDOUT` to `mobile.events.data.microsoft.com` (harmless, expected)
and a `github.copilot-chat` built-in downgrade complaint (`0.57.0` vs `0.48.1`,
pre-existing noise).

## Fixes

**Not applied — assessment only.** In order of value:

1. **`"extensions.verifySignature": false`** in
   `devcontainer.json` → `customizations.vscode.settings`. Removes the stall
   outright. Setting name verified present in the installed server binary, not
   assumed. Defensible here: egress is already allowlisted, so marketplace
   signature checking is redundant belt-and-braces against a path that is
   already constrained.
2. **Terminal `iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited`**
   in `init-firewall.sh`. The durable fix. Converts every future blocked call
   from a 90-second silent hang into an immediate failure with a real error.
   Without it, the next blocked host costs another opaque debugging session with
   no log line to grep for. (Already recommended in `0719a` on separate grounds;
   this is independent evidence for the same change.)
3. Allowlisting the OCSP/CRL hosts would also work but is the worst option —
   they are shared DigiCert/Microsoft edges, so it widens allowlist surface
   meaningfully for no gain over fix 1.

Fixes 1 and 2 are complementary, not alternatives: 1 removes this instance, 2
makes the whole class of failure visible.

Once Pylance installs, outlines and F12 need no network — it is a fully local
language server. No further firewall work should be required for the original
goal.

## Diagnostic worth keeping

A `Duration:` figure that is (a) suspiciously round, (b) near-identical across
unrelated items, and (c) shared by a batch that all completes at the same
instant, is a network timeout — regardless of the `Success` next to it. These
lines said `Success`, which is why they read as noise on a first pass.

Corollary: under a `DROP` policy with no `REJECT`, a firewall problem does not
present as an error. It presents as something being slow, or as work that
silently never finished. Absence of an error in the log is not evidence the
firewall is innocent.
