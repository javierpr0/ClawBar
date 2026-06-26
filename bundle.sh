#!/bin/bash
# Package the release binary into a double-clickable ClawBar.app (menu-bar agent).
# Signed distribution + Sparkle auto-update would build on top of this; see README.
set -e
cd "$(dirname "$0")"
swift build -c release
VERSION=$(.build/release/clawbar --version | awk '{print $2}')
APP="ClawBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/clawbar "$APP/Contents/MacOS/ClawBar"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClawBar</string>
  <key>CFBundleIdentifier</key><string>com.clawbar.app</string>
  <key>CFBundleExecutable</key><string>ClawBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
echo "Built $APP (v$VERSION). Run hooks setup with: $APP/Contents/MacOS/ClawBar install"
