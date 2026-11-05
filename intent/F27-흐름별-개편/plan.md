# F27 흐름별 개편 — plan
- 작성: 2026-11-05 · 근거: spec.md(승인됨 2026-11-05) · 상태: 승인됨(2026-11-05) — 사용자: 전 단계를 한 번에 진행하고 마지막에 한 번 확인
- 단계마다 다음 순서로 진행한다:
  1. `swift build` 종료 코드가 0인지 확인한다(grep으로 거르지 않음).
  2. `.build/debug/Tasky --selftest`를 돌린다.
  3. `./scripts/make-app.sh`로 앱을 만든다. 실행 중인 펫은 사용자에게 묻고 바꾼다.
  4. 사용자가 화면으로 확인한다. 시안과 다른 점은 보고한다.
  5. 다음 단계로 간다.
- 커밋은 사용자가 요청할 때만 한다.

## 1단계 — 알림 패널 C · 일정/할 일 알림 · 집중 모드 · AI 승인만 (spec 공통·4·7, 우려 1·2)
- Tasks.swift
  - `TaskLogic.eventAlerts(events:now:sent:)`를 순수 함수로 만든다. 단계는 60분 전·30분 전·정각이고, 지난 단계는 가장 최근 것 하나만 돌려준다. 보낸 키는 `id@시작#단계`다.
  - `TaskLogic.todoNudge(remaining:last:now:interval:)`를 순수 함수로 만든다.
  - `TaskAlerts.check()`에 위 두 함수를 연결하고, 기존 `Ticker` 30초를 그대로 쓴다.
- Tasks.swift `TaskAlertPanel`
  - C 모양 `FocusCard`로 다시 그린다.
  - 한 번에 하나만 띄우고, 나머지는 줄을 세운다.
  - 같은 일정의 다음 단계가 오면 떠 있는 패널을 바꿔 끼운다.
  - 일정 버튼은 확인·10분 뒤, 할 일 버튼은 완료·나중에다.
- 새 Focus.swift: `FocusState.isOn`을 둔다.
  - 먼저 `INFocusStatusCenter`를 시도하고, 권한을 못 받으면 `nil`을 돌려준다.
  - 결과는 실제 앱(dist/Tasky.app)으로 확인한다. 막히면 멈추고 대안 b를 사용자에게 묻는다.
- SettingsView.swift: 다음 설정 두 개를 만든다.
  - '일정 볼 기간': 1~7, 기본 7.
  - '할 일 알려 주기 간격': 끄기/15/30/60/120, 기본 60.
  - 일정 볼 기간은 3단계 오늘 카드에서 쓴다.
- Agents.swift / PetController.swift `presentAlert`
  - `AgentAlert.shouldShow(state)`를 순수 함수로 만든다. 승인 대기일 때만 true다.
  - 끝남·실패는 알리지 않는다.
  - payload에 `tool_name`·`tool_input`이 오는지 확인하고, 오면 카드에 명령 앞 80자를 보여 준다.
- Geometry.swift `SelfTest`에 넣을 검사:
  - 일정 단계 시각 계산(늦게 켜진 경우 포함)
  - N분 간격 할 일 알림과 남은 할 일 0개인 경우
  - 승인 대기만 알리는 판정
  - 설정 기본값

## 2단계 — 받침대 · 상태 구슬 · 알약 · 원형 메뉴 (spec 1·2·3, 우려 4)
- 받침대
  - Today.swift: `GlanceStand` 뷰를 만든다. 시계·할 일 수·다음 일정과 오른쪽 끝 상태 구슬(`AgentBadgeView`를 옮김)이다.
  - `GlanceChipsView`는 지운다.
  - PetView.swift / PetController.swift: 곰 발밑에 자식 패널을 두고 마우스를 통과시킨다. 구슬 칸만 클릭을 받는다.
  - 설정 '알림 디스플레이 보기'를 만든다: 갖다대면(기본)/항상/안 봄.
