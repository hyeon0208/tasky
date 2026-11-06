# F30 뚜껑 닫아도 깨어 있기 — spec
- 작성: 2026-11-06 · 근거: ~/work/proposal/tasky/lid-awake/intent.md(승인됨 2026-11-06), 디자인 생략 · 상태: 승인됨(2026-11-06)

## 지금 상태 (코드로 확인)
- `Awake.swift`: `start(minutes:)`가 `PreventUserIdleDisplaySleep` assertion을 만들고, `stop()`이 그것을 푼다. 끝 시각은 `DispatchWorkItem`이 맡는다. `onChange`가 있다.
- 켜고 끄는 길은 네 군데다. 메뉴 막대 하위 메뉴(`PetController.swift:1917`), 오른쪽 클릭(2002), 원형 메뉴(762, 1773), 단축 동작(706). 모두 `Awake.shared.start/stop`을 부르므로 `Awake` 안에서만 고치면 된다.
- 설정 창에는 '잠 안 자기' 목록이 없다. 목록은 `PetController.swift:1105~1167`의 `SettingsTab` 배열에 있다.
- 이 Mac은 지금 `pmset -g`의 SleepDisabled가 0이다. 배터리가 있다. `/etc/sudoers.d`는 비어 있다.

## 우려 사항과 결정
1. **켜고 끄는 명령 — 추천: `/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1|0`을 `Process`로 실행한다.** 종료 코드가 0이 아니면 실패로 본다. 체크를 꺼 버리지는 않고, 한 번 알린다.
2. **권한 설치 — 추천: 처음 체크할 때 `osascript -e 'do shell script "…" with administrator privileges'`를 한 번 실행한다.**
   - 하는 일은 셋이다. 임시 파일에 sudoers 내용을 쓰고, `visudo -cf`로 검사하고, 통과하면 `install -m 0440 -o root -g wheel`로 `/etc/sudoers.d/tasky`에 넣는다.
   - 내용은 `<사용자> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1` 한 줄이다. 사용자 이름은 `NSUserName()`이다.
   - 암호 창을 취소하면 체크를 되돌린다.
   - 설치 여부는 파일이 있고 `sudo -n -l /usr/bin/pmset -a disablesleep 1`이 성공하는지로 판단한다.
3. **권한 제거 — 같은 osascript 방식으로 `rm -f /etc/sudoers.d/tasky`를 실행한다(암호를 한 번 묻는다).** 제거하기 전에 뚜껑 막기를 먼저 0으로 되돌리고, 체크를 끈다.
4. **켜기 전 값 기억과 비정상 종료 복구 — UserDefaults `lidAwakeApplied`(Bool)로 기록한다.**
   - 켤 때 `pmset -g`에서 SleepDisabled를 읽는다. 이미 1이면 사용자가 직접 켠 값이므로 아무것도 하지 않고 기록도 남기지 않는다. 0이면 1로 바꾸고 `lidAwakeApplied=true`로 둔다.
   - 되돌릴 때는 `lidAwakeApplied`가 true일 때만 0으로 바꾸고 false로 둔다.
   - 앱이 시작할 때 `lidAwakeApplied`가 true면 0으로 되돌린다. 켜짐 상태는 저장하지 않으므로(F23 결정) 시작할 때 항상 꺼져 있다.
5. **언제 적용하나 — 잠 안 자기가 켜져 있고, 체크가 켜져 있고, 배터리가 기준을 넘을 때만 1이다(`Awake.syncLid()` 한 곳에서 판단).** `start`, `stop`, 시간 끝, 체크 바꿈, 배터리 변화, 종료 때 이 함수를 부른다. 종료는 `applicationWillTerminate`에서 처리한다.
6. **배터리 — `IOPSNotificationCreateRunLoopSource`로 변화를 받는다. % 값은 `IOPSCopyPowerSourcesInfo`의 Current/Max Capacity로 계산한다.**
   - 전원에 연결된 동안에는 기준을 보지 않는다(추정: 충전 중이면 막을 이유가 없다).
   - 기준 이하로 떨어져 막기를 풀면 알림을 한 번 띄운다. 문구는 "배터리가 30% 아래라 뚜껑을 닫으면 잠들어요"다. 다시 기준 위로 올라오면(충전) 막기가 다시 켜진다.
   - 타이머는 쓰지 않는다.
