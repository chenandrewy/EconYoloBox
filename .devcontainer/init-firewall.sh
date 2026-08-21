#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# NOT re-runnable: this script only takes a container from clean (fresh netns,
# ACCEPT policies) to armed, once per container lifetime. A mid-session re-run
# inherits the DROP policies of the previous run - iptables -F flushes rules
# but not policies - so its own bootstrap fetches (GitHub meta, goog.json) get
# blackholed before any ACCEPT rule exists, and the fail-closed trap then cuts
# the whole container off. Refuse instead; a restart re-runs this via
# postStartCommand from a clean state. Exit 0 so launcher chains that hit an
# already-armed container don't abort.
if iptables -S OUTPUT | grep -q '^-P OUTPUT DROP'; then
    echo "Firewall already armed (OUTPUT policy is DROP) - refusing to re-run." >&2
    echo "To re-arm or apply changes, restart the container." >&2
    exit 0
fi

# Fail closed: everything below flushes the rules before rebuilding them, so a
# mid-script failure would otherwise leave the container wide open (default ACCEPT)
trap 'status=$?; if [ "$status" -ne 0 ]; then
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP
    echo "ERROR: firewall setup failed (exit $status) - default policies set to DROP" >&2
fi' EXIT

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# dnsmasq (started at the end of this script) owns DNS once set up. Kill any
# previous instance, and point resolv.conf back at the real upstream so this
# script's own dig/curl calls still resolve; the stash is written by the
# dnsmasq block below on first run.
UPSTREAM_STASH=/etc/dnsmasq-upstream.conf
pkill -x dnsmasq 2>/dev/null || true
if [ -s "$UPSTREAM_STASH" ] && grep -q '^nameserver 127\.0\.0\.1$' /etc/resolv.conf; then
    sed 's/^server=/nameserver /' "$UPSTREAM_STASH" > /etc/resolv.conf
fi
ipset destroy allowed-volatile 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Create ipset with CIDR support
ipset create allowed-domains hash:net

