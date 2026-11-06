# F32 끝낸 할 일 취소선 — spec

- 상태: approved (2026-11-06)
- 작성일: 2026-11-06
- intent: ~/work/proposal/tasky/task-strike/intent.md (승인됨 2026-11-06)
- 변경 이력
  - 2026-11-06: 최초 작성. 인터뷰 결정: 할 일 창에도 적용, 남은 것·끝낸 것 줄 수를 따로 정함

## 설계 요약
`TaskStore.reload()`가 이미 읽고 있는 '오늘 끝낸 미리 알림'을 개수만이 아니라 항목으로 보관한다(`doneItems`). 오늘 카드와 할 일 창은 끝내지 않은 할 일 아래에 이 항목들을 흐린 취소선으로 그리고, 체크를 풀면 미리 알림의 완료를 푼다. 알림·진행률·배지 계산이 쓰는 `items`에는 넣지 않아 기존 동작이 바뀌지 않는다.

## 구성
- `TaskItem`(Tasks.swift): `doneAt: Date?` 추가(끝낸 시각, 정렬·날짜 판정용). 기존 `done`은 그대로(빠른 실행 검색이 씀).
- `TaskLogic.doneToday(_ items:, now:, calendar:) -> [TaskItem]`(순수, 자체 검사 대상): `doneAt`이 `now`의 자정 이후인 것만, 최근에 끝낸 것부터.
- `TaskStore`
  - `doneItems: [TaskItem]` — reload의 두 번째 조회(`predicateForCompletedReminders(오늘 자정~지금)`) 결과를 `done: true, doneAt: completionDate`로 담는다. `doneToday`(개수)는 `doneItems.count`로 계산되게 바꾼다.
  - `uncomplete(_ item:)` — `isCompleted = false`로 저장하고 reload. 토스트 없음(intent에 없음).
  - `start()`에서 `.NSCalendarDayChanged`를 받아 reload(자정이 지나면 어제 끝낸 것과 진행률이 바로 바뀌게).
- 오늘 카드(Today.swift `rebuild()`): 남은 할 일 4줄 + "외 N개"(지금 그대로) 아래에 끝낸 할 일 **최대 3줄** + 넘치면 "끝낸 것 외 N개". 남은 할 일이 없으면 "남은 할 일이 없어요" 다음에 끝낸 줄. 블록 제목 "할 일 N"은 남은 수 그대로.
- 할 일 창(Tasks.swift `TaskWindow.reload()`): 왼쪽 열 그룹을 `오늘 → 날짜 없음 → 끝냄`으로. '끝냄'은 개수 제한 없이 모두(창이 스크롤됨). 오른쪽 '다가오는 일'은 그대로.
- 끝낸 줄 모양(두 곳 공통): 체크박스 켜짐, 제목은 `secondaryLabelColor` + 취소선(`NSAttributedString` `.strikethroughStyle`). 누르면 `uncomplete`. 할 일 창의 시간 글씨는 남기되 지난 마감도 빨간색으로 칠하지 않는다.

## 데이터 흐름
체크 → `complete()`(지금 그대로: 완료 저장 + 4초 되돌리기 토스트) → reload → 미완료 목록에서 빠지고 `doneItems` 맨 위에 들어옴 → 카드·창이 `onChange`/알림으로 다시 그림.
체크 풀기 → `uncomplete()` → reload → `doneItems`에서 빠지고 마감 날짜 기준 원래 묶음(오늘/날짜 없음/다가오는)으로 돌아감.
자정 → `NSCalendarDayChanged` → reload → 오늘 자정 기준으로 다시 조회. 그리기 때도 `TaskLogic.doneToday(now)`로 한 번 더 거른다(알림을 놓쳐도 어제 것이 안 보이게).

## 오류 처리
- 완료 풀기 저장 실패: 지금 `complete()`처럼 `try?`로 넘기고 reload(화면은 실제 상태로 돌아옴).
- 바꿀 수 없는 목록의 미리 알림: 체크박스를 눌러도 저장이 실패해 상태가 그대로 보인다(지금 `complete()`와 같음).

## 확인 방법
- `swift build` 종료 코드 0.
- `--selftest`에 추가: `doneToday` — 어제 23:59 끝낸 것 제외, 오늘 00:01 포함, 최근 것 먼저(3건).
- 실제 실행(`open dist/Tasky.app` 또는 `--debug`)에서 사용자 확인 필요: 체크 → 맨 아래 취소선 / 체크 풀기 → 미리 알림 앱에서 미완료 / 휴지통·일정 그대로. 화면을 볼 수 없으므로 이 부분은 "확인 못 함"으로 보고한다.

## 고려한 대안
- 끝낸 항목을 `items`에 섞기: 알림(`due`)·남은 할 일 수·배지·`pending`이 모두 `items`를 써서 곳곳에 `!done` 거르기가 필요하다. 따로 두는 쪽이 바뀌는 곳이 적다.
- Tasky가 끝낸 기록을 따로 저장: intent에서 제외(미리 알림 완료 값만 씀).

## 우려
- **[결정 필요] 오늘 카드의 끝낸 줄 수를 3줄로 정했다.** 인터뷰 답("구분해서 정했으면")을 남은 4줄·끝낸 3줄로 읽었다. 다른 수를 원하면 알려 주세요.
- 끝낸 줄에 휴지통은 두지 않는다(intent: 휴지통 동작 그대로 = 지금처럼 남은 항목에서만). 할 일 창의 오른쪽 클릭 '고치기·삭제'는 같은 줄 함수라 끝낸 줄에도 남는다.
- 날짜가 미래인 미리 알림도 오늘 끝냈으면 '끝냄'에 보인다(intent "오늘 끝낸 미리 알림" 그대로).
- 오늘 카드가 끝낸 줄만큼 길어진다(최대 4줄 늘어남).
