# Tasky 홍보 사이트 plan

- 상태: done (배포 전)
- 작성일: 2026-11-07
- spec: ./spec.md
- 변경 이력
  - 2026-11-07: 최초 작성

## 목표
c2와 똑같이 보이는 정적 사이트에서, 클릭 한 번으로 최신 .dmg/.zip을 받고 상태별 소식·복사 실패·클릭 이벤트가 spec대로 동작한다.

## 근거로 확인한 API·코드
- 릴리스 목록 `GET https://api.github.com/repos/hyeon0208/tasky/releases?per_page=3` → `tag_name`, `draft`, `prerelease`, `body`, `assets[].name/browser_download_url` — c2.html:239-252, 2026-11-07 실제 응답 확인
- `releases/latest/download/<이름>` → 302로 최신 태그의 같은 이름 파일 — 2026-11-07 HEAD 확인
- `window.va` 대기열 + `va('event', { name, data })`, 스크립트 `/<unique-path>/script.js`(또는 `/_vercel/insights/script.js`) — https://vercel.com/docs/analytics/custom-events
- `navigator.clipboard.writeText()` Promise, 실패 시 reject / 없음 — c2.html:256

## 파일 맵
- 생성: `index.html` — c2.html 복사 후 아래 단계만 수정
- 생성(복사): `media/{00-hero,03-menubar,04-ring,05-today,06-shrink,07-drawer,08-capture,09-clipboard,10-keyboard,11-window,12-keyrepeat}.{mp4,jpg}`, `img/appicon.png`
- 생성: `tests/check.mjs` — Node 표준만. index.html 안 스크립트의 두 순수 함수를 검사
- 생성: `CLAUDE.md` — 이 폴더 실수 기록용(처음엔 확인 명령 한 줄)

## 단계
### 1. 시안 옮기기
- 목표 기여: c2를 그대로 살린 바탕
- 파일: index.html, media/, img/
- 할 일: c2.html → index.html, `<title>Tasky</title>`. c2가 참조하는 파일만 복사(위 목록)
- 검사: index.html의 `src`/`poster`/`stageVid.src` 경로가 모두 파일로 존재하는지 스크립트로 확인 → 누락 0
- [x] 완료

### 2. 다운로드 주소 고정 + 소식·버전 상태
- 목표 기여: 클릭 한 번 다운로드, design.md 상태 표
- 파일: index.html
- 할 일:
  - `[data-dl]` 4곳 href → `…/releases/latest/download/Tasky.dmg|.zip`
  - 소식 샘플 줄 제거(불러오는 중 빈 칸)
  - 순수 함수 `pickRelease(list) → {tag, first, assets:{dmg,zip}} | null`(공개 릴리스 없으면 null), `firstLine(body)`(c2의 정규식 그대로)로 분리
  - 성공: 버전·소식 채움, 확장자 파일 있으면 그 주소, 없으면 `releases/latest` / 빈(null): "아직 공개한 버전이 없어요" + GitHub 링크 / 실패: "GitHub에서 보기" 링크만
- 검사: `node tests/check.mjs` → 사례 4개 통과(정상, Full Changelog만 있는 본문 → 대체 문구, draft·prerelease만 → null, 확장자 파일 없음)
- [x] 완료

### 3. 복사 실패 처리
- 목표 기여: spec 4
- 파일: index.html
- 할 일: `writeText` 없음/reject → `Selection.selectAllChildren(code)` + 버튼 "⌘C로 복사" 1.5초 후 "복사"
- 검사: 브라우저에서 `navigator.clipboard.writeText`를 reject로 바꿔 클릭 → 명령이 선택되고 글자 바뀜
- [x] 완료

### 4. 클릭 이벤트
- 목표 기여: spec 3
- 파일: index.html `<head>`
- 할 일: `window.va` 대기열 → `<script defer src="/_vercel/insights/script.js">`. `[data-dl]` 클릭 시 `va('event', {name:'download', data:{type}})`
- 검사: 로컬에서 클릭 후 `window.vaq`에 `['event',{name:'download',data:{type:'dmg'}}]`가 쌓임
- [x] 완료

### 5. 전체 확인
- 검사: `python3 -m http.server`로 띄워 Chrome에서 1440·820·375px 스크린샷 → c2와 같은 모습, 가로 스크롤 없음(`scrollWidth == clientWidth`), 콘솔 오류 0(스크립트 404는 로컬이라 예외), API 차단 시 오류 상태 표시
- [x] 완료

## Not now
- Vercel 프로젝트 생성·배포(승인 후) · 앱 `release.sh` 수정과 v1.4.0 이름 고정 파일 업로드(앱 폴더) · 릴리스 노트 쓰기(앱) · `/<unique-path>` 교체(대시보드에서 켠 뒤) · 영상 재촬영

## 진행 기록
- [x] 1  - [x] 2  - [x] 3  - [x] 4  - [x] 5 (375px는 Chrome 창 최소 폭 500px로 대신 확인)

## 결정(Ruling)
- 2026-11-07 단계 2: 테스트 가능한 두 함수만 분리하고 나머지는 c2 구조 유지 — 최소 변경 — 틀리면 함수 두 개 인라인으로 되돌리면 됨
- 2026-11-07 단계 2: 테스트는 index.html의 `<script>`에서 함수 정의를 잘라 `node`로 평가(별도 js 파일 안 만듦) — 한 파일 유지 — 함수 이름이 바뀌면 검사가 깨져 바로 드러남
- 2026-11-07 리뷰 반영: API를 `/releases?per_page=3` → `/releases/latest`(404 = 빈 상태)로 바꿈 — 최근 3개가 모두 prerelease일 때 빈 상태가 잘못 뜨는 문제 — 응답 모양만 배열로 감싸 pickRelease 그대로 씀
- 2026-11-07 리뷰 반영: 빈 상태에서도 다운로드를 `releases/latest` 페이지로, 복사 문구 타이머 겹침 방지, `.news > :empty{display:none}`(빈 칸이 간격 차지하던 것) — design.md 상태 표·spec 4 준수
