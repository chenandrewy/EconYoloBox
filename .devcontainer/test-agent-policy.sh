#!/bin/bash
# ABOUTME: Verifies the baked Claude Code and Codex connector policy is actually
# ABOUTME: in force, rather than merely present on disk.
#
# Run:     test-agent-policy.sh [--warn-only]
# Inputs:  /etc/claude-code/managed-settings.json, /etc/codex/requirements.toml
#          (both baked by the Dockerfile), plus the `claude` and `codex` CLIs
# Output:  PASS/FAIL per check on stdout; exit 1 if any check fails
#          --warn-only prints a banner and exits 0, for postStartCommand
#
# Why this exists: both policy files fail *silently*. A key the client does not
# recognize can take the whole policy layer out of service with no error, so a
# file that exists and parses is not evidence that anything is enforced. These
# checks assert observable behavior, including that a deliberate override
# attempt - the documented bypass - is refused.
set -uo pipefail

warn_only=false
[[ ${1:-} == "--warn-only" ]] && warn_only=true

failures=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

# --- Claude Code ------------------------------------------------------------

CLAUDE_POLICY=/etc/claude-code/managed-settings.json

if [[ -f $CLAUDE_POLICY ]]; then
    pass "Claude managed settings present: $CLAUDE_POLICY"

    if python3 -c "
import json, sys
d = json.load(open('$CLAUDE_POLICY'))
sys.exit(0 if d.get('disableClaudeAiConnectors') is True else 1)
" 2>/dev/null; then
        pass "Claude policy parses and sets disableClaudeAiConnectors"
    else
        fail "Claude policy missing/false disableClaudeAiConnectors, or invalid JSON"
    fi

    if python3 -c "
import json, sys
d = json.load(open('$CLAUDE_POLICY'))
urls = {e.get('serverUrl') for e in d.get('deniedMcpServers', [])}
need = {'https://gmailmcp.googleapis.com/*',
        'https://calendarmcp.googleapis.com/*',
        'https://drivemcp.googleapis.com/*'}
sys.exit(0 if need <= urls else 1)
" 2>/dev/null; then
        pass "Claude policy denies the connector URLs (covers --mcp-config)"
    else
        fail "Claude policy is missing one or more connector deny URLs"
    fi
else
    fail "Claude managed settings absent: $CLAUDE_POLICY (rebuild the image)"
fi

# The behavioral check. Connectors must not appear at all.
if command -v claude >/dev/null; then
    if claude_mcp_output=$(claude mcp list 2>&1); then
        if grep -qi "claude\.ai" <<<"$claude_mcp_output"; then
            fail "claude mcp list still shows claude.ai connectors"
        else
            pass "claude mcp list shows no claude.ai connectors"
        fi
    else
        fail "claude mcp list failed; connector state could not be verified: $claude_mcp_output"
    fi
else
    fail "claude CLI not on PATH"
fi

# --- Codex ------------------------------------------------------------------

CODEX_POLICY=/etc/codex/requirements.toml

if [[ -f $CODEX_POLICY ]]; then
    pass "Codex requirements present: $CODEX_POLICY"
    if python3 -c "import tomllib; tomllib.load(open('$CODEX_POLICY','rb'))" 2>/dev/null; then
        pass "Codex requirements parse as TOML"
    else
        fail "Codex requirements are not valid TOML"
    fi
else
    fail "Codex requirements absent: $CODEX_POLICY (rebuild the image)"
fi

# `codex features list` prints: <name> <stage> <effective-state>. The effective
# state is what the requirements layer is supposed to be pinning to false.
feature_state() {
    codex features list 2>/dev/null | awk -v f="$1" '$1 == f { print $NF }'
}

if command -v codex >/dev/null; then
    for feature in apps plugins remote_plugin; do
        state=$(feature_state "$feature")
        if [[ -z $state ]]; then
            fail "codex feature '$feature' not found (flag renamed? update this test)"
        elif [[ $state == "false" ]]; then
            pass "codex feature '$feature' is disabled"
        else
            fail "codex feature '$feature' is '$state', expected false"
        fi
    done

    # The bypass the requirements layer exists to stop. If an explicit override
    # flips the flag, user-level config was never the real control.
    override=$(codex features list --enable plugins 2>/dev/null \
        | awk '$1 == "plugins" { print $NF }')
    if [[ $override == "false" ]]; then
        pass "codex rejects '--enable plugins' override"
    else
        fail "codex '--enable plugins' produced '$override' - requirements NOT enforced"
    fi

    override=$(codex features list -c 'features.plugins=true' 2>/dev/null \
        | awk '$1 == "plugins" { print $NF }')
    if [[ $override == "false" ]]; then
        pass "codex rejects '-c features.plugins=true' override"
    else
        fail "codex '-c features.plugins=true' produced '$override' - requirements NOT enforced"
    fi
else
    fail "codex CLI not on PATH"
fi

# --- Result -----------------------------------------------------------------

if ((failures > 0)); then
    if $warn_only; then
        echo
        echo "############################################################"
        echo "# WARNING: agent connector policy is NOT fully enforced.    "
        echo "# $failures check(s) failed. Mail/calendar access may be    "
        echo "# reachable from this container. Run                        "
        echo "#   test-agent-policy.sh                                    "
        echo "# for detail. Continuing container start.                   "
        echo "############################################################"
        exit 0
    fi
    echo "Agent policy test failed ($failures check(s) failed)." >&2
    exit 1
fi

echo "Agent policy verified: connectors disabled for both Claude and Codex."
