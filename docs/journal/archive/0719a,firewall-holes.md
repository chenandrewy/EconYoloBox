# 0719a — Firewall holes in the devcontainer sandbox

2026-07-19 (NY)

Context: tightening the sandbox. Removed the persistent `gh-config` volume from
`devcontainer.json` (commit pending), so GitHub credentials no longer survive
container rebuilds. Reviewed the rest of the setup for holes. The `~/.claude`
and `~/.codex` volumes are **intended to persist** — agent logins survive
rebuilds by design; the sandbox story is "agent credentials persist, GitHub
credentials don't."

## Holes found in `init-firewall.sh` (priority order)

1. **Outbound SSH to anywhere** (`init-firewall.sh:42`). Blanket
   `-p tcp --dport 22 -j ACCEPT` to any IP. Full exfiltration/tunnel channel
   (`ssh -D`, `scp` to arbitrary hosts) that bypasses the allowlist entirely.
   GitHub-over-SSH doesn't need it: the ipset already contains GitHub's `.git`
   IP ranges from `api.github.com/meta`. The rule can just be deleted.
2. **Outbound DNS to anywhere** (`init-firewall.sh:38`). UDP 53 to any IP =
   classic DNS-tunneling channel (iodine etc.). Fix: restrict to Docker's
   embedded DNS at 127.0.0.11 (whose NAT rules the script already preserves)
   or the resolvers in `/etc/resolv.conf`.
3. **Stateless inbound accepts** (`init-firewall.sh:40,44`). Any inbound UDP
   packet with *source port* 53 is accepted from anywhere, no conntrack; same
   idea for the sport-22 rule. The `ESTABLISHED,RELATED` rule (line 161)
   already admits real replies, so both rules can go.
4. **Whole host /24 open both directions** (`init-firewall.sh:152-153`).
   Opens the entire bridge subnet — other containers and host-published
   services, inbound as well as outbound. Before narrowing to `$HOST_IP`
   (or removing), check what actually talks to the host network.
5. **`NET_RAW` capability** (`devcontainer.json` runArgs). iptables/ipset only
   need `NET_ADMIN`; `NET_RAW` is basically for `ping`/raw sockets. Try a
   rebuild without it.

## Upstream comparison (anthropics/claude-code)

Checked the reference `.devcontainer/init-firewall.sh` on current main
(2026-07-19; file last modified 2025-08-27, commit `07e13937`). All of holes
1-4 are inherited verbatim from upstream, and the reference also passes both
`NET_ADMIN` and `NET_RAW` (hole 5). So these are upstream usability tradeoffs,
not something our fork introduced — and fixing them is a deliberate divergence;
don't let a future "sync with reference" pass reintroduce them.

One thing upstream has that we lack: an explicit final
`iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited`, so blocked
connections fail fast instead of hanging until timeout under the DROP policy.
Worth adopting when fixing the holes.

## Known limits, accepted for now

- API keys (WRDS, Mistral, OpenRouter, OpenAlex) arrive as container-wide env
  vars — visible to every process. Alternative (per-use secrets file or
  libsecret keyring) is a workflow change; conscious tradeoff.
- Allowlist is IP-based against shared CDNs (`*.gallerycdn.vsassets.io`,
  `sentry.io`, `chatgpt.com` are Azure/Cloudflare edges), so those IPs admit
  whatever else the edge serves; one-shot `dig` also goes stale. Hostname-level
  egress control needs a filtering proxy — bigger project.
- Brief unfiltered-network window between container start and
  `postStartCommand` applying the firewall.

## Related cleanup

- `Dockerfile` no longer needs to pre-create `/home/node/.config/gh` (was only
  there so the removed volume mount wouldn't be created root-owned). Fixed.
