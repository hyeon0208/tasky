# F24 할 일·일정 — spec
- 작성: 2026-11-02 · 근거: intent.md(승인됨 2026-11-02) · 상태: 승인됨(2026-11-03)

## 지금 상태 (코드로 확인)
- 링 칸: `Slot(title:symbol:id:)`(PetController.swift:628), 순서는 `RingOrder.apply`(새 칸은 기본 앞 칸 뒤에 붙음).
- 알약: `petView.island` / `islandContent(expanded:)`(PetController.swift:176), 작업 알림이 펼침을 쓴다.
- 소리: `NSSound(named:)`(AgentPanel.swift:241). 설정 탭: `SettingsTab(id:title:symbol:content:)`(PetController.swift:976).
- 앱 번들: `scripts/make-app.sh`가 Info.plist를 만든다. 지금은 권한 설명 키가 없다.

## 우려 사항
1. **권한 설명 키와 번들.** EventKit은 Info.plist에 `NSRemindersFullAccessUsageDescription`, `NSCalendarsFullAccessUsageDescription`가 없으면 요청할 때 앱이 죽는다(추정, 문서 기준). `make-app.sh`에 두 키를 넣는다. 번들이 아닌 `.build/debug/Tasky`로 띄우면 요청 전에 `Bundle.main.bundleIdentifier`와 키를 확인하고, 없으면 "앱으로 실행해야 해요"라고 보여 준 뒤 요청하지 않는다.
2. **macOS 알림도 번들이 필요하다.** `UNUserNotificationCenter`는 번들 밖에서 부르면 예외가 난다. 같은 방식으로 막고, 그때는 펫 반응만 보여 준다.
3. **권한 요청 시점.** 설정의 '할 일·일정' 켜기를 눌렀을 때만 `requestFullAccessToReminders()` / `requestFullAccessToEvents()`(macOS 14 API)를 부른다. 거절하면 "권한 열기"(`Privacy_Reminders` / `Privacy_Calendars`)를 보여 준다. 할 일과 일정 권한은 따로 다룬다(하나만 켜도 된다).
4. **자연어 → 날짜.** `NSDataDetector`가 "내일 3시"같은 한국어를 잘 못 읽을 수 있다(추정, 구현 전에 `--selftest`로 확인). 그래서 작은 자체 규칙을 먼저 쓰고, 맞는 게 없으면 `NSDataDetector`를 쓴다.
   - 날: 오늘·내일·모레·글피, `N일 뒤`, `다음 주 X요일`, `X요일`(다가오는 날), `M월 D일`, `M/D`
   - 때: `오전/오후/아침/저녁/밤 N시 (M분|반)`, `N:MM`. 오전·오후 없이 `1~6시`면 오후, `7~12시`는 오전, `13시` 이상은 24시간제로 본다(사용자 결정 2026-11-03). 틀리면 칩으로 고친다
   - 뽑은 말은 제목에서 뺀다("내일 3시 치과" → 제목 "치과", 칩 "내일(11/3) 오후 3:00").
   - 칩: 날짜 칩, 시간 칩. 누르면 `NSDatePicker` 팝오버로 고치고, ✕로 뺀다.
   - 시간이 있으면 일정(캘린더), 날짜만 있거나 없으면 할 일(미리 알림)으로 넣는다. 칩 옆 토글로 바꿀 수 있다(추정).
5. **보기 창.** `FloatingPanel` 같은 비활성 패널은 입력을 받을 수 없다. 입력칸이 있는 창은 클립보드 기록 창(`ClipWindow`)처럼 열 때만 키 창이 되게 한다. 이렇게 하면 포커스를 가져오지만, 사용자가 직접 연 창이라 규칙 예외로 보지 않는다(확인 필요).
   - 위: 한 줄 입력칸 + 칩
   - 목록: 오늘(지난 것 포함) / 다가오는 일(7일) / 날짜 없음. 체크하면 완료, 오른쪽 클릭하면 삭제(미리 알림의 휴지통 정책을 따른다).
   - 일정은 오늘·다가오는 일 안에 시간 순서로 섞어 보여 준다(완료 체크 없음).
6. **알림.**
   - 미리 알림·일정에 알람(`EKAlarm`, 그 시각)을 붙여 두면, Tasky가 꺼져 있어도 macOS가 알린다. Tasky가 따로 시스템 알림을 보내면 둘이 겹친다. 그래서 macOS 알림은 미리 알림·캘린더 앱에 맡기고, Tasky는 펫 반응만 한다(사용자 결정 2026-11-03).
   - 펫 반응: 1분마다 `Ticker`로 "지금부터 1분 안" 항목을 찾는다. 찾으면 알약을 펼치고(완료·10분 뒤 버튼, 일정은 확인·10분 뒤), 곰 반응(`BearMotion` 기존 알림 자세)과 짧은 소리를 낸다. 10분 뒤는 알람 시각을 바꿔 저장한다.
   - 이미 알린 항목 id는 메모리에 둔다(다시 켜면 지나간 것은 알리지 않음).
7. **바깥 변경.** `EKEventStoreChanged` 알림을 받으면 목록을 다시 읽는다.
8. **목록·캘린더 선택.** 기본은 `defaultCalendarForNewReminders()` / `defaultCalendarForNewEvents`. 설정에서 바꿀 수 있게 하고, 저장은 calendarIdentifier.

## 화면
- 링에 '할 일' 칸(`id: "tasks"`, `checklist`)을 넣는다. 누르면 창을 연다. 기능이 꺼져 있으면 칸을 숨긴다.
- 설정 탭 '할 일·일정': 켜기(할 일/일정 따로), 권한 상태 줄, 저장 목록·캘린더, 알림 소리 켜기, 단축키(선택, 기본 없음).

## 파일
- 새 `Tasks.swift`: `TaskStore`(EventKit 읽기·쓰기·권한·변경 감시), `QuickParse`(자연어), `TaskWindow`, 알림 감시
- `PetController.swift`: 링 칸, 설정 탭, 알약 펼침 연결
- `Geometry.swift` `SelfTest`: `QuickParse` 사례(고정 기준 시각)
- `scripts/make-app.sh`: 권한 설명 키

## 추가 (사용자 결정 2026-11-04)
9. **남은 할 일이 늘 보이게.** 오늘(지난 것 포함)·날짜 없는 할 일 중 안 끝낸 개수를 펫 옆 숫자 배지로 보여 준다. 펫에 마우스를 올리면 그 목록을 최대 5줄 말풍선으로 보여 준다. 붙어 있으면 알약 한 줄에 "할 일 N", 링 칸 이름도 "할 일 N".
10. **줄을 두 번 눌러 고치기.** 이름과 날짜·시간을 고친다(입력과 같은 자연어 + 칩). 바꿀 수 없는 캘린더 항목은 고치지 않는다.

## 하지 않는 것
- 반복 일정·하위 할 일·태그 편집, 캘린더 달력 보기, 여러 기기 동기화 UI(iCloud가 해 준다)

## 사용자 확인이 필요한 것
- (없음)

## 변경 이력
- 2026-11-02 초안
- 2026-11-03 알림 역할 결정: macOS 알림은 미리 알림·캘린더 앱(EKAlarm), Tasky는 펫 반응
- 2026-11-03 시각 해석 결정: 오전·오후 없는 1~6시는 오후. 승인
- 2026-11-04 추가: 남은 할 일 배지·미리보기, 두 번 눌러 고치기(사용자 요청)
