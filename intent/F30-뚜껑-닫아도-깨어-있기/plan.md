# F30 뚜껑 닫아도 깨어 있기 — plan
- 작성: 2026-11-06 · 근거: spec.md(승인됨) · 상태: 승인됨(2026-11-06)

## 단계
1. `Awake.swift`에 순수 함수를 둔다.
   - `LidSleep.sudoersLine(user:)`
   - `LidSleep.parseDisabled(pmsetOutput:)`
   - `Awake.lidShouldBlock(on:checked:onAC:percent:threshold:)`
   - → 확인: `Geometry.swift` 자체 검사에 위 세 가지를 넣고 `--selftest`가 통과한다.
2. `LidSleep`의 실행 부분을 만든다.
   - `isDisabled()`, `set(_:)`(sudo -n), `installed`, `install()`(osascript + visudo -cf + install), `uninstall()`
   - → 확인: `swift build`의 종료 코드가 0이다.
3. `Awake`에 기능을 더한다.
   - 설정 값 `lidAwake`, `lidAwakeBattery`
   - 기록 `lidAwakeApplied`
   - `syncLid()`, `restoreOnLaunch()`
   - 배터리 감시(`IOPSNotificationCreateRunLoopSource`)와 기준 아래 알림 한 번
   - `start`, `stop`, 시간 끝에서 `syncLid` 호출
   - → 확인: 빌드가 통과한다.
4. `PetController.swift`를 고친다.
   - 하위 메뉴에 체크 항목과 '배터리 보호 ▸'를 넣고 `refreshAwakeMenu`에 체크 표시를 더한다.
   - 설정 목록 `awakeSettings()`를 만든다.
   - 시작할 때 `restoreOnLaunch`, 종료할 때 `syncLid(false)`를 부른다.
   - → 확인: 빌드와 `--selftest`가 통과한다.
5. 실제로 실행해 확인한다(`scripts/make-app.sh` → `open`, 펫을 다시 띄워야 하니 사용자 확인 뒤).
   - 암호 설치를 사용자가 한다.
   - `pmset -g`가 1과 0으로 바뀌는지 본다.
   - `kill -9` 뒤 다시 실행해서 0으로 돌아오는지 본다.
   - 권한 제거 뒤 파일이 없는지 본다.
6. 새 문맥에서 독립 리뷰를 하고, 이 plan과 다른 점을 보고한다. CLAUDE.md의 권한 예외에 F30(sudoers)을 한 줄로 기록한다(사용자 결정 2026-11-06).

## 변경 이력
- 2026-11-06 초안

## 결과 (2026-11-06)
- 1~5단계 완료. 사용자가 실제로 확인했다(뚜껑을 닫은 채 깨어 있음, 1분 뒤 잠듦).
- plan과 다른 점
  - 닫힌 채로 0이 되면 잠들지 않아서, 되돌린 뒤 `LidSleep.sleepIfClosed()`로 재우는 동작을 더했다.
  - `--debug`일 때만 시간에 '1분'을 넣었다(테스트용).
  - 배터리 알림에 되돌리기가 필요 없어서 `DoneToast`의 undo를 선택으로 바꿨다.
- 6단계의 독립 리뷰는 아직 하지 않았다.
