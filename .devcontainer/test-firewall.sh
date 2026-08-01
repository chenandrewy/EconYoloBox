#!/usr/bin/env bash

set -u

readonly ALLOWED_URL="https://api.github.com/zen"
readonly BLOCKED_URL="https://example.com"
# CloudFront-fronted host allowed via dnsmasq's resolve-time ipset path, not
# start-time pinning; this probe exercises that whole chain (0725e).
readonly VOLATILE_URL="https://rspm-sync.rstudio.com/"
readonly JKP_VOLATILE_URL="https://jkpfactors-data.s3.amazonaws.com/public/availability.json"
readonly OPENAI_DOCS_URL="https://developers.openai.com/"
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

if probe "$VOLATILE_URL"; then
    echo "PASS: Volatile (dnsmasq-allowlisted) destination is reachable: $VOLATILE_URL"
else
    echo "FAIL: Volatile destination is not reachable (dnsmasq path broken?): $VOLATILE_URL" >&2
    failures=$((failures + 1))
fi

if probe "$JKP_VOLATILE_URL"; then
    echo "PASS: JKP volatile destination is reachable: $JKP_VOLATILE_URL"
else
    echo "FAIL: JKP volatile destination is not reachable: $JKP_VOLATILE_URL" >&2
    failures=$((failures + 1))
fi

if probe "$OPENAI_DOCS_URL"; then
    echo "PASS: OpenAI developer docs are reachable: $OPENAI_DOCS_URL"
else
    echo "FAIL: OpenAI developer docs are not reachable: $OPENAI_DOCS_URL" >&2
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "Firewall test failed ($failures check(s) failed)." >&2
    exit 1
fi

echo "Firewall test passed."
