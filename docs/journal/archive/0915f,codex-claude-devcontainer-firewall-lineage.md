# 0915f — Codex removal and the shared Claude devcontainer firewall limits

2026-09-15 (NY). Follow-up to [0915c]. Web and repository review only; no
firewall, container, or configuration changes in this investigation.

## Bottom line

OpenAI removed its contributor and "secure" devcontainer configurations on
2026-09-08, three weeks after explicitly documenting that the secure profile
could exfiltrate through DNS and allowed HTTPS destinations. The public removal
PR gives no reason, so security as the cause remains an inference.

The more important finding for this repository is not new: OpenAI's retired
firewall had substantially the same design and limitations as Anthropic's still
published Claude Code reference devcontainer, from which our firewall descends.
Our July investigations had already documented the central holes: arbitrary DNS
and SSH egress, an open Docker bridge subnet, IP-level allowlisting against
shared services, stale address snapshots, and persistent credentials inside the
container. OpenAI's sequence independently confirms that this design should be
described as useful egress reduction, not containment of adversarial code.

## Codex repository timeline

### 2026-02-02 through 2026-04-11 — secure profile proposed and merged

OpenAI PR [#10431] added a separate, opt-in "secure customer profile." The PR
described `devcontainer.secure.json` as the customer-facing option and advertised
an allowlist-driven outbound firewall, IPv6 blocking, persistent Codex/GitHub
state, and Bubblewrap support. It was developed from February and merged on
April 11 as commit `dbfe855f4`.

The security defects were visible before merge. On April 11, Codex's automated
review made two relevant findings on `init-firewall.sh`:

1. Allowing outbound TCP/UDP port 53 to any destination creates an unfiltered
   channel that bypasses the domain allowlist. The review recommended limiting
   DNS to Docker's resolver or explicitly trusted resolvers.
2. Allowing the entire `/24` around the Docker gateway permits access to peer
   containers that could relay traffic around the allowlist.

The merged script retained both rules. Thus the August change below was not the
first discovery of the DNS weakness; it was the first explicit documentation of
a weakness identified during the original review.

### 2026-04-20 through 2026-05-17 — related defects reported

- Issue [#18674] reported that resolving allowed domains once and retaining the
  addresses indefinitely ignored DNS TTLs, created a stale-address/reassignment
  problem, and broke legitimate access after address rotation. It proposed a
  TTL-aware or DNS-integrated design. The issue was closed without a linked fix.
- Issue [#22471] reported that CNAME records in `dig` output made the secure
  devcontainer abort during startup. A user supplied a minimal filter for IPv4
  answers, but the issue remained open when reviewed.
- The older issue [#2454] already illustrated the operational version of the
  same architecture problem: Cloudflare address rotation made an apparently
  allowed Codex endpoint unreachable because the active address was not in the
  startup snapshot.

### 2026-08-18 — warning added

PR [#39283], commit `2fe4e06cc2`, changed only documentation. It stated that the
firewall did not apply its domain allowlist to DNS traffic, did not provide
secure DNS resolution for untrusted code, and should be used only with trusted
repositories. It called a restricted DNS resolver only a partial mitigation and
also acknowledged that allowed HTTPS destinations remain exfiltration paths.
The PR had no human review.

### 2026-09-08 — all repository devcontainers removed

PR [#43915], commit `f419c3214`, deleted the full `.devcontainer/` tree: the
ordinary contributor profile, the secure customer profile, both Dockerfiles,
the firewall and setup scripts, documentation, and locked installation files.
It also removed the Dependabot devcontainer entry and related ignore rules: 718
lines across 13 files. The last parent containing the tree is
`900b1e4cec1c4eada106a8071fc89c11c50de9a6` ([archived tree]).

The public PR says what was removed but not why. GitHub presents `copyberry` as
the bot author/merger, while the commit metadata names OpenAI employee Adam
Perry as author and includes an internal `GitOrigin-RevId`. The public PR is an
automated mirror of an internal OpenAI change; the public record therefore does
not contain the internal rationale.

The timing supports, but does not prove, the inference in [0915c] that OpenAI
retired a profile whose "secure" name could overstate what it protected. A
competing explanation is ordinary maintenance-surface reduction, especially
because the deletion also removed the unrelated contributor profile.

### 2026-09-15 — official documentation still stale

The [OpenAI agent security documentation] still links the deleted repository
path, calls the secure devcontainer a reference implementation, tells users to
select `devcontainer.secure.json`, and names three files that no longer exist on
`main`. It does warn that malicious projects may exfiltrate anything available
inside the container and limits the pattern to trusted repositories. The page
and repository nevertheless disagree about whether the example exists.

## Same design in the Claude Code reference

Anthropic's current [development-container documentation] and [reference
firewall] still publish the design from which our configuration originated.
The major limits match the retired Codex profile:

| Limit | Claude Code reference | Retired Codex profile | This repository |
| --- | --- | --- | --- |
| Arbitrary DNS egress | UDP/53 to any destination | TCP and UDP/53 to any destination | Still present |
| Arbitrary SSH egress | TCP/22 to any destination | No equivalent blanket rule in the final profile reviewed | Still present |
| Docker subnet access | Entire gateway `/24` allowed | Entire gateway `/24` allowed | Still present |
| Address identity | Domains resolved into an IPv4 `ipset` | Domains resolved into an IPv4 `ipset` | Mixed static sets, broad ranges, and dnsmasq-populated volatile set |
| Address refresh | One startup snapshot | One startup snapshot | Improved for selected volatile domains; not a complete hostname boundary |
| IPv6 | No visible IPv6 default-deny in current script | Explicit IPv6 default-deny | Must be verified with the live firewall |
| Firewall location | Workload container with `NET_ADMIN`/`NET_RAW` | Workload container with `NET_ADMIN`/`NET_RAW` | Workload container with `NET_ADMIN`/`NET_RAW` |
| Stored agent credentials | Persistent `~/.claude` volume | Persistent `.codex` volume and GitHub state | Persistent Claude and Codex state |
| Allowed services as sinks | GitHub, npm, Anthropic, telemetry, VS Code infrastructure | OpenAI, GitHub, registries, package services | Those plus broad research and Google destinations |

Anthropic now describes the reference as a working example rather than a
maintained base image. Its docs explicitly say that a malicious project can
exfiltrate anything accessible in the container, including Claude credentials;
recommend trusted repositories only; and invite users to omit the network
capabilities and use their own controls. That warning is accurate. The included
firewall limits casual or opportunistic outbound traffic, but is not a boundary
against code assumed hostile inside the workload.

Reddit discussions reflect the same conclusion. One user reports Claude editing
the rules in Anthropic's reference container during an unrestricted session
([reported firewall rewrite]); treat this as anecdote, not controlled evidence.
The [o3s discussion] explains the stronger architecture: put the firewall in a
separate gateway namespace the agent cannot administer, force DNS through a
controlled resolver, restrict host and port together, and accept that even this
cannot prevent exfiltration through an intentionally allowed service. A recent
[Codex Docker sandbox discussion] independently adopts the same external-proxy,
no-external-DNS design.

## What our earlier journal had already established

This investigation mostly joins facts that were previously spread across the
journal:

- [0715a] found our inherited pre-fix Anthropic firewall silently disappeared
  after container restart and could fail open during setup. It traced the
  lineage to a mid-2025 Claude reference configuration. Later work moved setup
  to `postStartCommand`, waited for completion, added an explicit terminal
  reject, and added fail-closed behavior.
- [0719a] is the direct prior analysis. It lists unrestricted SSH, unrestricted
  DNS, stateless inbound rules, the whole Docker `/24`, and `NET_RAW`, and
  records that holes 1–4 were inherited verbatim from Anthropic.
- [0720c] documents why one-shot DNS-to-IP pinning fails on rotating CDNs and
  proposes resolve-time `dnsmasq` population or a hostname-aware proxy.
- [0724b] demonstrates that IP allowlisting cannot separate Google Scholar from
  Forms, Drive, or Storage because they share front-end address space. It also
  records our narrower privilege model: the node user may run only the
  root-owned installed firewall script through passwordless sudo; the editable
  workspace source is inert until rebuild.
- [0724d] records the deliberate acceptance of Google first-party ranges for
  this research environment despite the programmable exfiltration sinks.
- [0725e] and [0726a] implement and preserve the `dnsmasq` resolve-time path for
  volatile hosts. This improves reachability and address freshness but does not
  filter arbitrary DNS queries or provide application-level hostname policy.
- [0821c] states the enduring threat model correctly: the firewall blocks a bad
  dependency phoning home to a random server, but it does not stop a determined
  attacker, and upstream provenance is not evidence that a design was checked.
- [0915a] and [0915b] carry these limits into the current Codex/Bubblewrap and
  YOLO analysis: broad ranges, DNS/SSH, host-subnet access, existing connections,
  and live-state verification all matter. The firewall cannot substitute for a
  filesystem or kernel sandbox.
- [0915c] records the initial discovery of OpenAI's deletion. This entry adds
  the earlier April review findings, user issue history, Claude comparison, and
  the distinction between public evidence and the inferred reason for removal.

## Current interpretation

The right claim for this sandbox remains the one already reached in July:

> The firewall meaningfully reduces accidental and commodity outbound access.
> It does not make an untrusted repository safe and does not guarantee that a
> determined process cannot exfiltrate data available inside the container.

A materially stronger egress boundary would live outside the workload
container, deny direct external DNS and private/local networks, enforce names
and ports at a proxy or controlled resolver, and keep the workload from
administering the boundary. Even then, every allowed programmable destination
must be treated as a possible data sink. That is a separate redesign, not a
small patch to the current `iptables` script.

## Why the reference firewalls allow outbound port 53

The rule exists because normal programs must resolve names after the firewall
changes the default output policy to `DROP`. The configured allowlist starts as
names such as `api.anthropic.com` and `registry.npmjs.org`, while `iptables`
ultimately permits addresses. DNS is therefore needed both while the firewall
initializes its `ipset` and later when ordinary applications connect or CDN
answers change.

UDP/53 carries most DNS queries. TCP/53 handles protocol fallback, including
truncated or unusually large responses. Anthropic's current reference permits
arbitrary UDP/53; OpenAI's retired profile permitted arbitrary UDP and TCP/53.
OpenAI's version was more complete as DNS plumbing, but both leave an outbound
data channel.

Permitting port 53 to every address was probably a portability shortcut. A
container may use Docker's embedded resolver at `127.0.0.11`, a resolver from
`/etc/resolv.conf`, a corporate/VPN resolver, or runtime-specific DNS and NAT
arrangements. A blanket destination-independent rule works across those cases
without parsing resolver configuration or reasoning about Docker's translated
upstream traffic.

The security mistake is treating DNS as harmless infrastructure. A hostile
process can encode data in a query such as
`<encoded-secret>.attacker-controlled.example`; the attacker's authoritative
DNS server then observes the label. Because the rule permits arbitrary
destinations, code can also bypass Docker's resolver and query an
attacker-operated resolver directly. The policy blocks ordinary HTTP callbacks
to unknown servers while retaining a lower-bandwidth exfiltration route.

Restricting port 53 to the configured resolver is a useful first improvement,
but it prevents only direct queries to arbitrary resolvers. A recursive resolver
will still forward a query for an attacker-controlled domain. Closing that path
requires an allowlist-aware resolver that refuses names outside policy, together
with rules that block every alternative resolver and direct-IP route. The
strongest practical arrangement puts that resolver and the egress enforcement
outside the workload container so the agent cannot administer either boundary.

This repository's `dnsmasq` path solves a narrower problem: it refreshes the
addresses of selected approved names and populates `allowed-volatile` at lookup
time. It improves CDN reachability and address freshness. Because arbitrary
outbound UDP/53 remains allowed and `dnsmasq` does not refuse every unapproved
name, it does not close the inherited DNS-exfiltration channel.

[0715a]: archive/0715a,firewall-fails-open.md
[0719a]: archive/0719a,firewall-holes.md
[0720c]: archive/0720c,extension-install-blocked.md
[0724b]: archive/0724b,firewall-exfil-risk.md
[0724d]: archive/0724d,google-firewall-open.md
[0725e]: archive/0725e,rspm-cdn-rotation.md
[0726a]: archive/0726a,ubuntu-base-migrated.md
[0821c]: archive/0821c,lessons-learned.md
[0915a]: 0915a,codex-nested-sandbox-investigation.md
[0915b]: 0915b,codex-nested-sandbox-runtime-evidence.md
[0915c]: 0915c,codex-devcontainer-removed-upstream.md
[#10431]: https://github.com/openai/codex/pull/10431
[#18674]: https://github.com/openai/codex/issues/18674
[#22471]: https://github.com/openai/codex/issues/22471
[#2454]: https://github.com/openai/codex/issues/2454
[#39283]: https://github.com/openai/codex/pull/39283
[#43915]: https://github.com/openai/codex/pull/43915
[archived tree]: https://github.com/openai/codex/tree/900b1e4cec1c4eada106a8071fc89c11c50de9a6/.devcontainer
[OpenAI agent security documentation]: https://learn.chatgpt.com/docs/agent-approvals-security#run-codex-in-dev-containers
[development-container documentation]: https://code.claude.com/docs/en/devcontainer
[reference firewall]: https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
[reported firewall rewrite]: https://www.reddit.com/r/ClaudeCode/comments/1qr10r3/trying_to_introduce_cc_at_work_but_security_says/
[o3s discussion]: https://www.reddit.com/r/ClaudeCode/comments/1v7f8zk/ever_nervous_running_claude_code_on_your_machine/
[Codex Docker sandbox discussion]: https://www.reddit.com/r/codex/comments/1vat9np/docker_sandbox_for_codex_cli_with_one_mounted/
