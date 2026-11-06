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
# 앱 아이콘: Assets/AppIcon.png(1024) → AppIcon.icns
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s Assets/AppIcon.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Assets/AppIcon.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Frameworks"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"   # F29 자동 업데이트
version=$(cat VERSION)
# Sparkle 공개 키(scripts/sparkle-public-key, 저장소에 둠). 없으면 업데이트 없이 만든다.
sparkle=""
if [[ -s scripts/sparkle-public-key ]]; then
  sparkle="<key>SUFeedURL</key><string>https://raw.githubusercontent.com/hyeon0208/tasky/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$(cat scripts/sparkle-public-key)</string>
  <key>SUEnableAutomaticChecks</key><true/>"
fi
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.tasky.pet</string>
  <key>CFBundleName</key><string>Tasky</string>
  <key>CFBundleExecutable</key><string>Tasky</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  $sparkle
  <key>NSRemindersFullAccessUsageDescription</key><string>Tasky에서 할 일을 적고 끝내려면 미리 알림 접근이 필요해요.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Tasky에서 일정을 보고 추가하려면 캘린더 접근이 필요해요.</string>
  <key>NSFocusStatusUsageDescription</key><string>집중 모드가 켜져 있을 때 일정·할 일 알림을 띄우지 않으려고 집중 상태를 확인해요.</string>
</dict></plist>
PLIST
# ad-hoc 서명은 지정 요구가 cdhash라 다시 만들 때마다 손쉬운 사용·미리 알림·캘린더 권한이 풀린다.
# 식별자로 지정 요구를 고정해 다시 빌드해도 같은 앱으로 보이게 한다(F27 피드백 2026-11-05).
codesign --force --sign - --identifier com.tasky.pet -r='designated => identifier "com.tasky.pet"' "$app"
echo "만들었어요: $PWD/$app"
