#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(swift build -c release --arch x86_64 --show-bin-path)/CompressCraft"
mkdir -p dist/CompressCraft.app/Contents/MacOS
cp "$BIN" dist/CompressCraft.app/Contents/MacOS/CompressCraft
chmod +x dist/CompressCraft.app/Contents/MacOS/CompressCraft
cat > dist/CompressCraft.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CompressCraft</string>
<key>CFBundleIdentifier</key><string>io.github.appbuilderlee2.compresscraft</string>
<key>CFBundleName</key><string>CompressCraft</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
ditto -c -k --sequesterRsrc --keepParent dist/CompressCraft.app dist/CompressCraft-macOS-Intel.zip
