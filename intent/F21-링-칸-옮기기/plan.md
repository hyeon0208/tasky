# F21 링 칸 옮기기 — plan
- 작성: 2026-10-30 · 근거: spec.md(승인됨) · 상태: 초안(승인 대기)

## 파일
| 파일 | 할 일 |
|---|---|
| `RingView.swift` | `Slot.id` 추가, `RingOrder`(순수: `apply`·`move`), 누름 0.3초 타이머·들기 상태, 젤리 스프링 갱신(`Ticker` '링 칸 옮기기', 움직이는 동안만), `mouseDown` 실행 → `mouseUp`, Esc 취소, `onReorder`, `reorderable`(드롭 변환 링은 false) |
| `PetController.swift` | `mainSlots`에 id 부여·저장 순서 적용, `onReorder`에서 `ringOrder` 저장, 설정 '일반'에 '원형 메뉴 순서 처음대로' |
| `Geometry.swift` | SelfTest에 `RingOrder` 검사 |
| 문서 | README 원형 메뉴 절 한 줄, plan 이력 |

## 순서
1. `RingOrder` + 자체 검사.
2. 클릭을 `mouseUp`으로, 누름 타이머·들기(1.15배 확인 반응).
3. 들고 움직이기: 든 칸 따라가기, 40pt 안이면 순서 바꾸기, 젤리 늘어남·출렁 스프링.
4. 놓기·Esc·저장, 숫자 키·접근성 순서.
5. `PetController` 연결·설정 버튼.
6. 빌드(종료 코드)·자체 검사 → 독립 검토 → 반영 → 문서·커밋·푸시.

## 검사
- 자체 검사: 저장 순서 적용(새 칸 기본 자리에 끼움·없어진 칸 무시·빈 저장=기본), move 앞·뒤.
- 사용자 확인: 꾹 눌러 들기, 젤리 움직임, 저장 유지, 짧은 클릭 실행, 알약 부채꼴·가장자리 반원에서 동작, 동작 줄이기.

## 변경 이력
- 2026-10-30 초안
