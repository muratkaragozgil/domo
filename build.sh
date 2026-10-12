#!/bin/zsh
# Builds Domo.app and installs it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=build/Domo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Domo "$APP/Contents/MacOS/Domo"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Domo</string>
    <key>CFBundleIdentifier</key><string>com.muratkaragozgil.domo</string>
    <key>CFBundleName</key><string>Domo</string>
    <key>CFBundleDisplayName</key><string>Domo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>Domo talks to your cat feeder and plugs directly over your home Wi-Fi.</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/*.png "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Icons" && cp Resources/Icons/*.png "$APP/Contents/Resources/Icons/"

codesign --force --sign - "$APP"

DEST=~/Applications/Domo.app
pkill -x Domo 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Installed $DEST"
