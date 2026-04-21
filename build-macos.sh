#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Platformer"
LOVE_VERSION="11.4"
LOVE_ZIP="love-${LOVE_VERSION}-macos.zip"
LOVE_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/${LOVE_ZIP}"
BUILD_DIR="build/macos"
DIST_DIR="dist"

# Source files to include (all .lua files + any assets if added later)
SOURCES=(camera.lua conf.lua enemy.lua levels.lua main.lua network.lua particles.lua player.lua world.lua)

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> Creating ${APP_NAME}.love"
zip -j "$BUILD_DIR/${APP_NAME}.love" "${SOURCES[@]}"

echo "==> Downloading LÖVE ${LOVE_VERSION} for macOS"
if [ ! -f "$BUILD_DIR/${LOVE_ZIP}" ]; then
    curl -L --progress-bar -o "$BUILD_DIR/${LOVE_ZIP}" "$LOVE_URL"
fi

echo "==> Extracting LÖVE"
unzip -q "$BUILD_DIR/${LOVE_ZIP}" -d "$BUILD_DIR"

LOVE_APP="$BUILD_DIR/love.app"
if [ ! -d "$LOVE_APP" ]; then
    echo "ERROR: love.app not found after extraction" >&2
    exit 1
fi

echo "==> Bundling game into app"
cp "$BUILD_DIR/${APP_NAME}.love" "$LOVE_APP/Contents/Resources/"

echo "==> Patching Info.plist"
PLIST="$LOVE_APP/Contents/Info.plist"

# Set bundle name and display name
/usr/bin/python3 - "$PLIST" "$APP_NAME" <<'EOF'
import sys, plistlib, pathlib

path = pathlib.Path(sys.argv[1])
name = sys.argv[2]

with open(path, "rb") as f:
    data = plistlib.load(f)

data["CFBundleName"]        = name
data["CFBundleDisplayName"] = name
data["CFBundleIdentifier"]  = f"com.game.{name.lower()}"
data["CFBundleExecutable"]  = "love"

# Tell LÖVE which .love file to load
data["LOVE_GAME"] = f"{name}.love"

with open(path, "wb") as f:
    plistlib.dump(data, f)

print(f"    CFBundleName        = {data['CFBundleName']}")
print(f"    CFBundleDisplayName = {data['CFBundleDisplayName']}")
print(f"    CFBundleIdentifier  = {data['CFBundleIdentifier']}")
EOF

echo "==> Renaming to ${APP_NAME}.app"
mv "$LOVE_APP" "$BUILD_DIR/${APP_NAME}.app"

echo "==> Creating distributable zip"
OUTPUT="$DIST_DIR/${APP_NAME}-macos.zip"
(cd "$BUILD_DIR" && zip -qr "../../$OUTPUT" "${APP_NAME}.app")

echo ""
echo "Done! Distributable: $OUTPUT"
echo "To test locally (on macOS): open $BUILD_DIR/${APP_NAME}.app"
