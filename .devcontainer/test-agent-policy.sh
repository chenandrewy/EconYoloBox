#!/bin/bash
# ABOUTME: Verifies the baked Claude Code and Codex connector policy is actually
# ABOUTME: in force, rather than merely present on disk.
#
# Run:     test-agent-policy.sh [--warn-only]
# Inputs:  /etc/claude-code/managed-settings.json, /etc/codex/requirements.toml
#          (both baked by the Dockerfile), plus the `claude` and `codex` CLIs.
#          The CLIs are installed at runtime (install-packages.sh cli), so
#          either may legitimately be absent; its checks SKIP rather than fail.
# Output:  PASS/FAIL/SKIP per check on stdout; exit 1 if any check fails
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
skips=0

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

# A CLI that is not installed is not a policy failure: these policies are
# enforced by the CLI reading them, so with no CLI there is nothing to assert.
# The CLIs are installed at runtime (install-packages.sh cli), so a fresh
# npm-global volume legitimately has none. Deliberately NOT a pass - a vacuous
# pass would go green if a broken PATH or a failed install removed the CLI,
# which is exactly the silent-policy-hole this script exists to catch.
skip() {
    echo "SKIP: $1"
    skips=$((skips + 1))
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
    skip "claude CLI not installed; run install-packages.sh cli, then re-run this"
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
    # mentions_v2 rides along with the three connector flags. It is a UX
    # preference, not a security control, but it sits in the same requirements
    # table - so checking it is also how we notice if that table was knocked
    # out of service, which is the failure this script exists to catch.
    for feature in apps plugins remote_plugin mentions_v2; do
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

    # Needed on top of the effective-state loop above: `mentions_v2 = false` may
    # also be sitting in ~/.codex/config.toml, left over from when the seeder
    # set it there. That would make the state check pass without requirements
    # doing any work. Only a refused override proves this file is the control.
    override=$(codex features list --enable mentions_v2 2>/dev/null \
        | awk '$1 == "mentions_v2" { print $NF }')
    if [[ $override == "false" ]]; then
        pass "codex rejects '--enable mentions_v2' override"
    else
        fail "codex '--enable mentions_v2' produced '$override' - requirements NOT enforced"
    fi

    override=$(codex features list -c 'features.plugins=true' 2>/dev/null \
        | awk '$1 == "plugins" { print $NF }')
    if [[ $override == "false" ]]; then
        pass "codex rejects '-c features.plugins=true' override"
    else
        fail "codex '-c features.plugins=true' produced '$override' - requirements NOT enforced"
    fi
else
    skip "codex CLI not installed; run install-packages.sh cli, then re-run this"
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

if ((skips > 0)); then
    # Not "verified for both": say what was actually checked, so an uninstalled
    # CLI cannot be mistaken for a clean bill of health.
    echo "Agent policy verified for the installed CLIs ($skips check(s) skipped)."
    echo "Re-run after install-packages.sh cli to cover the rest."
    exit 0
fi

echo "Agent policy verified: connectors disabled for both Claude and Codex."
