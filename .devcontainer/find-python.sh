#!/usr/bin/env bash
# ABOUTME: Cross-platform Python finder for devcontainer initializeCommand.
# ABOUTME: Finds a working Python 3 interpreter on macOS, Linux, or Windows (Git Bash).
#
# Run:     source .devcontainer/find-python.sh  (sets PYTHON variable)
# Inputs:  None
# Outputs: PYTHON env var pointing to a working Python 3 interpreter

PYTHON=""

for candidate in python3 python py; do
    if command -v "$candidate" > /dev/null 2>&1; then
        PYTHON="$candidate"
        break
    fi
done

# Windows Anaconda: common install locations when not on PATH
if [ -z "$PYTHON" ] && [ "$(uname -s | cut -c1-5)" = "MINGW" ] || [ "$(uname -s | cut -c1-4)" = "MSYS" ]; then
    for anaconda_dir in \
        "$LOCALAPPDATA/anaconda3" \
        "$USERPROFILE/anaconda3" \
        "$LOCALAPPDATA/miniconda3" \
        "$USERPROFILE/miniconda3" \
        "$APPDATA/anaconda3" \
        "$PROGRAMDATA/anaconda3"; do
        if [ -x "$anaconda_dir/python.exe" ]; then
            PYTHON="$anaconda_dir/python.exe"
            break
        fi
    done
fi

if [ -z "$PYTHON" ]; then
    echo "Error: Could not find Python. Install Python 3 or add it to PATH." >&2
    exit 1
fi
