# F29 배포·자동 업데이트 — plan

- 상태: 구현됨, 첫 출시 전 (2026-11-06)
- 입력: ~/work/proposal/tasky/release/intent.md (디자인 단계 없음)

## 결정 (사용자가 추천안 위임, 2026-11-06)
- 버전은 저장소의 `VERSION` 파일 하나. CFBundleShortVersionString·CFBundleVersion 둘 다 같은 SemVer.
- 자동 확인은 묻지 않고 켬(`SUEnableAutomaticChecks`). 설정 > 정보에 '지금 확인'·'자동으로 확인'.
- appcast: `appcast.xml`(main) raw URL. 공개 키는 `scripts/sparkle-public-key`(저장소), 개인 키는 키체인에만.
- `release.sh` 순서: VERSION 커밋·태그 push → Release에 zip·dmg 업로드 → appcast 커밋·push(404 방지). push 전에 y/N 확인.
- 공개 키 파일이 없으면 make-app.sh는 업데이트 없이 만든다. `swift build`로 띄운 개발 빌드는 업데이트를 켜지 않는다.

## 확인한 것
- 시험 앱(같은 빌드 방식, ad-hoc)에서 1.0.0→1.0.1 감지·설치·재실행. 다른 키로 서명한 파일은 거부(3002). 식별자 고정 없는 ad-hoc 새 앱도 받음 → Sparkle은 EdDSA만으로 검증.
- `release.sh 1.0.1 --dry-run`(시험 키): .app 서명·Frameworks/Sparkle 포함·Info.plist, zip EdDSA 검증, dmg(UDZO, Applications 링크, 안의 앱 서명), appcast 항목 삽입 후 XML 유효. 실패해도 VERSION 되돌림.

## 못 한 것
- 실제 Tasky.app의 업데이트 창(Sparkle 기본 UI)과 GitHub https 경로. 첫 출시(1.0.0) 뒤 1.0.1로 확인.
- dmg로 처음 설치할 때의 경고 안내(사이트 단계). Applications로 옮기지 않으면 앱 이동(translocation)으로 업데이트가 실패할 수 있음.

## 첫 출시 전 할 일
1. `.build/artifacts/sparkle/Sparkle/bin/generate_keys` (키체인 허용) → 나온 공개 키를 `scripts/sparkle-public-key`에 저장
2. `generate_keys -x <파일>`로 개인 키를 내보내 비밀번호 관리자에 백업(잃으면 설치된 앱이 업데이트를 못 받음)
3. 변경을 커밋한 뒤 `scripts/release.sh 1.0.0`

## 변경 이력
- 2026-11-06 작성
