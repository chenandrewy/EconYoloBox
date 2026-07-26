#!/bin/sh
# Synchronizes MathPanel into the container's VS Code Server extension
# directory. Idempotent: unchanged installs are left untouched, so this is
# cheap and safe to run from the devcontainer's postStartCommand.
# Removes the superseded 0.1.0 folder after a successful copy. Touches nothing
# else — no extensions.json, tool settings, or devcontainer config.
set -eu

SRC="$(cd "$(dirname "$0")/extension" && pwd)"
if [ ! -f "$SRC/package.json" ] || [ ! -f "$SRC/extension.js" ]; then
  echo "error: extension files missing under $SRC" >&2
  exit 1
fi

TARGET="$HOME/.vscode-server/extensions/local.mathpanel-0.2.0"
OLD_TARGET="$HOME/.vscode-server/extensions/local.mathpanel-0.1.0"

if [ -d "$TARGET" ] && diff -qr "$SRC" "$TARGET" >/dev/null; then
  rm -rf "$OLD_TARGET"
  echo "MathPanel is already up to date."
  exit 0
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -r "$SRC/." "$TARGET/"
rm -rf "$OLD_TARGET"

echo "Installed to $TARGET"
echo "If MathPanel does not appear, reload the VS Code window"
echo "(Command Palette: 'Developer: Reload Window')."
echo "Then run 'MathPanel: Show' from the Command Palette."
