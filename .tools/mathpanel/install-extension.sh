#!/bin/sh
# Installs MathPanel by copying the extension folder into the container's
# VS Code Server extension directory. Idempotent: safe to run twice.
# Touches nothing else — no extensions.json, no Claude settings, no devcontainer
# config. Uninstall = rm -rf the target directory + reload the window.
set -eu

SRC="$(cd "$(dirname "$0")/extension" && pwd)"
if [ ! -f "$SRC/package.json" ] || [ ! -f "$SRC/extension.js" ]; then
  echo "error: extension files missing under $SRC" >&2
  exit 1
fi

TARGET="$HOME/.vscode-server/extensions/local.mathpanel-0.1.0"
rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -r "$SRC/." "$TARGET/"

echo "Installed to $TARGET"
echo "Reload the VS Code window (Command Palette: 'Developer: Reload Window') to activate."
echo "Then run 'MathPanel: Show' from the Command Palette."
