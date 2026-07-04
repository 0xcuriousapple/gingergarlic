#!/bin/zsh
# Builds gingergarlic.app into ./dist
set -e
cd "$(dirname "$0")"

swift build -c release

APP=dist/gingergarlic.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/gingergarlic "$APP/Contents/MacOS/gingergarlic"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>xyz.curiousapple.gingergarlic</string>
    <key>CFBundleName</key>
    <string>gingergarlic</string>
    <key>CFBundleExecutable</key>
    <string>gingergarlic</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC has a stable-ish identity to attach the permission to.
codesign --force -s - "$APP"

echo "built $APP"
echo "run:   open $APP"
