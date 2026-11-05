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
  <key>NSRemindersFullAccessUsageDescription</key><string>Tasky에서 할 일을 적고 끝내려면 미리 알림 접근이 필요해요.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Tasky에서 일정을 보고 추가하려면 캘린더 접근이 필요해요.</string>
  <key>NSFocusStatusUsageDescription</key><string>집중 모드가 켜져 있을 때 일정·할 일 알림을 띄우지 않으려고 집중 상태를 확인해요.</string>
</dict></plist>
PLIST
# ad-hoc 서명은 지정 요구가 cdhash라 다시 만들 때마다 손쉬운 사용·미리 알림·캘린더 권한이 풀린다.
# 식별자로 지정 요구를 고정해 다시 빌드해도 같은 앱으로 보이게 한다(F27 피드백 2026-11-05).
codesign --force --sign - --identifier com.tasky.pet -r='designated => identifier "com.tasky.pet"' "$app"
echo "만들었어요: $PWD/$app"
