#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="EasyTODO.app"
SOURCE_APP="$PROJECT_ROOT/dist/$APP_NAME"
DESTINATION_APP="/Applications/$APP_NAME"

"$PROJECT_ROOT/scripts/package_app.sh"

# Stop installed bundles and bare SwiftPM development executables before the
# canonical bundle is replaced. The anchored executable pattern avoids touching
# unrelated processes whose arguments merely mention EasyTODO.
PIDS="$(pgrep -f '(/EasyTODO\.app/Contents/MacOS/EasyTODO|(^|/)\.build/[^ ]*/EasyTODO)$' || true)"
if [[ -n "$PIDS" ]]; then
    while IFS= read -r PID; do
        [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
    done <<< "$PIDS"
    for _ in {1..20}; do
        REMAINING="$(pgrep -f '(/EasyTODO\.app/Contents/MacOS/EasyTODO|(^|/)\.build/[^ ]*/EasyTODO)$' || true)"
        [[ -z "$REMAINING" ]] && break
        sleep 0.1
    done
    if [[ -n "${REMAINING:-}" ]]; then
        while IFS= read -r PID; do
            [[ -n "$PID" ]] && kill -KILL "$PID" 2>/dev/null || true
        done <<< "$REMAINING"
    fi
fi

if [[ -d "$DESTINATION_APP" ]]; then
    case "$DESTINATION_APP" in
        /Applications/EasyTODO.app) rm -rf "$DESTINATION_APP" ;;
        *) echo "Refusing to replace unexpected app path: $DESTINATION_APP" >&2; exit 1 ;;
    esac
fi

COPYFILE_DISABLE=1 ditto --norsrc "$SOURCE_APP" "$DESTINATION_APP"
/usr/bin/xattr -cr "$DESTINATION_APP"
codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"
open -n "$DESTINATION_APP"

echo "Installed and launched: $DESTINATION_APP"