# Volatile set: populated at resolve time by dnsmasq's ipset= directive, for
# CDN-fronted hosts whose IPs rotate faster than start-time pinning can track.
ipset create allowed-volatile hash:ip

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Fetch Google's published first-party IP ranges the same way.
#
# goog.json ONLY - never cloud.json. cloud.json is GCP *customer* space
# (arbitrary rented VMs), i.e. a rent-a-C2 endpoint surface; goog.json is
# Google's own fleet. That boundary is what keeps this defensible.
#
# Allowing the published ranges self-heals across Google's anycast rotations
# instead of needing hand-patched CIDRs. Knowingly accepted: the fleet is routed
# by SNI, so allowing any Google host necessarily allows Docs/Drive/Forms -
# programmable first-party sinks that can relay data out. That trade is
# deliberate: the alternative is hand-patching CIDRs that rotate underneath you.
echo "Fetching Google IP ranges..."
goog_ranges=$(curl -s https://www.gstatic.com/ipranges/goog.json)
if [ -z "$goog_ranges" ]; then
    echo "ERROR: Failed to fetch Google IP ranges"
    exit 1
fi

if ! echo "$goog_ranges" | jq -e '.prefixes | length > 0' >/dev/null; then
    echo "ERROR: Google ipranges response missing prefixes"
    exit 1
fi

echo "Processing Google IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from goog.json: $cidr"
        exit 1
    fi
    echo "Adding Google range $cidr"
    ipset add allowed-domains "$cidr" -exist
done < <(echo "$goog_ranges" | jq -r '.prefixes[].ipv4Prefix | select(. != null)' | aggregate -q)

# Resolve and add other allowed domains.
# The *.gallerycdn.vsassets.io entries are the per-publisher VS Code extension
# download CDN: one entry per publisher in devcontainer.json "extensions".
# Adding an extension from a new publisher requires a new entry here, or its
# install will silently fail inside the container.
#
# Two hosts serve runtime R installs (install-packages.sh):
#   cran.r-project.org    - archived-source tarballs (pryr), which P3M does not
#     carry. Only touched by the explicit archive pin.
#   rspm-sync.rstudio.com - P3M's package payload host - is NOT pinned here: it
#     is CloudFront and rotates IPs on a minutes timescale, so start-time
#     pinning cannot hold it. It goes through dnsmasq's
#     resolve-time VOLATILE_DOMAINS path at the end of this script instead.
#
# Six hosts were removed here at the Ubuntu base migration (0725g):
# www/dlcdn/archive/nightlies.apache.org, zlib.net, and sourceware.org existed
# only to feed arrow's C++ source build, and that build happened only because
# P3M ships no arm64 binaries for Debian. It ships them for noble, so arrow now
# arrives prebuilt with libarrow already inside, over the ordinary rspm-sync
# path. If a source build ever resurfaces, rediscover the host list from
# cpp/thirdparty/versions.txt in the arrow tarball - everything else there is
# github.com. (apache.jfrog.io stays in VOLATILE_DOMAINS below: it serves a
# *prebuilt* libarrow, so it is the cheap fallback that avoids the C++ build
# rather than part of it.)
#
# Expect more redirect hosts to surface: a redirect chain to an unlisted host is
# invisible to inspection, so this list is permanently reactive. A host whose
# answers rotate belongs in VOLATILE_DOMAINS, not here.
for domain in \
    "registry.npmjs.org" \
    "marketplace.visualstudio.com" \
    "open-vsx.org" \
    "ms-vscode.gallery.vsassets.io" \
    "anthropic.gallerycdn.vsassets.io" \
    "github.gallerycdn.vsassets.io" \
    "dbaeumer.gallerycdn.vsassets.io" \
    "esbenp.gallerycdn.vsassets.io" \
    "tomoki1207.gallerycdn.vsassets.io" \
    "james-yu.gallerycdn.vsassets.io" \
    "donjayamanne.gallerycdn.vsassets.io" \
    "mhutchie.gallerycdn.vsassets.io" \
    "ms-python.gallerycdn.vsassets.io" \
    "ikuyadeu.gallerycdn.vsassets.io" \
    "reditorsupport.gallerycdn.vsassets.io" \
    "chenandrewy.gallerycdn.vsassets.io" \
    "copilot-proxy.githubusercontent.com" \
    "origin-tracker.githubusercontent.com" \
    "copilot-telemetry.githubusercontent.com" \
    "collector.github.com" \
    "default.exp-tas.com" \
    "githubcopilot.com" \
    "api.githubcopilot.com" \
    "auth.openai.com" \
    "api.openai.com" \
    "api.openalex.org" \
    "openrouter.ai" \
    "chatgpt.com" \
    "ab.chatgpt.com" \
    "chat.openai.com" \
    "api.anthropic.com" \
    "sentry.io" \
    "wrds-pgdata.wharton.upenn.edu" \
    "ssrn.com" \
    "www.ssrn.com" \
    "papers.ssrn.com" \
    "arxiv.org" \
    "www.arxiv.org" \
    "export.arxiv.org" \
    "api.mistral.ai" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "packagemanager.posit.co" \
    "cran.r-project.org" \
    "api.stlouisfed.org" \
    "fred.stlouisfed.org" \
    "mba.tuck.dartmouth.edu" \
    "global-q.org"; do
    echo "Resolving $domain..."
    ips=$(dig +short A "$domain" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip" -exist
    done < <(echo "$ips")
done

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-volatile dst -j ACCEPT

# Reject everything else explicitly so blocked calls fail immediately instead
# of hanging until their network timeout under the default DROP policy.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

# --- Resolve-time allowlisting via dnsmasq ---
# CDN-fronted hosts rotate IPs faster than the start-time pinning above can
# track. dnsmasq's ipset= inserts every address it resolves for these names
# into allowed-volatile BEFORE answering the client, so the connection that
# follows is allowed by construction.
#
# resolv.conf is cut over to 127.0.0.1 only after dnsmasq provably works, so
# every failure path here leaves the container with working DNS and only the
# volatile hosts unreachable. None of these failures should trip the EXIT trap
# into DROP - the firewall itself is fine.
# apache.jfrog.io: first host arrow's nixlibs.R tries for a prebuilt libarrow.
# AWS load balancer with a ~73s TTL, so it needs the resolve-time path.
# jkpfactors-data.s3.amazonaws.com: Amazon S3 endpoint whose answers rotate,
# so start-time IP pinning becomes stale.
# developers.openai.com: Vercel-hosted OpenAI documentation and Docs MCP;
# resolve-time allowlisting accommodates changes to its edge addresses.
VOLATILE_DOMAINS=(
    "rspm-sync.rstudio.com"
    "apache.jfrog.io"
    "jkpfactors-data.s3.amazonaws.com"
    "developers.openai.com"
)

if ! command -v dnsmasq >/dev/null; then
    echo "WARNING: dnsmasq not installed (image predates it) - skipping resolver setup." >&2
    echo "WARNING: R installs from P3M will fail until the container is rebuilt." >&2
else
    # Harvest the real upstream once. On re-runs resolv.conf already points at
    # dnsmasq itself, and forwarding to ourselves would loop; the teardown at
    # the top restored it, but guard anyway.
    if ! grep -q '^nameserver 127\.0\.0\.1$' /etc/resolv.conf; then
        grep '^nameserver' /etc/resolv.conf | sed 's/^nameserver /server=/' > "$UPSTREAM_STASH" || true
    fi
    if [ ! -s "$UPSTREAM_STASH" ]; then
        echo "WARNING: no upstream nameserver found in /etc/resolv.conf - skipping dnsmasq setup." >&2
    else
        {
            echo "no-resolv"
            cat "$UPSTREAM_STASH"
            echo "listen-address=127.0.0.1"
            echo "bind-interfaces"
            echo "pid-file=/run/dnsmasq-firewall.pid"
            echo "log-facility=/var/log/dnsmasq-firewall.log"
            for domain in "${VOLATILE_DOMAINS[@]}"; do
                echo "ipset=/$domain/allowed-volatile"
            done
        } > /etc/dnsmasq-firewall.conf

        dnsmasq_ok=false
        if dnsmasq --conf-file=/etc/dnsmasq-firewall.conf; then
            # End-to-end check: a generic name resolves, a volatile name
            # resolves, and the volatile answer landed in the ipset.
            rspm_ip=$(dig +short +time=2 @127.0.0.1 A "${VOLATILE_DOMAINS[0]}" \
                | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1 || true)
            if dig +short +time=2 @127.0.0.1 A api.github.com | grep -qE '^[0-9]' \
                && [ -n "$rspm_ip" ] && ipset test allowed-volatile "$rspm_ip" 2>/dev/null; then
                dnsmasq_ok=true
            fi
        fi

        if [ "$dnsmasq_ok" = true ]; then
            echo "nameserver 127.0.0.1" > /etc/resolv.conf
            echo "dnsmasq resolver active - volatile domains: ${VOLATILE_DOMAINS[*]}"
        else
            sed 's/^server=/nameserver /' "$UPSTREAM_STASH" > /etc/resolv.conf
            pkill -x dnsmasq 2>/dev/null || true
            echo "WARNING: dnsmasq verification failed - resolver left at upstream." >&2
            echo "WARNING: R installs from P3M will fail; fix and restart the container." >&2
        fi
    fi
fi
