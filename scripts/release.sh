#!/bin/zsh
# Tasky 출시(F29). 사용법: scripts/release.sh 1.0.1 --notes "바뀐 점 한 줄" [--dry-run|--yes]
# 버전 올리기 → release 빌드(.app) → .zip·.dmg → Sparkle 서명 → GitHub Release → appcast.xml 갱신·push
# --notes: 릴리스 노트 첫 줄(사이트 '새로운 소식'에 쓰임). 그 아래에 GitHub 자동 노트가 붙는다. 실제 출시엔 꼭 적는다.
# 이름 고정 사본 Tasky.dmg·Tasky.zip도 함께 올린다(사이트가 releases/latest/download/Tasky.dmg로 연결, tasky-site ADR 0001).
# --dry-run: 파일 만들기와 서명까지만 하고 git·GitHub은 건드리지 않는다.
# --yes: push 전 확인을 건너뛴다(Claude Code의 `!`처럼 입력을 받을 수 없을 때).
# Sparkle 개인 키는 키체인에서 읽는다(처음 한 번: .build/artifacts/sparkle/Sparkle/bin/generate_keys).
set -euo pipefail
cd "${0:A:h}/.."
v=${1:?"버전을 적어 주세요. 예: scripts/release.sh 1.0.1 --notes \"바뀐 점 한 줄\""}; shift
dry= notes=
while (( $# )); do
  case $1 in
    --dry-run|--yes) dry=$1 ;;
    --notes) notes=${2:?"--notes 뒤에 한 줄을 적어 주세요"}; shift ;;
    *) echo "모르는 옵션: $1"; exit 1 ;;
  esac
  shift
done
[[ $v =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "버전은 1.2.3 형식이어야 해요"; exit 1; }
[[ -s scripts/sparkle-public-key ]] || { echo "scripts/sparkle-public-key가 없어요(generate_keys -p 결과를 넣어 주세요)"; exit 1; }
if [[ $dry != --dry-run ]]; then
  [[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "커밋하지 않은 변경이 있어요. 정리한 뒤 다시 실행해 주세요"; exit 1; }
  [[ $(git branch --show-current) == main ]] || { echo "main 브랜치에서 실행해 주세요"; exit 1; }
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null && { echo "v$v 태그가 이미 있어요"; exit 1; }
  [[ -n $notes ]] || { echo "--notes \"바뀐 점 한 줄\"을 적어 주세요(사이트 '새로운 소식'에 쓰여요)"; exit 1; }
  gh auth status >/dev/null
fi

old=$(cat VERSION)
trap 'echo $old > VERSION' EXIT   # 실패·중단·dry-run이면 버전을 되돌린다
echo $v > VERSION
scripts/make-app.sh
app=dist/Tasky.app zip=dist/Tasky-$v.zip dmg=dist/Tasky-$v.dmg
rm -f $zip $dmg dist/Tasky.zip dist/Tasky.dmg
ditto -c -k --sequesterRsrc --keepParent $app $zip
stage=$(mktemp -d)
ditto $app $stage/Tasky.app
ln -s /Applications $stage/Applications
hdiutil create -quiet -volname Tasky -srcfolder $stage -format UDZO $dmg
rm -rf $stage
cp $zip dist/Tasky.zip; cp $dmg dist/Tasky.dmg   # 이름 고정 사본(appcast는 버전 붙은 zip을 쓴다)

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
echo "만들었어요: $zip, $dmg, dist/Tasky.zip, dist/Tasky.dmg"
if [[ $dry == --dry-run ]]; then
  echo "--dry-run: appcast 항목(적용 안 함)"; echo "$item"; exit 0
fi

[[ $dry == --yes ]] || read -q "?v${v}를 main에 push하고 GitHub Release를 만들까요? [y/N] " || { echo; echo "그만뒀어요"; exit 1; }
echo
git diff --quiet VERSION || git commit -q -m "v$v 출시" VERSION   # 첫 출시처럼 이미 같은 버전이면 건너뜀
trap - EXIT
git tag v$v
git push -q origin main v$v
gh release create v$v $zip $dmg dist/Tasky.zip dist/Tasky.dmg --title "Tasky $v" --notes "$notes" --generate-notes
# 파일이 올라간 뒤에 appcast를 바꿔야 설치된 앱이 404를 받지 않는다.
ITEM=$item perl -0pi -e 's/(<!-- items -->\n)/$1$ENV{ITEM}\n/' appcast.xml
git commit -q -m "appcast: v$v" appcast.xml
git push -q origin main
echo "출시했어요: https://github.com/hyeon0208/tasky/releases/tag/v$v"
