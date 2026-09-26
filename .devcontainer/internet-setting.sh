#!/bin/bash
# ABOUTME: Reads the container internet mode, defaulting safely to firewalled.
#
# Run:     bash .devcontainer/internet-setting.sh [SANDBOX.toml]
# Inputs:  SANDBOX.toml (or the optional path), with internet = "firewalled" or "open".
# Outputs: one validated mode on stdout; a warning on stderr for invalid input.
exec bash "$(dirname "${BASH_SOURCE[0]}")/strict-setting.sh" internet 'firewalled open' "$@"
