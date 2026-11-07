#!/usr/bin/env bash
# Builds build/Coach.app from the Swift package in app/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Coach.app"

if [ ! -d "$ROOT/content" ]; then
    node "$ROOT/tools/lock.mjs" open
fi
python3 "$ROOT/tools/build_content.py"

# The Command Line Tools toolchain can't start the new SwiftPM build system,
# so fall back to the native one when it fails.
SWIFT_FLAGS=(-c release --package-path "$ROOT/app")
if ! swift build "${SWIFT_FLAGS[@]}" 2>/dev/null; then
    SWIFT_FLAGS+=(--build-system native)
    swift build "${SWIFT_FLAGS[@]}"
fi
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Coach" "$APP/Contents/MacOS/Coach"
cp "$ROOT/app/Sources/Coach/Resources/content.json" "$APP/Contents/Resources/content.json"

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Coach</string>
    <key>CFBundleDisplayName</key><string>Coach</string>
    <key>CFBundleIdentifier</key><string>com.venkatacrc.coach</string>
    <key>CFBundleExecutable</key><string>Coach</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