- 알약
  - Geometry.swift `islandFrame`에 옆으로 펼치는 방향을 더한다.
  - PetController.swift `islandContent`를 미니 오늘로 바꾸고, 라이트·다크는 `effectiveAppearance`를 따른다.
- 원형 메뉴
  - RingView.swift: 반원 6칸과 이름표 하나로 바꾼다. 칸은 오늘 카드·빠른 실행·폴더 서랍·캡처·작업 목록·잠 안 자기다.
  - `RingMath.direction(pet:screen:occupied:)`를 순수 함수로 만들어, 다른 패널과 겹치지 않는 방향을 고른다.
  - PetController.swift: 빼꼼·그 사이 N건을 메뉴 막대로 옮긴다.
- 검사: 받침대 보기 3가지 설정, 반원 방향 고르기, 칸이 6개인지.

## 3단계 — 오늘 카드 · 빠른 실행 · 할 일 창 (spec 4·5·6)
- Today.swift `TodayCard`
  - 할 일·일정·AI 작업 세 덩어리로 나눈다.
  - 입력칸 문구는 "할 일 또는 일정 추가"다.
  - 일정은 N일 뒤까지 보여 준다.
- QuickRun.swift
  - 명령 바 모양으로 다시 그린다.
  - 일정으로 읽힐 때만 저장 미리보기를 보여 준다.
  - 입력 중에 contentView를 다시 만들지 않는다.
- Tasks.swift `TaskWindow`
  - 오늘·다가오는 두 칸으로 나눈다.
  - '고정' 버튼을 누르면 항상 위 미니 패널이 되고, 다시 누르면 돌아온다.
- 검사: N일 범위 거르기. 입력을 일정으로 읽을 때만 미리보기가 켜지는지(`QuickParse` 결과로 확인).

## 4단계 — 원형 변환 (spec 9, 우려 3)
- Converter.swift
  - 새 항목: toTIFF, imageToPDF(1장), pdfToJPG, pdfToText, pdfShrink, pdfSplit, pdfToDOCX, docToODT, csvToXLSX, sheetToPDF, toMOV, posterFrame, toAIFF.
  - 칸 종류(형식/동작)와 짧은 설명을 `ConvertOp`에 둔다.
  - 원본과 같은 형식의 칸을 빼는 규칙을 모든 종류에 적용한다.
- 새 ConvertWheel.swift: 둥근 부채꼴을 그리는 비활성 패널이다.
  - 이 패널이 드롭을 직접 받는다.
  - 칸이 7개 이하면 고리 하나, 넘으면 두 고리다. 화면 가장자리에서는 반원으로 그린다.
  - 가운데에 썸네일, 올린 칸의 설명, 진행 링을 보여 준다.
  - `WheelMath.layout(count:edge:)`와 `WheelMath.slot(point:layout:)`는 순수 함수다.
- PetController.swift: 드롭 경로(:890)를 `RingView` 칸에서 `ConvertWheel`로 바꾼다.
- 검사
  - 칸 맞추기: 틈, 두 고리, 반원, 원 밖이면 취소.
  - 종류별 칸 목록.
  - 새 항목마다 `--convert`로 실제 파일을 만들어 결과 확장자·크기가 0이 아닌지 본다. 표본 파일은 scratchpad에서 만든다.

## 5단계 — 서랍 최근 · 캡처 띠 · 클립보드 · 창 정리 도움말 · 작업 목록 (spec 8·10~12·7)
- Drawer.swift
  - 칼럼 위에 칩 줄을 둔다: [최근] [고정 폴더…] [+].
  - '최근'은 고정 폴더에서 7일 안에 바뀐 파일이다. 깊이 3, 최대 200개, 백그라운드에서 만들고 캐시한다.
  - 함수 `RecentFiles.collect(roots:now:)`로 만든다.
- Capture.swift / RingView: '캡처' 칸을 누르면 오늘 찍은 캡처 썸네일 띠를 보여 준다.
- Clipboard.swift `ClipWindow`
  - 검색 목록 모양으로 다시 그린다.
  - 고정 항목은 위쪽 칩 줄로 보여 주고, 항목마다 고정 버튼을 둔다.
