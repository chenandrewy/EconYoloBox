#!/bin/bash
# ABOUTME: Titles the VS Code window when the container is not in YOLO mode,
# ABOUTME: so the posture stays in view. devcontainer.json's postAttachCommand.
#
# Run:     bash .devcontainer/vscode-posture.sh [SETTINGS_FILE] [POSTURE]
# Inputs:  posture.sh's line (or POSTURE, for tests); VS Code's machine
#          settings, ~/.vscode-server/data/Machine/settings.json by default.
# Outputs: in normie mode or a custom posture, that file with the mode at the
#          front of the window title (NORMIE: or CUSTOM:), and without the
#          title and status bar colors earlier versions set. In YOLO mode, nothing. Always exits 0;
#          a file jq cannot parse (JSONC comments, say) is left alone with a
#          warning.
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
    normie) label='NORMIE' ;;
    *) label='CUSTOM' ;;
esac

mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || echo '{}' >"$settings"
tmp=$(mktemp "$settings.XXXXXX") || exit 0
# Earlier versions' longer title prefixes are replaced, and the colors they set
# removed where they are still exactly those.
if jq --arg label "$label" '
    (.["window.title"] // "${rootName}${separator}${activeEditorShort}"
        | sub("^(NORMIE MODE|CUSTOM POSTURE|NORMIE|CUSTOM) - "; "")) as $title
    | .["window.title"] = (if ($title | startswith("\($label):")) then $title else "\($label):\($title)" end)
    | if (.["workbench.colorCustomizations"] | type) == "object" then
        .["workbench.colorCustomizations"] |= with_entries(select(
            [.key, .value] as $kv
            | [["titleBar.activeBackground", "#b91c1c"], ["titleBar.activeBackground", "#d97706"],
               ["titleBar.inactiveBackground", "#7f1d1d"], ["titleBar.inactiveBackground", "#92400e"],
               ["statusBar.background", "#b91c1c"], ["statusBar.background", "#d97706"],
               ["titleBar.activeForeground", "#ffffff"], ["titleBar.activeForeground", "#000000"],
               ["titleBar.inactiveForeground", "#ffffff"], ["titleBar.inactiveForeground", "#000000"],
               ["statusBar.foreground", "#ffffff"], ["statusBar.foreground", "#000000"]]
            | index([$kv]) | not))
      else . end
' "$settings" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$settings"
else
    rm -f "$tmp"
    echo "vscode-posture.sh: could not parse $settings; window left untitled" >&2
fi
exit 0
