#!/bin/bash
# Tasky 한 줄 설치: 최신 Release를 내려받아 /Applications에 넣고 경고 표시(quarantine)를 지운 뒤 연다.
# 사용: curl -fsSL https://raw.githubusercontent.com/hyeon0208/tasky/main/scripts/install.sh | bash
set -euo pipefail
repo=hyeon0208/tasky
apps=${TASKY_APPS:-/Applications}   # 시험할 때만 바꾼다
tag=$(curl -fsSI "https://github.com/$repo/releases/latest" | tr -d '\r' | sed -n 's#^[Ll]ocation: .*/tag/##p')
[ -n "$tag" ] || { echo "최신 버전을 찾지 못했어요. 인터넷 연결을 확인해 주세요."; exit 1; }
echo "Tasky ${tag#v} 내려받는 중…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar -o "$tmp/Tasky.zip" "https://github.com/$repo/releases/download/$tag/Tasky-${tag#v}.zip"
ditto -x -k "$tmp/Tasky.zip" "$tmp"
pkill -f "$apps/Tasky.app/Contents/MacOS/Tasky" 2>/dev/null && sleep 1 || true   # 설치된 Tasky가 켜져 있으면 끈다
rm -rf "$apps/Tasky.app"
mv "$tmp/Tasky.app" "$apps/"
xattr -cr "$apps/Tasky.app"
echo "설치했어요: $apps/Tasky.app"
[ -n "${TASKY_APPS:-}" ] || open "$apps/Tasky.app"
