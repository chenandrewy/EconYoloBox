#!/bin/bash
# ABOUTME: Colors and titles the VS Code window when the container is not in
# ABOUTME: YOLO mode, so the posture stays in view. devcontainer.json's postAttachCommand.
#
# Run:     bash .devcontainer/vscode-posture.sh [SETTINGS_FILE] [POSTURE]
# Inputs:  posture.sh's line (or POSTURE, for tests); VS Code's machine
#          settings, ~/.vscode-server/data/Machine/settings.json by default.
# Outputs: in normie mode or a custom posture, that file with a red (normie) or
#          amber (custom) title and status bar and the mode at the front of the
#          window title. In YOLO mode, nothing. Always exits 0; a file jq cannot
#          parse (JSONC comments, say) is left alone with a warning.
#
# Machine settings, not the workspace's .vscode/settings.json: they belong to
# this container, which is created fresh for each posture, whereas the
# workspace is the shared host folder. The Dev Containers extension writes
# this file once per container, as it first attaches, so this runs on attach.
# Rerunning is harmless: the title prefix is added once.

settings=${1:-$HOME/.vscode-server/data/Machine/settings.json}
posture=${2:-$(bash "$(dirname "${BASH_SOURCE[0]}")/posture.sh")}

case "${posture%% *}" in
    yolo) exit 0 ;;
    normie) label='NORMIE MODE' background='#b91c1c' inactive='#7f1d1d' foreground='#ffffff' ;;
    *) label='CUSTOM POSTURE' background='#d97706' inactive='#92400e' foreground='#000000' ;;
esac

mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || echo '{}' >"$settings"
tmp=$(mktemp "$settings.XXXXXX") || exit 0
if jq --arg label "$label" --arg bg "$background" --arg inactive "$inactive" --arg fg "$foreground" '
    (.["window.title"] // "${rootName}${separator}${activeEditorShort}") as $title
    | .["window.title"] = (if ($title | startswith($label)) then $title else "\($label) - \($title)" end)
    | .["workbench.colorCustomizations"] = ((.["workbench.colorCustomizations"] // {}) + {
        "titleBar.activeBackground": $bg,
        "titleBar.activeForeground": $fg,
        "titleBar.inactiveBackground": $inactive,
        "titleBar.inactiveForeground": $fg,
        "statusBar.background": $bg,
        "statusBar.foreground": $fg
      })
' "$settings" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$settings"
else
    rm -f "$tmp"
    echo "vscode-posture.sh: could not parse $settings; window left uncolored" >&2
fi
exit 0