- WindowSnap.swift
  - ⌃⌥를 누르고 있으면 단축키 도움말 패널을 띄운다.
  - 감지는 `flagsChanged` 전역 모니터로 하고, 창 정리가 켜져 있을 때만 동작한다.
- AgentPanel.swift `AgentListController`: 세션 카드 스택 A 모양으로 다시 그린다.
- 검사: 최근 파일 수집(임시 폴더에 날짜를 바꾼 파일을 만들어 확인). 클립보드 고정 정렬은 기존 검사를 유지한다.

## 끝
- README의 기능 설명을 갱신한다.
- 새 문맥에서 독립 검토를 하고, 이 plan과 다른 점을 보고한다.
- 커밋은 승인을 받은 뒤 한다.

## 변경 이력
- 2026-11-05 초안.

## 결과 (2026-11-05, 1~5단계 한 번에 — 사용자 요청)
- 확인함: `swift build` 종료 코드 0, `--selftest` 통과(일정 단계·N분 알림·기본값·승인만 알림·원형 메뉴 방향·변환 칸·변환 원 맞추기·CSV/엑셀·최근 파일·클립보드·⌃⌥ 판정 검사 추가). 새 변환 13개는 `--convert`로 실제 파일을 만들어 확인(ODT·XLSX·표 PDF·TIFF·1장 PDF·AIFF·MOV·대표 사진·PDF→JPG/TXT/작게/나누기/Word, XLSX→CSV 왕복 내용 일치).
- 집중 모드: ad-hoc 서명 시험 앱을 `open`으로 실행하니 권한 authorized, isFocused 읽힘 → 대안 b 불필요. 실행 파일을 직접 띄우면 TCC가 앱을 죽이므로 권한 요청은 번들 실행일 때만 함. (시험 앱 com.tasky.focusprobe의 권한 항목이 시스템에 남음)
- 화면 확인은 못 함(사용자 확인 필요).

## plan과 다른 점
- 원형 메뉴는 RingView를 바꾸지 않고 `Geometry.halfRing`·`ringDirection`(plan의 `RingMath.direction`)으로 만듦. '변환 결과 보기'·'쓰다듬기' 칸은 없어짐(결과는 말풍선 안내).
- 할 일 N분 알림 함수 이름은 `nudgeDue`. 변환 원 함수는 `WheelMath.layout(formats:actions:start:span:)`·`slot`. 원 밖에 놓으면 닫고 "칸 위에 놓아 주세요".
- 변환 칸은 자주 쓴 순 정렬 대신 고정 순서(시안처럼 형식 → 동작).
- 서랍: 왼쪽 목록을 없애 칩 순서 바꾸기(끌기)는 아직 없음(칩 오른쪽 클릭: Finder에서 보기·빼기). '최근'은 열 때마다 백그라운드로 새로 모음(캐시 안 함).
- 클립보드: 고정 항목은 칩 줄(6개)과 목록 맨 위 둘 다(키보드로 고르게).
- 받침대 보기 설정 키를 새로 두어(standMode) 기존 시계 설정은 기본값 '갖다대면'으로 시작.

## 독립 검토 반영 (2026-11-05)
- 받침대 구슬로 옮기는 사이 '봤음' 처리돼 구슬이 사라지던 것 → 받침대 위면 미룸.
- 받침대가 클릭·드롭을 막던 것 → 곰 아래로 내리고 구슬이 없으면 마우스 통과.
- 시작 알림 '10분 뒤'가 버려지던 것 → 시작 후 20분까지 다시 띄움.
- 클립보드 고정 항목을 키보드로 못 고르던 것 → 목록에도 둠.
- 변환 중 새로 연 원이 앞 변환 끝에 닫히던 것, 창 정리 끌 때 도움말 예약 취소.
- 남김(낮음): 캡처 띠 PNG 12장 메모리, 오늘 카드 클릭 대상 작은 누수, 짧은 답의 곰 '끝남' 반응.
