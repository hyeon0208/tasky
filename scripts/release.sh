#!/bin/zsh
# Tasky 출시(F29). 사용법: scripts/release.sh 1.0.1 [--dry-run|--yes]
# 버전 올리기 → release 빌드(.app) → .zip·.dmg → Sparkle 서명 → GitHub Release → appcast.xml 갱신·push
# --dry-run: 파일 만들기와 서명까지만 하고 git·GitHub은 건드리지 않는다.
# --yes: push 전 확인을 건너뛴다(Claude Code의 `!`처럼 입력을 받을 수 없을 때).
# Sparkle 개인 키는 키체인에서 읽는다(처음 한 번: .build/artifacts/sparkle/Sparkle/bin/generate_keys).
set -euo pipefail
cd "${0:A:h}/.."
v=${1:?"버전을 적어 주세요. 예: scripts/release.sh 1.0.1"}
dry=${2:-}
[[ $v =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "버전은 1.2.3 형식이어야 해요"; exit 1; }
[[ -s scripts/sparkle-public-key ]] || { echo "scripts/sparkle-public-key가 없어요(generate_keys -p 결과를 넣어 주세요)"; exit 1; }
if [[ $dry != --dry-run ]]; then
  [[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "커밋하지 않은 변경이 있어요. 정리한 뒤 다시 실행해 주세요"; exit 1; }
  [[ $(git branch --show-current) == main ]] || { echo "main 브랜치에서 실행해 주세요"; exit 1; }
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null && { echo "v$v 태그가 이미 있어요"; exit 1; }
  gh auth status >/dev/null
fi

old=$(cat VERSION)
trap 'echo $old > VERSION' EXIT   # 실패·중단·dry-run이면 버전을 되돌린다
echo $v > VERSION
scripts/make-app.sh
app=dist/Tasky.app zip=dist/Tasky-$v.zip dmg=dist/Tasky-$v.dmg
rm -f $zip $dmg
ditto -c -k --sequesterRsrc --keepParent $app $zip
stage=$(mktemp -d)
ditto $app $stage/Tasky.app
ln -s /Applications $stage/Applications
hdiutil create -quiet -volname Tasky -srcfolder $stage -format UDZO $dmg
rm -rf $stage

sign=.build/artifacts/sparkle/Sparkle/bin/sign_update
key=(); [[ -n ${SPARKLE_KEY_FILE:-} ]] && key=(--ed-key-file $SPARKLE_KEY_FILE)   # 시험용 키 파일(평소엔 키체인)
attrs=$($sign $key $zip)   # sparkle:edSignature="…" length="…"
url=https://github.com/hyeon0208/tasky/releases/download/v$v/Tasky-$v.zip
item="    <item>
      <title>$v</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$v</sparkle:version>
      <sparkle:shortVersionString>$v</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/hyeon0208/tasky/releases/tag/v$v</sparkle:fullReleaseNotesLink>
      <enclosure url=\"$url\" $attrs type=\"application/octet-stream\"/>
    </item>"
echo "만들었어요: $zip, $dmg"
if [[ $dry == --dry-run ]]; then
  echo "--dry-run: appcast 항목(적용 안 함)"; echo "$item"; exit 0
fi

[[ $dry == --yes ]] || read -q "?v${v}를 main에 push하고 GitHub Release를 만들까요? [y/N] " || { echo; echo "그만뒀어요"; exit 1; }
echo
git commit -q -m "v$v 출시" VERSION
trap - EXIT
git tag v$v
git push -q origin main v$v
gh release create v$v $zip $dmg --title "Tasky $v" --generate-notes
# 파일이 올라간 뒤에 appcast를 바꿔야 설치된 앱이 404를 받지 않는다.
ITEM=$item perl -0pi -e 's/(<!-- items -->\n)/$1$ENV{ITEM}\n/' appcast.xml
git commit -q -m "appcast: v$v" appcast.xml
git push -q origin main
echo "출시했어요: https://github.com/hyeon0208/tasky/releases/tag/v$v"
