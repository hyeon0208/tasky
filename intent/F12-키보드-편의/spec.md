# F12 키보드 편의 — spec
- 작성: 2026-10-27 · 근거: intent.md(승인됨) · 상태: 승인됨(2026-10-27)

## 이 Mac의 지금 상태 (확인함)
- 입력 소스: ABC, 한국어 2벌식(`com.apple.inputmethod.Korean.2SetKorean`)
- 키 반복: InitialKeyRepeat 15, KeyRepeat 2 (시스템 설정의 가장 빠른 값)
- hidutil 사용자 키 매핑: 없음

## 우려 사항 (모두 결정됨)
1. ✅ **Caps Lock을 어떻게 가로챌지 — 결정: hidutil 방식(추천안).** macOS는 Caps Lock을 누르는 순간 하드웨어 단계에서 대문자 고정을 켜 버려서, 일반 키 감지로는 '짧게 누름'만 막을 수 없다.
   - 추천: `hidutil`로 Caps Lock을 쓰지 않는 키(F18)로 바꿔 두고, F18을 짧게 누르면 한영 전환, 길게 누르면 코드로 대문자 고정을 켜고 끈다. 권한이 필요 없는 공식 명령이고 gksdud 같은 앱도 비슷하게 한다.
   - 다른 길: 키 이벤트를 가로채 지우기(손쉬운 사용 권한 필요). Caps Lock 불빛·상태가 이미 바뀐 뒤라 믿기 어렵다.
2. ✅ **콩깍지가 꺼졌을 때 Caps Lock — 결정: 추천안.** 1의 바꿈은 Mac을 다시 켤 때까지 남는다. 콩깍지가 비정상 종료되면 Caps Lock이 아무 일도 안 하는 키가 된다.
   - 추천: 정상 종료·기능 끄기 때 원래대로 되돌리고, 다음 실행 때 다시 건다. 비정상 종료 뒤에는 콩깍지를 다시 켜거나 Mac을 다시 시작하면 돌아온다(설정 화면에 한 줄 안내).
3. ✅ **필요한 권한 — 결정: 입력 모니터링 하나.** 키를 읽기만 하면 되므로(1을 쓰면 지울 필요 없음) **입력 모니터링 하나**로 충분하다. intent에 적은 손쉬운 사용 권한은 받지 않는다(권한을 줄이는 방향).
   - 지금은 `.app`으로 포장하지 않은 실행 파일이라, 권한 목록에 Kongpod 또는 실행한 터미널 앱으로 보이고, 다시 빌드하면 권한을 다시 줘야 할 수 있다. 화면 확인 때 사용자가 겪을 수 있음.
4. ✅ **어느 입력 소스끼리 바꿀지 — 결정: 한국어·영문 자동.** 추천: 켜져 있는 입력 소스에서 한국어 하나와 영문(ABC 등) 하나를 자동으로 찾아 둘 사이를 오간다. 지금이 한국어가 아니면 한국어로, 한국어면 영문으로. 둘 중 하나가 없으면 이 기능은 꺼진 채 안내한다.

5. ✅ **기본값 — 결정:** 한영 전환은 기본 꺼짐. 사용자가 켤 때만 감지·Caps Lock 바꿈·권한 요청을 한다(gksdud와 겹치지 않게).
6. ✅ **gksdud와 함께 켜졌을 때 — 결정: 안내 없음.** 기본 꺼짐이라 켤 때 사용자가 판단한다. (아래는 검토 당시 설명) 둘 다 같은 키를 바꾸면 한 번 눌러 두 번 전환(되돌아감)될 수 있다. 추천: 켤 때 gksdud가 실행 중이면 "다른 한영 전환 앱이 켜져 있어 겹칠 수 있어요" 한 줄만 보여 준다(앱 이름·홍보 없이, 끄거나 켜는 것은 사용자가 정함).

