#!/bin/bash
# ABOUTME: Prints SANDBOX.toml's package-volume mode, strictly validated.
# ABOUTME: Shared by the macOS host launcher and the container.
#
# Run:     bash .devcontainer/packages-setting.sh [FILE]
# Inputs:  FILE defaults to SANDBOX.toml beside .devcontainer.
# Outputs: readonly or writable on stdout. Invalid, missing, unreadable, or
#          unsupported input warns on stderr and safely resolves to readonly.
#          The rules are strict-setting.sh's.
exec bash "$(dirname "${BASH_SOURCE[0]}")/strict-setting.sh" packages "readonly writable" "$@"
