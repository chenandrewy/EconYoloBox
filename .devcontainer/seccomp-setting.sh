#!/bin/bash
# ABOUTME: Prints SANDBOX.toml's seccomp policy, strictly validated.
# ABOUTME: Shared by the macOS host launcher and interactive container shells.
#
# Run:     bash .devcontainer/seccomp-setting.sh [FILE]
# Inputs:  FILE defaults to SANDBOX.toml beside .devcontainer.
# Outputs: builtin or unconfined on stdout. Invalid, missing, unreadable, or
#          unsupported input warns on stderr and safely resolves to builtin.
#          The rules are strict-setting.sh's.
exec bash "$(dirname "${BASH_SOURCE[0]}")/strict-setting.sh" seccomp "builtin unconfined" "$@"
