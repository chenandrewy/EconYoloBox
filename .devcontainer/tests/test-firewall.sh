#!/usr/bin/env bash
# Run: bash .devcontainer/tests/test-firewall.sh (inside the YOLO container).
# Inputs: live firewall rules, DNS, and public endpoints listed below.
# Outputs: PASS/FAIL diagnostics; nonzero exit if any network boundary check fails.

set -u

readonly ALLOWED_URL="https://api.github.com/zen"
readonly BLOCKED_URL="https://example.com"
# Package registries are deliberately blocked: the R and Python stacks are
# installed in normie mode, with the firewall off (docs/journal/0925b, 0926e).
readonly BLOCKED_PACKAGE_URLS=(
    "https://pypi.org/simple/"
    "https://packagemanager.posit.co/"
)
# Marketplace/CDN IPs are no longer added to the allowlist. This live probe
# also catches accidental reachability from an IP shared with another host.
readonly BLOCKED_EXTENSION_URLS=(
    "https://marketplace.visualstudio.com/"
    "https://open-vsx.org/"
    "https://ms-python.gallerycdn.vsassets.io/"
)
# Vercel-hosted host allowed via dnsmasq's resolve-time ipset path, not
# start-time pinning; this probe exercises that whole chain (0725e).
readonly VOLATILE_URL="https://developers.openai.com/"
readonly CONNECT_TIMEOUT=5
readonly MAX_TIME=10

failures=0

probe() {
    curl \
        --silent \
        --show-error \
        --output /dev/null \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        "$1"
}

echo "Testing devcontainer firewall..."

if probe "$ALLOWED_URL"; then
    echo "PASS: Allowed destination is reachable: $ALLOWED_URL"
else
    echo "FAIL: Allowed destination is not reachable: $ALLOWED_URL" >&2
    failures=$((failures + 1))
fi

if probe "$BLOCKED_URL"; then
    echo "FAIL: Blocked destination is reachable: $BLOCKED_URL" >&2
    failures=$((failures + 1))
else
    echo "PASS: Blocked destination is not reachable: $BLOCKED_URL"
fi

for url in "${BLOCKED_PACKAGE_URLS[@]}"; do
    if probe "$url"; then
        echo "FAIL: Package registry is reachable: $url" >&2
        failures=$((failures + 1))
    else
        echo "PASS: Package registry is blocked: $url"
    fi
done

for url in "${BLOCKED_EXTENSION_URLS[@]}"; do
    if probe "$url"; then
        echo "FAIL: Extension marketplace/CDN is reachable: $url" >&2
        failures=$((failures + 1))
    else
        echo "PASS: Extension marketplace/CDN is blocked: $url"
    fi
done

if probe "$VOLATILE_URL"; then
    echo "PASS: Volatile (dnsmasq-allowlisted) destination is reachable: $VOLATILE_URL"
else
    echo "FAIL: Volatile destination is not reachable (dnsmasq path broken?): $VOLATILE_URL" >&2
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "Firewall test failed ($failures check(s) failed)." >&2
    exit 1
fi

echo "Firewall test passed."
