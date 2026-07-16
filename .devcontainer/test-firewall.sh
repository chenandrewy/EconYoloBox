#!/usr/bin/env bash

set -u

readonly ALLOWED_URL="https://api.github.com/zen"
readonly BLOCKED_URL="https://example.com"
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

if ((failures > 0)); then
    echo "Firewall test failed ($failures check(s) failed)." >&2
    exit 1
fi

echo "Firewall test passed."
