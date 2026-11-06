# F31 한영 전환 세부 설정 — spec
- 작성: 2026-11-06 · 근거: ~/work/proposal/tasky/input-switch/intent.md(승인됨) · 상태: 승인됨(2026-11-06, spec·plan·구현 한 번에 검토)

## 설정 값(UserDefaults)
| 키 | 값 | 기본 |
|---|---|---|
| `kbLongPressCaps` | Bool — ① 길게 눌러 대문자 고정 | true |
| `kbKeepCaps` | Bool — ② 전환 시 대소문자 유지 | false |
| `kbInternalKey` | "f13"…"f20" — ③ 내부 전환 키 | "f18" |
| `kbInternalKeyChosen` | Bool — 사용자가 ③을 한 번이라도 골랐는지 | false |
| `kbHotkey60Original` | 바꾸기 전 시스템 단축키 60(plist Data, 없었으면 빈 Data) | 없음 |
| `kbDevices` | [vid:pid: {name, use(off/default/on), key(default/capsLock/rightCommand/rightOption)}] — ④ | 빈 값 |

## 동작
- ① 끄면 `SwitchJudge`가 길게 누르기(`capsInstead`)를 내지 않는다.
- ② 꺼져 있으면 전환할 때(누르는 순간) 대문자 고정이 켜져 있으면 끈다. 이때 끈 기록을 두어, 같은 누름이 0.5초 길게 누르기가 되면 입력만 되돌리고 대문자 고정은 끈 채 둔다(켜진 대문자 고정을 길게 눌러 끄는 동작이 그대로 되게).
- ③ Caps는 장치마다 hidutil로 `Caps → 내부 키`(F13–F20 HID 0x68–0x6F)로 바꾼다. 감지는 내부 키의 가상 키 코드(F13 105, F14 107, F15 113, F16 106, F17 64, F18 79, F19 80, F20 90)를 본다.
  - 사용자가 ③을 고른 뒤로는, 기능이 켜져 있고 Caps를 쓰는 키보드가 있으면 시스템 단축키 60(이전 입력 소스)을 내부 키(수정키 없음, fn 표시 0x800000)로 맞춘다. 처음 바꾸기 전 값을 저장한다. 기능이 꺼지면(다음 실행 때 포함) 저장한 값으로 되돌린다. 쓰기는 CFPreferences + `activateSettings -u`.
  - 단축키가 내부 키와 같으면 지금처럼 macOS에 맡긴다(nativeSwitch). 아니면 TISSelectInputSource.
  - 팝업에서 단축키 60·61이 아닌 다른 켜진 시스템 단축키가 쓰는 키는 흐리게(고를 수 없게) 한다.
- ④ 키보드 = IOHIDManager로 찾은 PrimaryUsage 키보드(1/6), vid:pid로 구분. 연결된 키보드는 기억한다.
  - 사용 여부: 켬 / 끔 / 기본값(=전체 '한 키로 한영 바꾸기'). 쓸 키: 기본값(=전체 '쓸 키') / Caps / 오른쪽 ⌘ / 오른쪽 ⌥.
  - Caps 매핑은 장치마다(`--matching {VendorID, ProductID, PrimaryUsagePage 1, PrimaryUsage 6}`) 건다. 그래서 '내장 끔, 외장 켬'이면 내장 Caps는 원래 대문자 고정이다.
  - 감지할 키 = 켜진 키보드들의 쓸 키를 모은 것. 키보드를 찾지 못하면 예전처럼 전체 설정 하나만.
  - 연결 안 된 키보드는 목록에서 지울 수 있다.

## 한계(추정 아님, 구조상)
- 오른쪽 ⌘·⌥는 키 이벤트에 장치 정보가 없어 키보드를 구분하지 못한다. 어느 키보드든 켜진 키보드 하나가 오른쪽 ⌘을 쓰면 모든 키보드의 오른쪽 ⌘ 단독 누름이 전환한다. 장치별 구분이 정확한 것은 Caps뿐이다.
- 설정 창은 다시 그리지 않으므로 ①은 쓸 키가 Caps가 아닐 때 숨기지 않고 흐리게 한다. 지운 키보드는 창을 다시 열 때 목록에서 빠진다.

## 성공 기준
intent의 1–5. 자체 검사: 판정(①), 내부 키 코드표, 매핑 항목 구분(다른 내부 키 항목도 우리 것으로 지움), 시스템 단축키 파싱.

## 변경 이력
- 2026-11-06 초안
