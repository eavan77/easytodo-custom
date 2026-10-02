#!/usr/bin/env bash
set -euo pipefail

APP_NAME="EasyTODO"
BUNDLE_ID="${BUNDLE_ID:-com.easytodo.EasyTODO}"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-10}"
CONFIGURATION="${CONFIGURATION:-release}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/easytodo-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
FINAL_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ICON_SOURCE="$PROJECT_ROOT/Sources/EasyTODO/Resources/logo.png"
ICONSET_DIR="$STAGING_DIR/$APP_NAME.iconset"
ICON_FILE="$RESOURCES_DIR/$APP_NAME.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"

cd "$PROJECT_ROOT"

GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || printf 'unavailable')"
if ! git diff --quiet --ignore-submodules -- 2>/dev/null; then
    GIT_HASH="${GIT_HASH}+dirty"
fi
BUILD_DATE="$(date '+%b %e, %Y %H:%M %Z')"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PROJECT_ROOT/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift build -c "$CONFIGURATION"
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Missing built executable: $EXECUTABLE" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/logo.png"
fi

if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [[ -f "$ICON_SOURCE" ]]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
    rm -rf "$ICONSET_DIR"
fi

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>EasyTODOGitHash</key>
    <string>$GIT_HASH</string>
    <key>EasyTODOBuildDate</key>
    <string>$BUILD_DATE</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>EasyTODO reads your calendars to show special events alongside your weekly school timetable.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
plutil -lint "$INFO_PLIST" >/dev/null

if command -v codesign >/dev/null 2>&1; then
    # Finder/FileProvider metadata makes otherwise valid bundles fail signing.
    # Strip it only from the generated app, immediately before signing.
    case "$APP_BUNDLE" in
        "$STAGING_DIR"/*.app)
            /usr/bin/xattr -cr "$APP_BUNDLE"
            ;;
        *)
            echo "Refusing to alter extended attributes outside generated app: $APP_BUNDLE" >&2
            exit 1
            ;;
    esac
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

rm -f "$ZIP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ -e "$FINAL_APP_BUNDLE" ]]; then
    case "$FINAL_APP_BUNDLE" in
        "$PROJECT_ROOT"/dist/*.app) rm -rf "$FINAL_APP_BUNDLE" ;;
        *) echo "Refusing to replace unexpected app path: $FINAL_APP_BUNDLE" >&2; exit 1 ;;
    esac
fi
COPYFILE_DISABLE=1 ditto --norsrc "$APP_BUNDLE" "$FINAL_APP_BUNDLE"

if command -v codesign >/dev/null 2>&1; then
    # FileProvider-backed folders can reattach Finder metadata while archiving.
    # Clean and verify with a short retry because the metadata can race the copy.
    VERIFIED=false
    for _ in {1..5}; do
        /usr/bin/xattr -cr "$FINAL_APP_BUNDLE"
        if codesign --verify --deep --strict --verbose=2 "$FINAL_APP_BUNDLE"; then
            VERIFIED=true
            break
        fi
        sleep 0.1
    done
    if [[ "$VERIFIED" != true ]]; then
        echo "Unable to produce a clean signed app bundle: $FINAL_APP_BUNDLE" >&2
        exit 1
    fi
fi

echo "Packaged app: $FINAL_APP_BUNDLE"
echo "Installable zip: $ZIP_PATH"
