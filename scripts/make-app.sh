#!/bin/zsh
# Tasky.app 만들기(내 Mac용, 직접 서명). 결과: dist/Tasky.app
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
bin=$(swift build -c release --show-bin-path)
app=dist/Tasky.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Tasky" "$app/Contents/MacOS/Tasky"
cp -R "$bin/Tasky_Tasky.bundle" "$app/Contents/Resources/"
version=$(git describe --tags --always 2>/dev/null || echo 0.1)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.tasky.pet</string>
  <key>CFBundleName</key><string>Tasky</string>
  <key>CFBundleExecutable</key><string>Tasky</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier com.tasky.pet "$app"
echo "만들었어요: $PWD/$app"