7. **설정 — UserDefaults `lidAwake`(Bool, 기본 false), `lidAwakeBattery`(Int, 기본 30, 10/20/30/50).**
8. **메뉴 막대 하위 메뉴 — '끄기' 아래에 구분선, "뚜껑 닫아도 깨어 있기"(체크)를 둔다.** 배터리 기준은 하위 메뉴 "배터리 보호" 안에 10%/20%/30%/50%를 체크로 넣는다.
9. **설정 창 '잠 안 자기' 목록(symbol `cup.and.saucer`) — 네 항목이다.**
   - 기본 시간: 팝업. `Awake.minutes`(오른쪽 클릭 시간)를 바꾼다.
   - 뚜껑 닫아도 깨어 있기: 체크.
   - 배터리 보호 기준: 팝업.
   - 권한 상태와 "권한 제거" 버튼: 설치되었을 때만 보인다.
   - 안내 한 줄: "뚜껑을 닫은 채 가방에 넣으면 뜨거워질 수 있어요."

## 요구사항
- R1. 체크가 꺼져 있으면 지금과 똑같이 동작하고, 암호를 묻지 않는다.
- R2. 체크하고 잠 안 자기가 켜지면 SleepDisabled가 1이 된다. 잠 안 자기를 끄거나 시간이 끝나거나 체크를 끄거나 Tasky를 끄면 0이 된다.
- R3. 강제 종료한 뒤 다시 실행하면 0으로 돌아온다. 원래 1이었으면 손대지 않는다.
- R4. 배터리 기준 이하(전원 미연결)에서는 0이 된다.
- R5. 암호는 처음 설치할 때와 권한을 제거할 때만 묻는다.

## 설계
- `Awake.swift`
  - 추가: `enum LidSleep`. `isDisabled()`(pmset -g 읽기), `set(_:) -> Bool`(sudo -n), `installed`, `install() -> Bool`, `uninstall()`을 둔다.
  - `Awake`에 `syncLid()`, 배터리 감시, 설정 값을 더한다.
- `PetController.swift`
  - 하위 메뉴 항목과 `refreshAwakeMenu` 체크 표시
  - 설정 목록 `awakeSettings()`
  - 시작할 때 복구 호출, 종료 때 `syncLid` 호출
- `Geometry.swift` 자체 검사: sudoers 한 줄 생성, `pmset -g` 출력에서 SleepDisabled 읽기, 적용 판단(켜짐·체크·전원·%·기준 조합).

## 검증 방법
- 자체 검사: 위 세 가지(순수 함수로 뺀다).
- 내가 확인할 수 있는 것:
  - 설치 뒤 `cat /etc/sudoers.d/tasky`와 `sudo -n -l`로 확인한다.
  - 켜고 끄면서 `pmset -g | grep SleepDisabled`가 1과 0으로 바뀌는지 본다.
  - `kill -9` 뒤 다시 실행하면 0이 되는지 본다.
  - 권한 제거 뒤 파일이 없는지 본다.
  - 단, 암호 입력은 사용자가 해야 한다.
- 사용자만 확인할 수 있는 것: 뚜껑을 닫고 5분 뒤 음악 재생이나 ping이 계속되는지, 배터리 기준 동작(실제 %를 바꿀 수 없으므로 기준을 50%로 두고 확인하거나 판단 함수 검사로 대신한다).

## 변경 이력
- 2026-11-06 초안
- 2026-11-06 사용자 승인
