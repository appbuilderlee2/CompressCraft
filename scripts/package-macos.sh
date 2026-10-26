#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(swift build -c release --arch x86_64 --show-bin-path)/CompressCraft"
APP="dist/CompressCraft.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/licenses"
cp "$BIN" "$APP/Contents/MacOS/CompressCraft"
chmod +x "$APP/Contents/MacOS/CompressCraft"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CompressCraft</string>
<key>CFBundleIdentifier</key><string>io.github.appbuilderlee2.compresscraft</string>
<key>CFBundleName</key><string>CompressCraft</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.1</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
bash scripts/bundle-tools.sh "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/CompressCraft-macOS-Intel.zip
