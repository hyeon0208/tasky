# F32 끝낸 할 일 취소선 — plan

- 상태: done (구현 2026-11-06, 화면 확인 대기)
- 작성일: 2026-11-06
- spec: ./spec.md (approved 2026-11-06)
- 변경 이력
  - 2026-11-06: 최초 작성

## 목표
오늘 끝낸 미리 알림이 오늘 카드와 할 일 창의 맨 아래에 흐린 취소선으로 남고, 체크를 풀면 원래 자리로 돌아간다.

## 근거로 확인한 API·코드
- 오늘 끝낸 미리 알림 조회 `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)` — Tasks.swift:294 (이미 쓰는 중, 지금은 개수만 씀)
- `EKReminder.completionDate: Date?`, `isCompleted` — EventKit (complete()가 isCompleted를 씀, Tasks.swift:387)
- `NSNotification.Name.NSCalendarDayChanged` — Foundation(macOS 10.9+)
- `TaskItem` — Tasks.swift:108 / `doneToday` — Tasks.swift:198·295·951
- 오늘 카드 할 일 줄 — Today.swift:371-379 / 할 일 창 목록 `reload()` — Tasks.swift:941-973, 줄 `row(_:)` — Tasks.swift:1047
- 자체 검사 `TaskLogic` 묶음 — Geometry.swift:726-750

## 파일 맵
- 수정: `Sources/Tasky/Tasks.swift` — TaskItem·TaskLogic·TaskStore(데이터), TaskWindow(할 일 창 그리기)
- 수정: `Sources/Tasky/Today.swift:359-379` — 오늘 카드 그리기
- 테스트: `Sources/Tasky/Geometry.swift` — `--selftest` 검사 추가

## 단계
### 1. 데이터: 오늘 끝낸 항목 보관·완료 풀기
- 목표 기여: 카드·창이 그릴 끝낸 항목과 되돌리는 동작을 제공한다.
- 파일: Tasks.swift
- 할 일:
  - `TaskItem`에 `var doneAt: Date? = nil`.
  - `TaskLogic.doneToday(_ items: [TaskItem], now: Date, calendar: Calendar = .current) -> [TaskItem]` — `doneAt >= startOfDay(now)`만, `doneAt` 내림차순.
  - `TaskStore.doneItems: [TaskItem]`(private(set)). 294행 조회 결과를 `done: true, doneAt: r.completionDate`로 담는다. `doneToday`는 `var doneToday: Int { doneItems.count }`로 바꾼다. 미리 알림을 끄면(285행 경로) `doneItems = []`.
  - `TaskStore.uncomplete(_ item: TaskItem)` — `isCompleted = false`, `try? save(commit: true)`, `reload()`.
  - `start()`의 감시 등록(258행)과 같은 자리에서 `.NSCalendarDayChanged` → `reload()`(main 큐).
- 검사: `swift build` 종료 코드 0; `--selftest`에 `doneToday` 검사 1개(어제 23:59 제외 · 오늘 00:01 포함 · 최근 것 먼저) → `selftest ok`
- [ ] 완료

### 2. 오늘 카드
- 목표 기여: 카드 맨 아래에 끝낸 항목을 취소선으로 보인다(성공 기준 1).
- 파일: Today.swift `rebuild()`
- 할 일:
  - 남은 할 일 4줄 + "외 N개"는 그대로. 그 뒤 `TaskLogic.doneToday(store.doneItems, now:)`의 앞 3개를 줄로, 넘치면 `"끝낸 것 외 N개"` 라벨(11pt, secondaryLabelColor — 기존 "외 N개"와 같음).
  - 끝낸 줄: `ClosureButton(switch)`, `state = .on`, `attributedTitle` = 13pt·`secondaryLabelColor`·`.strikethroughStyle: NSUnderlineStyle.single`. 누르면 `TaskStore.shared.uncomplete(item)`. 휴지통 감싸기(`trashRow`) 안 함.
  - "남은 할 일이 없어요" 라벨은 남은 것이 0일 때 그대로 두고 그 아래에 끝낸 줄.
- 검사: `swift build` 종료 코드 0. 화면은 사용자 확인.
- [ ] 완료

### 3. 할 일 창
- 목표 기여: 할 일 창 왼쪽 열에도 끝낸 항목을 남긴다(인터뷰 결정 "둘 다").
- 파일: Tasks.swift `TaskWindow.reload()`·`row(_:)`
- 할 일:
  - 971행 그룹을 `[(nil, g.today), ("날짜 없음", g.undated), ("끝냄", TaskLogic.doneToday(store.doneItems, now:))]`로. 개수 제한 없음. 빈 목록 판단(957행)은 그대로 — 끝낸 것만 있으면 '끝냄'만 보인다.
  - `colTitles.0` 숫자(954행)는 남은 것만 그대로.
  - `row(_:)`: `item.done`이면 체크박스 `state = .on`·누르면 `uncomplete`, 제목 `secondaryLabelColor`+취소선, `overdue` 빨간색 끔. 오른쪽 클릭 메뉴·두 번 눌러 고치기는 그대로.
- 검사: `swift build` 종료 코드 0. 화면은 사용자 확인.
- [ ] 완료

### 4. 전체 확인·리뷰
- 검사: `swift build` 종료 코드 0 → `TASKY_HOME=$(mktemp -d) .build/debug/Tasky --selftest` → `selftest ok`. 새 문맥 독립 리뷰 1회, plan과 다른 점 보고.
- 사용자 확인 요청: 체크 → 맨 아래 취소선 / 체크 풀기 → 미리 알림 앱에서 미완료·원래 자리 / 휴지통·일정 그대로 / 다음 날 사라짐.
- [ ] 완료

## Not now
- 끝낸 줄의 휴지통 · 끝낸 항목 되돌리기 토스트 · 일정 완료 표시

## 진행 기록
- [ ] 1  - [ ] 2  - [ ] 3  - [ ] 4

## 결정(Ruling)
- 2026-11-06 단계 1: 끝낸 항목을 `items`와 따로 둔다 — 알림·배지·`pending`이 `items`를 쓰므로 섞으면 곳곳에 거르기가 필요 — 틀리면 끝낸 항목이 알림·남은 수에 섞임

## 결과 (2026-11-06)
- 1~4단계 완료. `swift build` 0, `--selftest` ok(오늘 끝낸 할 일 검사 추가). 독립 리뷰: 문제 없음.
- 확인 못 함: 화면(취소선 줄·체크 풀기·미리 알림 앱 동기화·자정 뒤 사라짐).
