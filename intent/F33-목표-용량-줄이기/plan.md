# F33 목표 용량으로 줄이기 — plan

- 상태: done (구현 2026-11-06, 화면 확인 대기)
- 작성일: 2026-11-06
- spec: ./spec.md (approved 2026-11-06)
- 변경 이력
  - 2026-11-06: 최초 작성

## 목표
이미지·PDF를 원형 변환의 '용량 줄이기'에 잠깐 올려 두면 목표 5칸이 펼쳐지고, 고른 용량 아래로 맞춘 파일이 원본 옆에 생긴다.

## 근거로 확인한 API·코드
- `QuartzFilter(properties:)` + `PDFDocument.write(to:withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter])` — 2026-11-06 스크래치 시험으로 동작 확인(11.8MB → 0.56MB, 쪽 수 같음). 속성 키: `FilterData.ColorSettings.ImageSettings.{Compression Quality, ImageCompression=ImageJPEGCompress, ImageScaleSettings.ImageResolution}`
- `PDFPage(image:)`(쪽 크기 = NSImage size) — Converter.swift:317, 시험에서 확인
- `PDFPage.thumbnail(of:for:)` — Converter.swift:326
- `CGImageDestinationCreateWithData`·`kCGImageDestinationLossyCompressionQuality` — ImageIO, 기존 `writeImage` Converter.swift:454
- `loadImage(_:maxPixel:)`(방향 적용) — Converter.swift:415
- `finalize(_:from:ext:label:)` — Converter.swift:650 / `tempURL(ext:)` — 644
- `Converter.run` — Converter.swift:269, 호출처 PetController.swift:938 하나 / CLI main.swift:32
- 칸 목록 `specific(_:)` — Converter.swift:240-241 / 원형 칸 `WheelItem`·`WheelMath`·`ConvertWheelView`·`ConvertWheel.open` — ConvertWheel.swift:7, 17, 60, 189
- 칸 만들기 `convertItems`·`convert` — PetController.swift:911-953
- 자체 검사 변환 칸·원 배치 — Geometry.swift:797-816

## 파일 맵
- 수정: `Sources/Tasky/Converter.swift` — 작업 5개, 이미지·PDF 맞추기, 알림 전달
- 수정: `Sources/Tasky/ConvertWheel.swift` — 하위 칸 펼침
- 수정: `Sources/Tasky/PetController.swift:911-953` — 부모 칸 묶기, 알림 말하기
- 수정: `Sources/Tasky/main.swift:32-35` — CLI 알림 출력
- 테스트: `Sources/Tasky/Geometry.swift` — `--selftest`

## 단계
### 1. 작업 5개와 알림 통로
- 목표 기여: 목표별 작업이 칸 목록에 들어가고, "이미 작아요"·"못 맞췄어요" 알림이 펫까지 간다.
- 파일: Converter.swift, PetController.swift:938-951, main.swift
- 할 일:
  - `.shrink`, `.pdfShrink` 삭제. `shrink500K, shrink1M, shrink2M, shrink5M, shrink10M` 추가. `var targetBytes: Int?`(500_000…10_000_000, 나머지 nil). `title` "500KB 이하"…, `short` "500KB"…"10MB", `symbol` "arrow.down.circle", `note` nil, `isFormat` false.
  - 240행: `.shrink` 자리에, 241행: `.pdfShrink` 자리에 5개.
  - `convert(_ op:, _ urls:, note: (String) -> Void = { _ in }) throws -> [URL]`.
  - `run(_:_:done: ([URL], [String], [String]) -> Void)` — 세 번째는 "파일이름: 알림".
  - PetController `convert`: 알림이 있으면 오류가 없을 때 성공 문구 대신 `notes[0]`(+ " 외 N건"), 4초. 결과 0개·오류 0개면 "실패"로 말하지 않는다.
  - main.swift: 알림을 `NOTE: …`로 출력.
- 검사: `swift build` 0; `--selftest` 변환 칸 검사에 "이미지·PDF에 목표 5개, `shrink` 없음" 추가 → `selftest ok`
- [ ] 완료

### 2. 이미지 맞추기
- 목표 기여: 성공 기준 1·3·4(이미지).
- 파일: Converter.swift
- 할 일: `private static func shrinkImage(_ src: URL, target: Int, note: (String) -> Void) throws -> [URL]`
  - 원본 ≤ target → `note("이미 \(목표 이름) 이하예요")`, `[]`.
  - `loadImage(src, maxPixel: nil)` → 흰 배경 RGB 비트맵에 그림(투명 → 흰색).
  - 긴 변 후보: 원본, ×0.8 반복, 하한 `min(원본, 800)`. 각 후보에서 품질 0.3~0.9 이분 탐색 5번(`CGImageDestinationCreateWithData`로 메모리 인코딩). 목표 아래 첫 후보의 최고 품질 결과를 쓴다.
  - 못 맞추면 가장 작은 결과 + `note("목표에 못 맞췄어요 (\(ByteCountFormatter .file))")`.
  - 쓰기: 임시 파일 → `finalize(ext: "jpg", label: op.title)`.
- 검사: `--selftest`에서 임시 폴더에 잡음 이미지(3000×2000 PNG) 생성 → `shrink500K` 결과 ≤ 500,000바이트; 200×200 이미지 → 결과 0개·알림 "이미" 포함.
- [ ] 완료

