# Tasky (옛 이름 콩깍지)

macOS 14+ 데스크톱 펫. Swift Package(AppKit, SwiftUI 미사용), Xcode 없이 Command Line Tools로 빌드. git 사용(https://github.com/hyeon0208/tasky, MIT).
작업 방식은 [AI-NATIVE-GUIDE.md](AI-NATIVE-GUIDE.md)를 따른다. 기능 문서는 `intent/<기능>/`.

## 명령
- 빌드: `swift build`
- 자체 검사: `.build/debug/Tasky --selftest` (위치·링 계산, 작업 알림 상태 전환, 훅→소켓 왕복은 `TASKY_HOME=<임시폴더>`일 때)
- 변환만 확인: `.build/debug/Tasky --convert <ConvertOp> <파일...>`
- 훅 연결: `.build/debug/Tasky --connect|--disconnect claude|codex` (`TASKY_HOME`으로 실제 설정 대신 임시 폴더 사용 가능)
- 출시: `scripts/release.sh <버전> [--dry-run]` (VERSION·zip·dmg·Sparkle 서명·GitHub Release·appcast.xml, F29)
- 실행: `.build/debug/Tasky` (메뉴 막대 잎 아이콘 → 종료). `--debug`를 붙이면 설정에 '개발자' 탭(CPU·메모리·화면 갱신·애니메이션·타이머, CSV 기록)

## 규칙
- 새 타이머는 `Ticker`(Debug.swift)로 만든다(개발자 탭에서 이름으로 보이게).
- 펫과 패널은 포커스를 뺏지 않는다(비활성 패널). 전역 키보드 감지·손쉬운 사용 권한을 쓰지 않는다. 예외: F12 한영 전환 키(입력 모니터링, 손쉬운 사용 권한이 있으면 전환 키만 걸러 순서를 지킴 — 사용자 결정 2026-11-06), F15 창 정리(손쉬운 사용 권한, 사용자 결정 2026-10-28), F22 화면 캡처(화면 기록 권한, 사용자 결정 2026-10-30), F30 뚜껑 닫아도 깨어 있기(관리자 암호로 `/etc/sudoers.d/tasky`에 `pmset -a disablesleep 0|1`만 허용, 사용자 결정 2026-11-06). 모두 사용자가 켰을 때만 요청하고, 키를 저장·전송하지 않음.
- 변환은 원본을 바꾸지 않고 `이름 (깍지).확장자`로 새로 만든다. 서랍의 삭제는 휴지통으로만.
- 사용자 설정 파일(~/.claude, ~/.codex)은 백업 후 우리 항목만 바꾼다.
- 다른 소프트웨어를 안내·홍보하는 UI를 넣지 않는다.
- 디자인(색·모양·간격)은 사용자가 고른 시안대로 만들고, 시안과 다른 점은 보고한다(사용자 결정 2026-11-05, F27).

## 반복된 실수 (다시 하지 않기)
- 실행 중인 펫을 사용자 확인 없이 끄지 않는다. 사용자가 터미널에서 직접 띄운 펫도 함께 꺼진다.
- 화면을 볼 수 없으므로 UI 동작을 "된다"고 단정하지 않는다. 확인한 것과 못 한 것을 나눠 보고한다.
- 새 기본값을 정할 때는 사용자가 기대하는 기본 동작부터 확인한다(예: 처음 위치는 화면 중앙, 빼꼼은 사용자가 가장자리에 둘 때만).
- 원형 메뉴에서 연 서랍이 '고정'으로 열려 바깥 클릭으로 닫히지 않았다. 열기 경로마다 같은 상태로 여는지 확인한다.
- NSBrowser 칼럼 폭은 `.noColumnResizing`이면 기본 최소 폭으로 좁아진다. `setDefaultColumnWidth`를 쓴다.
- SwiftUI 뷰 본문에서 상태를 바꾸면 무한 갱신으로 멈출 수 있다(북마크 해석 중 저장). 무거운 해석은 한 번만 하고 캐시한다.
- 시스템 값의 단위·적용 시점을 추정으로 정하지 않는다. 지금 값을 읽어 확인한다(키 반복 단위를 15ms로 잘못 잡았고, 전역 값은 로그아웃 뒤에만 적용됨).
- 빌드 결과를 grep으로 거르고 이어서 자체 검사·커밋하면, 빌드가 실패해도 예전 실행 파일로 검사가 통과해 깨진 코드가 커밋된다. `swift build`의 종료 코드로 확인한 뒤 커밋한다.
- 입력 중에 입력칸이 든 창 내용(contentView)을 다시 만들지 않는다. 포커스·한글 조합이 끊겨 타이핑이 안 된다(F26 빠른 실행).
- ad-hoc 서명(`--sign -`)은 지정 요구가 cdhash라 앱을 다시 만들 때마다 손쉬운 사용·미리 알림·캘린더 권한이 풀린다(설정엔 켜져 보임). make-app.sh에서 지정 요구를 식별자로 고정한다. 권한 요청 API(TCC)는 실행 파일을 직접 띄우면 앱이 죽으므로 `open`으로 확인한다.
- 한영 전환 Caps→F18 바꿈은 키보드 장치마다(`--matching` PrimaryUsage 6) 걸고 재연결·깨어남 때 다시 건다. 전체에 걸면 블루투스 키보드에서 빠져 macOS 기본 Caps Lock이 대신 동작해 전환이 씹혔다(F28).
- 다른 앱의 입력 소스를 `TISSelectInputSource`로 바꾸면 메뉴 막대는 '한'인데 앞 앱(터미널·브라우저)은 영문으로 남는 일이 있다. 시스템 '이전 입력 소스' 단축키가 F18이면 F18을 그대로 보내 macOS가 바꾸게 한다. 앱으로 띄운 Tasky의 NSLog는 로그에 안 남으니 진단은 `diag`(stderr)와 `open --stderr <파일> dist/Tasky.app --args --debug`로 본다(F28).
- `pmset disablesleep`을 뚜껑이 닫힌 채 0으로 되돌리면 macOS가 다시 판단하지 않아 깨어 있다. 닫힘 잠자기 조건(ioreg AppleClamshellCausesSleep)이면 `pmset sleepnow`로 재운다(F30).