## 참고: gksdud 방식 (실행 파일의 사용 함수로 확인)
- Caps Lock 바꿈: `hidutil` 명령을 부르지는 않지만, 같은 일을 하는 HID 키보드 속성(`HIDKeyboardModifierMappingSrc/Dst`)을 `IOHIDServiceClientSetProperty`로 직접 설정한다. → hidutil과 같은 원리.
- 감지: `IOHIDManager`(입력 모니터링 권한, `IOHIDRequestAccess`) + `CGEventTap`·`AXIsProcessTrusted`(손쉬운 사용 권한).
- 대문자 고정: `IOHIDSetModifierLockState`.
- 우리 추천안(우려 1·3)은 같은 원리에서 손쉬운 사용 권한만 빼는 것.

## 요구사항
- R1. 설정 '키보드' 구역: 한영 전환 켜기(기본 꺼짐), 전환 키(Caps Lock·오른쪽 ⌘·오른쪽 ⌥, 기본 Caps Lock), 권한 상태와 '권한 열기' 버튼.
- R2. 전환 키를 **혼자** 눌렀다 뗄 때만 전환한다(⌘C처럼 다른 키와 함께 누르면 전환 안 함).
- R3. Caps Lock: 0.5초 미만 = 전환, 0.5초 이상 = 대문자 고정 켜기/끄기.
- R4. 키 반복 슬라이더 2개(반복 시작 10~120, 반복 속도 1~120, 단위 15ms), 옆에 ms 표시, "로그아웃 후 모든 앱에 적용돼요" 안내.
- R5. 처음 바꿀 때 원래 값을 기억하고, '되돌리기'는 그 값으로(원래 값이 없었으면 키를 지워 시스템 기본으로).
- R6. 끄면 키 감지를 멈추고 Caps Lock 바꿈을 되돌린다. 읽은 키는 저장·전송하지 않는다.

## 설계
### 새 파일 `Keyboard.swift`
- `KeySwitcher`
  - 감지: 듣기 전용 이벤트 탭(`CGEvent.tapCreate`, `.listenOnly`, keyDown·keyUp·flagsChanged). 권한 확인 `CGPreflightListenEventAccess`, 요청 `CGRequestListenEventAccess`.
  - 판정은 순수 구조체 `SwitchJudge`로 분리: (이벤트 순서, 시각) → 전환 / 대문자 고정 / 없음. 자체 검사 대상.
  - 전환: `TISCreateInputSourceList`로 켜진 소스 중 한국어·영문을 찾고 `TISSelectInputSource`.
  - 대문자 고정: `IOHIDSetModifierLockState(kIOHIDCapsLockState)`.
  - Caps Lock 바꿈: `hidutil property --set '{"UserKeyMapping":[{Caps→F18}]}'`. 원래 매핑을 읽어 우리 항목만 더하고 뺀다(설정 파일 규칙과 같게).
- `KeyRepeat`
  - 읽기·쓰기: `CFPreferences`의 전역 도메인(`defaults -g`와 같은 곳). 원래 값은 우리 UserDefaults에 한 번만 저장.
  - 값 ↔ ms 변환(×15)은 순수 함수.

### 바뀌는 곳
- `PetController.swift`: 설정 창에 '키보드' 구역(모든 펫 공통 값).
- `App`: 실행 때 켜져 있으면 감지 시작, 종료(`willTerminate`) 때 Caps Lock 바꿈 되돌리기.
- `Geometry.swift` SelfTest: 판정·변환·매핑 합치기 검사.

## 검증 방법
- 자체 검사: 혼자 누름만 전환, 다른 키와 함께면 안 함, Caps 0.5초 경계, 오른쪽 ⌘·⌥ 키 코드 구분(왼쪽은 무시), ms 변환, hidutil 매핑 합치기·빼기(기존 항목 보존), 되돌리기 값 계산.
- 실제 입력 소스 전환·대문자 고정·권한 창·로그아웃 후 반복 속도는 사용자 확인.

## 변경 이력
- 2026-10-27 초안
- 2026-10-27 기본 꺼짐 결정, gksdud 방식 확인(HID 속성 직접 설정 = hidutil과 같은 원리), 우려 6 추가
- 2026-10-27 우려 1~4 추천안, 우려 6 안내 없음으로 결정
- 2026-10-27 사용자 승인
