#!/bin/sh
# Run: .tools/mathpanel/install-extension.sh
# Input: the sibling extension/package.json and extension source tree.
# Output: a synchronized, versioned VS Code Server extension installation.
# Idempotent: unchanged installs are left untouched, so this is cheap and safe
# to run from the devcontainer's postStartCommand. Removes only known
# superseded MathPanel folders after a successful copy. Touches no extension
# registry, tool settings, or devcontainer configuration.
set -eu

SRC="$(cd "$(dirname "$0")/extension" && pwd)"
if [ ! -f "$SRC/package.json" ] || [ ! -f "$SRC/extension.js" ]; then
  echo "error: extension files missing under $SRC" >&2
  exit 1
fi

VERSION="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "$SRC/package.json")"
case "$VERSION" in
  ''|*[!0-9A-Za-z.+-]*)
    echo "error: unsafe extension version in $SRC/package.json" >&2
    exit 1
    ;;
esac

EXTENSIONS_DIR="$HOME/.vscode-server/extensions"
TARGET="$EXTENSIONS_DIR/local.mathpanel-$VERSION"

remove_superseded() {
  for old_target in \
    "$EXTENSIONS_DIR/local.mathpanel-0.1.0" \
    "$EXTENSIONS_DIR/local.mathpanel-0.2.0"
  do
    if [ "$old_target" != "$TARGET" ]; then
      rm -rf "$old_target"
    fi
  done
}

if [ -d "$TARGET" ] && diff -qr "$SRC" "$TARGET" >/dev/null; then
  remove_superseded
  echo "MathPanel is already up to date."
  exit 0
fi

rm -rf "$TARGET"
mkdir -p "$TARGET"
cp -r "$SRC/." "$TARGET/"
remove_superseded

echo "Installed to $TARGET"
echo "If MathPanel does not appear, reload the VS Code window"
echo "(Command Palette: 'Developer: Reload Window')."
echo "Then run 'MathPanel: Show' from the Command Palette."