### 3. PDF 맞추기
- 목표 기여: 성공 기준 2·3·4(PDF).
- 파일: Converter.swift
- 할 일: `private static func shrinkPDF(_ src: URL, target: Int, note: (String) -> Void) throws -> [URL]`
  - 원본 ≤ target → 알림만.
  - 1차 QuartzFilter (품질, dpi): (0.75,150) → (0.5,150) → (0.5,100) → (0.3,72). `write`가 false면 그 단계 건너뜀.
  - 2차 쪽 그림화 (dpi, 품질): (150,0.6) → (110,0.5) → (80,0.4) → (60,0.3). 쪽마다 `thumbnail(of: 쪽 크기 × dpi/72)` → JPEG 데이터 → `NSImage(data:)`에 `size = 쪽 크기` → `PDFPage(image:)`. 이 단계 결과를 쓰면 `note("글자를 선택·검색할 수 없게 됐어요")`.
  - 못 맞추면 가장 작은 결과 + "목표에 못 맞췄어요 (…)".
  - `finalize(ext: "pdf", label: op.title)`. 결과 쪽 수가 원본과 다르면 오류 "PDF를 저장하지 못했어요".
- 검사: `--selftest`에서 잡음 이미지 3쪽 PDF(약 10MB) → `shrink500K` 결과 ≤ 500,000바이트·쪽 수 3. 큰 사진 PDF가 없으면 이 합성 PDF로 성공 기준 2를 대신하고 보고.
- [ ] 완료

### 4. 원형 칸 펼침
- 목표 기여: 다섯 목표를 칸 수를 늘리지 않고 고르게 한다(인터뷰 결정).
- 파일: ConvertWheel.swift, PetController.swift:911-927
- 할 일:
  - `WheelItem.children: [WheelItem] = []`.
  - `WheelMath.children(of parent: Wedge, count: Int, start: Double, span: Double) -> [Wedge]` — r0 = parent.r1 + 6, r1 = r0 + 58, 칸당 16°, 부모 가운데 각 중심. `span < 360`이면 `[start - span, start]` 안으로 밀어 넣는다.
  - `ConvertWheelView`: `expanded: Int?`, `childWedges`. 자식 있는 칸에 0.5초 머무르면(`Ticker.once("변환 칸 펼치기", 0.5)`) 펼침. `draggingUpdated`는 펼친 동안 자식 칸 먼저 찾고, 부모·자식 밖 다른 칸이면 접음. 자식 칸 그리기는 기존 `wedgePath`·글자 그리기 재사용. 놓을 때 자식이면 그 action, 부모 칸이면 `onPick` 대신 `onParentDrop`.
  - `ConvertWheel.open`: 패널 한 변을 `(outerRadius + 6 + 58 + 20) * 2`로(자식이 있을 때만). `arc`를 뷰에 넘김.
  - PetController `convertItems`: `targetBytes != nil`인 작업을 빼서 `WheelItem(title: "용량 줄이기", isFormat: false, detail: "올려 두면 목표 용량", children: …)` 하나로 넣는다. 부모에 놓으면 원을 닫고 `say("칸에 잠깐 올려 두면 목표 용량이 펼쳐져요")`.
- 검사: `swift build` 0; `--selftest`에 `WheelMath.children` 검사(5칸, 모두 r0 > 부모 r1, 반원 (90,180)에서 범위 안) → `selftest ok`. 펼침 동작은 사용자 확인.
- [ ] 완료

### 5. 전체 확인·리뷰
- 검사: `swift build` 0 → `TASKY_HOME=$(mktemp -d) .build/debug/Tasky --selftest` → `selftest ok`; `--convert shrink1M <스크래치의 큰 이미지>` → 출력 파일 ≤ 1,000,000바이트. 새 문맥 독립 리뷰 1회, plan과 다른 점 보고.
- 사용자 확인 요청: 실제 사진·PDF로 원형 칸 펼침 → 결과 크기·말풍선.
- [ ] 완료

## Not now
- 동영상 · 직접 입력 · 합계 기준 · 예전 `convertUse`의 shrink 값 정리

## 진행 기록
- [ ] 1  - [ ] 2  - [ ] 3  - [ ] 4  - [ ] 5

## 결정(Ruling)
- 2026-11-06 단계 1: 목표별 작업 5개(`ConvertOp` 케이스) — 작업 = 이름 하나 구조(run·CLI·사용 기록)에 맞음 — 틀리면 케이스가 늘어나는 정도
- 2026-11-06 단계 3: PDF 단계 값은 고정 사다리 — 시험값 기준, 이분 탐색보다 단순 — 틀리면 목표보다 많이 작아질 수 있음(화질 손해)

## 결과 (2026-11-06)
- 1~5단계 완료. `swift build` 0, `--selftest` ok(목표 5칸, 이미지 500KB, 이미 작음, A4 사진 3쪽 PDF 11.8MB→500KB 이하·쪽 수 같음, 하위 칸 배치).
- plan과 다른 점: PDF 그림화 단계에 긴 변 픽셀 상한(2000/1500/1100/800) 추가 — 'PDF 하나로' PDF는 쪽 크기가 픽셀 크기라 dpi만으로 안 줄었음. 칸 이름은 "500KB 이하로 줄이기", 파일 라벨은 "500KB 이하".
- 독립 리뷰 반영: 회전된 쪽(90°/270°) 그림화 시 찌그러짐 수정, 결과가 원본보다 작지 않으면 파일을 만들지 않고 "더 줄이지 못했어요", 쓰기 실패 임시 파일 정리, 하위 칸 고리까지 넣어 반원 판단.
- 확인 못 함: 원형 칸 펼침 화면, 실제 8MB 사진·20MB PDF.
