# F23 잠 안 자기 — plan
- 작성: 2026-10-30 · 근거: spec.md(승인됨) · 상태: 구현됨, 화면 확인 대기

## 파일
| 파일 | 할 일 |
|---|---|
| `Awake.swift`(새) | `Awake`: `IOPMAssertionCreateWithName(PreventUserIdleDisplaySleep)` 켜기/끄기, 끝 시각 `DispatchWorkItem`, 남은 시간 글자, 마지막 시간 저장(`awakeMinutes`, 0=영원히). `AwakeIcon`: 곰 + 컵·손·김 3프레임 23×18 템플릿 그리기 |
| `PetController.swift` `App` | `statusItem.menu` 빼고 왼쪽=메뉴 열기, 오른쪽·⌃클릭=바로 켜기/끄기. 길이 23pt. 메뉴에 '잠 안 자기' 하위 메뉴(15분·1시간·2시간·5시간·12시간·영원히·끄기, 체크 표시, 남은 시간). 켜진 동안 `Ticker` '잠 안 자기 김'(1초)로 프레임 교체, 동작 줄이기면 고정 |
| `Geometry.swift` | SelfTest: 남은 시간 글자, 끝 시각 계산, 영원히=끝 없음 |
| 문서 | README 한 절, plan 이력 |

## 순서
1. `Awake` 순수 계산(남은 시간 글자·끝 시각) + 자체 검사 → `swift build`, `--selftest`.
2. assertion 켜기/끄기 → 실행 후 `pmset -g assertions`에서 Tasky 항목 확인/사라짐 확인.
3. 클릭 나누기 + 하위 메뉴.
4. C2 아이콘·김 프레임.
5. 새 문맥 검토 → 반영 → README·커밋·푸시.

## 검사
- 빌드 종료 코드 0, `--selftest` 통과.
- `pmset -g assertions`로 켜짐/꺼짐 확인(제가 함).
- 확인 못 하는 것: 오른쪽 클릭 느낌, 아이콘 모습·김 움직임 → 사용자 화면 확인.

## 변경 이력
- 2026-10-30 초안
- 2026-10-30 승인("시작"), 구현. 빌드·자체 검사 통과, `pmset -g assertions`에서 같은 호출로 `PreventUserIdleDisplaySleep named: "Tasky keep awake"` 확인(한글 이름은 빈칸으로 보여 영어로 바꿈)
- 계획과 다른 점: 상태 항목 길이를 고정 정사각형에서 가변으로(23pt 아이콘이 잘리지 않게)
- 검토에서 남긴 작은 점(고치지 않음): 메뉴가 마우스를 뗄 때 열림, 메뉴가 열린 채 저절로 꺼지면 다시 열 때까지 이전 표시, 동작 줄이기를 켜고 끄면 다음 켜기부터 반영
