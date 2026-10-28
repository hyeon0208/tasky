# F16 클립보드 기록 — plan
- 작성: 2026-10-29 · 근거: intent.md(승인됨), spec.md(승인됨) · 상태: 구현됨, 화면 확인 대기

## 바뀌는 파일
| 파일 | 변경 |
|---|---|
| `Sources/Tasky/Clipboard.swift` (새로) | `ClipItem`, `ClipHistory`(순수), `ClipWatcher`, `ClipStore`, `HotKey`(Carbon), `ClipWindow` |
| `Sources/Tasky/PetController.swift` | `App`: 시작 때 감시·단축키, 복사 반응을 보이는 펫에 전달. 펫: 링 '클립보드' 칸, 쪽지, 설정 '클립보드' 탭 |
| `Sources/Tasky/Geometry.swift` | 자체 검사 |
| `CLAUDE.md`, `README.md` | 구조·기능 |

## 작업 순서와 검사
### 1. `ClipHistory` (순수)
- `insert(item)`: 같은 내용(글자·파일 경로·이미지 해시)이 있으면 그것을 맨 위로(시각 갱신), 없으면 맨 위에 추가. 고정이 아닌 것이 `limit`를 넘으면 오래된 것부터 지움(지운 이미지 파일 이름 반환).
- `search(q)`: 대소문자·전각 무시 포함 검색, 고정 먼저.
- `isConcealed(types:)`: 숨김·임시·자동 생성 타입 판정.
- **검사:** spec 검증 방법 그대로.

### 2. `ClipStore` + `ClipWatcher`
- 저장: `Paths.support/Clipboard/history.json`(원자 쓰기), 이미지 `<uuid>.png`. 바뀔 때 0.5초 모아 저장.
- 감시: `Ticker.every("복사한 것 확인하기", 0.5)`, `changeCount`가 바뀌고 우리 앱이 올린 것이 아니면 읽기. 순서: 파일 URL → 이미지 → 글자. 크기 제한 넘으면 건너뜀.
- **검사:** JSON 왕복(임시 폴더).

### 3. `HotKey`
- `RegisterEventHotKey` + `InstallEventHandler`(앱 이벤트 대상). 등록 결과(성공/실패)를 돌려준다. 단축키는 UserDefaults(`clipHotKey`: keyCode·modifiers), 기본 ⌘⇧C.
- **검사:** 빌드. 실제 동작은 사용자 확인.

### 4. `ClipWindow`
- 커서 화면 가운데 위쪽 3분의 1, 420×(검색 44 + 행 44×최대 8). 검색 칸에 바로 포커스(`NSApp.activate` 후 `makeKeyAndOrderFront`), 닫을 때 이전 앱 다시 활성화.
- 행: SF Symbol(글자 text.alignleft·이미지 photo·파일 doc) 또는 이미지 미리보기, 한 줄 글자, 시간, 고정 핀. 키: ↑↓ ↩ Esc ⌘P ⌫ 1~9.
- 고르면 `ClipWatcher`에 '우리가 올림' 표시 후 클립보드에 쓰고 `ClipHistory`에서 맨 위로.
- **검사:** 빌드.

### 5. 펫·설정
- 링 '클립보드'(doc.on.clipboard) 칸, 복사 반응(입벌림 0.6초 + 쪽지 앞 20자 1.5초, 설정으로 끔).
- 설정 '클립보드' 탭: 켜기, 단축키(녹화 버튼: 다음 키 조합을 받아 저장·다시 등록, 실패 시 안내), 기록 개수(10~200), 복사할 때 펫 반응, 전체 지우기(고정 제외 / 고정 포함), ⌘⇧C 겹침 안내 한 줄.
- **검사:** 빌드, 자체 검사 전체.

### 6. 마무리
- 독립 검토 → 반영 → 다른 점 기록, 커밋·push.

## 확인하지 못할 것 (사용자 확인)
- ⌘⇧C로 창이 뜨는지, 바로 검색되는지, 고른 뒤 ⌘V로 붙는지, 숨김 복사(비밀번호 관리자)가 빠지는지.

## 구현 결과와 plan과 다른 점 (2026-10-29)
- 자체 검사 통과(개수 넘침·고정 남음, 같은 내용 맨 위로, 검색, 숨김 판정, 저장·읽기).
- 독립 검토 반영: 단축키 녹화가 닫힌 뒤에도 키를 가로채던 문제, ⇧만으로 된 단축키 막기, 한글 조합 중 ⌫·↩ 오작동, 한글 자판에서 ⌘P·⌘1~9, 기록 개수를 줄일 때 이미지 파일 정리, 기록 폴더 0700·파일 0600, 이미지 미리보기 캐시, 실행 파일을 옮겨도 메뉴 막대 로고 때문에 멈추지 않게.
- 다른 점: 창 440폭·줄 40pt·9줄(⌘1~9와 맞춤), 저장 키 `clipKeyCode`/`clipKeyMods`.
- 함께: 메뉴 막대 로고를 앱 아이콘(곰+체크)에서 뽑은 흑백 템플릿으로(`Assets/make-menubar-icon.swift`).
- 확인 못 함: ⌘⇧C로 열림, 검색, 고른 뒤 ⌘V, 비밀번호 관리자 복사 제외, 메뉴 막대 로고 실제 크기.

## 변경 이력
- 2026-10-29 초안
- 2026-10-29 구현, 독립 검토 반영
