# Tasky (옛 이름 콩깍지)

macOS 14+ 데스크톱 펫. Swift Package(AppKit, SwiftUI 미사용), Xcode 없이 Command Line Tools로 빌드. git 사용(https://github.com/hyeon0208/tasky, MIT).
작업 방식은 [AI-NATIVE-GUIDE.md](AI-NATIVE-GUIDE.md)를 따른다. 기능 문서는 `intent/<기능>/`.

## 명령
- 빌드: `swift build`
- 자체 검사: `.build/debug/Tasky --selftest` (위치·링 계산, 작업 알림 상태 전환, 훅→소켓 왕복은 `TASKY_HOME=<임시폴더>`일 때)
- 변환만 확인: `.build/debug/Tasky --convert <ConvertOp> <파일...>`
- 훅 연결: `.build/debug/Tasky --connect|--disconnect claude|codex` (`TASKY_HOME`으로 실제 설정 대신 임시 폴더 사용 가능)
- 실행: `.build/debug/Tasky` (메뉴 막대 잎 아이콘 → 종료). `--debug`를 붙이면 설정에 '개발자' 탭(CPU·메모리·화면 갱신·애니메이션·타이머, CSV 기록)

## 구조
- `PetController.swift`: 펫 한 마리(위치·빼꼼·링·서랍·알림·설정 창), `App`(펫 목록·메뉴 막대·훅 서버), `LoginItem`
- `PetView.swift`: 2D 그리기만(나중에 3D로 교체할 자리). `FloatingPanel`: 포커스를 뺏지 않는 투명 패널
- `Geometry.swift`: 빼꼼·링 칸 위치 계산 + `SelfTest`
- `SettingsView.swift`: 설정 창 탭 줄·격자·키보드 바로 테스트 칸 (F13)
- `RingView.swift`: 원형 메뉴, `Drawer.swift`: 폴더 서랍(NSBrowser 칼럼), `Converter.swift`: 드롭 변환
- `Character.swift`: 캐릭터 그림(영어·한국어 이름, 대신 규칙), 효과, 상황 → 반응 표, 찌르기·던지기 판정 (F11)
- `Keyboard.swift`: 한영 전환 키(판정·hidutil Caps→F18·듣기 전용 탭·입력 소스)와 키 반복 값 (F12)
- `Clipboard.swift`: 클립보드 기록(감시·저장·⌘⇧C 단축키·기록 창) (F16)
- `Beads.swift`: 작업 구슬(세션·변환 → 구슬 목록, 펫 위 자식 패널) (F14)
- `Debug.swift`: `--debug` 개발자 옵션, 이름 붙은 타이머 `Ticker`(새 타이머는 이것으로 만든다), `PerfSampler` (F17)
- `Agents.swift`: 훅 클라이언트·소켓 서버·세션 상태·훅 설치, `AgentPanel.swift`: 알림 목록·메시지 창

## 규칙
- 펫과 패널은 포커스를 뺏지 않는다(비활성 패널). 전역 키보드 감지·손쉬운 사용 권한을 쓰지 않는다. 예외: F12 한영 전환 키(입력 모니터링만), F15 창 정리(손쉬운 사용 권한, 사용자 결정 2026-10-28). 모두 사용자가 켰을 때만 요청하고, 키를 저장·전송하지 않음.
- 변환은 원본을 바꾸지 않고 `이름 (깍지).확장자`로 새로 만든다. 서랍의 삭제는 휴지통으로만.
- 사용자 설정 파일(~/.claude, ~/.codex)은 백업 후 우리 항목만 바꾼다.
- 다른 소프트웨어를 안내·홍보하는 UI를 넣지 않는다.
- 디자인(색·모양·소리)은 나중에 에셋으로 교체할 자리이므로, 기능 확인이 되는 수준으로만 만든다.

## 반복된 실수 (다시 하지 않기)
- 실행 중인 펫을 사용자 확인 없이 끄지 않는다. 사용자가 터미널에서 직접 띄운 펫도 함께 꺼진다.
- 화면을 볼 수 없으므로 UI 동작을 "된다"고 단정하지 않는다. 확인한 것과 못 한 것을 나눠 보고한다.
- 새 기본값을 정할 때는 사용자가 기대하는 기본 동작부터 확인한다(예: 처음 위치는 화면 중앙, 빼꼼은 사용자가 가장자리에 둘 때만).
- 원형 메뉴에서 연 서랍이 '고정'으로 열려 바깥 클릭으로 닫히지 않았다. 열기 경로마다 같은 상태로 여는지 확인한다.
- NSBrowser 칼럼 폭은 `.noColumnResizing`이면 기본 최소 폭으로 좁아진다. `setDefaultColumnWidth`를 쓴다.
- SwiftUI 뷰 본문에서 상태를 바꾸면 무한 갱신으로 멈출 수 있다(북마크 해석 중 저장). 무거운 해석은 한 번만 하고 캐시한다.
- 시스템 값의 단위·적용 시점을 추정으로 정하지 않는다. 지금 값을 읽어 확인한다(키 반복 단위를 15ms로 잘못 잡았고, 전역 값은 로그아웃 뒤에만 적용됨).
