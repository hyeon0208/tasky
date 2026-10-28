# F17 개발자 옵션 (--debug) — plan
- 작성: 2026-10-28 · 근거: intent.md(승인됨), spec.md(승인됨) · 상태: 구현됨, 화면 확인 대기

## 바뀌는 파일
| 파일 | 변경 |
|---|---|
| `Sources/Kongpod/Debug.swift` (새로) | `Debug.isOn`, `Ticker`(이름 붙은 타이머 만들기·세기), `PerfSampler`(CPU·메모리·화면 갱신·애니메이션 수, 1초 간격, CSV 기록), `DebugTab`(설정 탭 화면) |
| `Sources/Kongpod/PetController.swift`, `PetView.swift`, `AgentPanel.swift`, `SingingBowl.swift` | `Timer.scheduledTimer` 7곳 → `Ticker.every/once(이름, ...)` (동작 같음) |
| `Sources/Kongpod/PetController.swift` | `Debug.isOn`이면 설정 탭에 '개발자'(hammer), 펫 창을 `PerfSampler`에 알림 |
| `Sources/Kongpod/Geometry.swift` | 자체 검사 |
| `CLAUDE.md` | 명령에 `--debug`, 구조에 `Debug.swift` |

## 작업 순서와 검사
### 1. `Ticker`
- `Ticker.every(_ name:, _ interval:, block)` / `once(...)` → `Timer`를 만들고 `[(name, weak Timer)]`에 담는다. `live`는 아직 유효한 것만(이름별 개수).
- **검사:** 2개 만들면 2, 하나 `invalidate` 후 1, `once`는 실행 뒤 0.

### 2. `PerfSampler`
- CPU: `getrusage(RUSAGE_SELF)` 사용자+시스템 시간 차 ÷ 경과 시간 × 100. 계산은 순수 함수 `cpuPercent(prev:now:seconds:)`.
- 메모리: `task_info(TASK_VM_INFO)`의 `phys_footprint` → MB.
- 화면 갱신: 펫 뷰의 `displayLink(target:selector:)`(macOS 14+)로 1초 동안 부른 횟수.
- 애니메이션 수: 펫 창 층 트리의 `animationKeys()` 개수 합.
- 구독자가 있거나 기록 중일 때만 1초 타이머·디스플레이 링크를 켠다(spec 5·6).
- CSV: `~/Library/Logs/Kongpod/perf-yyyy-MM-dd.csv`, 머리줄 `time,cpu,memoryMB,frames,animations,timers`. 한 줄 만들기는 순수 함수.
- **검사:** CPU 계산(1초 동안 0.25초 → 25%), CSV 한 줄 형식.

### 3. 개발자 탭
- 값 다섯 줄(1초 갱신) + 타이머 이름 목록 + '기록 남기기' 켜기 + '로그 폴더 열기'. 탭이 보일 때 구독, 설정을 닫거나 탭을 바꾸면 해제(`viewDidMoveToWindow`로).
- **검사:** 빌드, `--debug` 없이 탭 없음(코드상 확인).

### 4. 마무리
- 자체 검사 전체, 새 문맥 독립 검토 → 반영 → 다른 점 기록.

## 확인하지 못할 것 (사용자 확인)
- `--debug` 실행 시 값이 실제로 바뀌는지, 활성 상태 보기 값과 비슷한지.

## 구현 결과와 plan과 다른 점 (2026-10-28)
- 자체 검사 통과(타이머 세기·한 번 타이머, CPU 계산, CSV 한 줄, 메모리 읽기).
- 독립 검토 반영:
  - '화면 갱신'은 늘 60/120이라 뜻이 없어, 화면 갱신 때마다 펫에 움직이는 애니메이션이 있었는지만 센다('움직인 프레임 /초'). 펫 창이 아니라 화면에 붙여 펫을 숨겨도 0으로 굳지 않음.
  - 기록 쓰기 실패(디스크 가득 등)로 앱이 죽지 않게, 실패하면 탭에 표시. 자정이 지나면 새 파일.
  - 서랍 키 확인 타이머는 메뉴가 열린 동안 멈춤(메뉴 중 ⌥로 서랍이 뒤에서 열리던 문제).
  - 시계 말풍선: 빼꼼 중에는 보이는 몸 위·화면 안에, 펫 위치가 바뀌면 따라 다시 놓음.
- 다른 점: 타이머가 메뉴가 열려 있어도 돈다(.common, 서랍 키만 예외). 시계·깜빡임이 메뉴 중에도 멈추지 않게 하려는 것. 타이머 허용 오차 최대 0.05초.
- 시계 말풍선(사용자 요청)도 이 단계에서 `Ticker`로 만듦.
- 확인 못 함: --debug 실제 값, 활성 상태 보기와 비교.

## 변경 이력
- 2026-10-28 초안
- 2026-10-28 구현, 독립 검토 반영
- 2026-10-29 사용자 확인: '타이머'가 이해 안 됨 → '반복해서 하는 일'로 바꾸고 설명 한 줄, 항목은 '졸 시간인지 보기 (30초마다)'처럼 하는 일·간격을 한 줄씩
