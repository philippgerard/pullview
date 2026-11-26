#!/bin/sh
# Builds build/PullView.app: a universal, menu-bar-only (LSUIElement) bundle.
# VERSION sets the bundle version. SIGN_IDENTITY picks a codesigning identity; the default "-" signs ad hoc.
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.0.0}"
IDENTITY="${SIGN_IDENTITY:--}"
ARCHS="--arch arm64 --arch x86_64"

swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"

APP=build/PullView.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/PullView" "$APP/Contents/MacOS/PullView"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PullView</string>
  <key>CFBundleIdentifier</key><string>io.github.philippgerard.pullview</string>
  <key>CFBundleName</key><string>PullView</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  # Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "$APP"
