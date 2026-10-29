# F18 3D 메인 캐릭터 — plan
- 작성: 2026-10-29 · 근거: spec.md(승인됨) · 상태: 승인됨(2026-10-29)

## 파일
| 파일 | 할 일 |
|---|---|
| `Pet3D.swift`(새로) | `Spring`(순수), `MotionClip`·`Pose`(관절 → 목표 회전·크기, 섞기), `BearRig`(노드 이름 표), `ProceduralBear`(도형 곰), `Pet3DView`(SCNView, 매 갱신마다 모션 → 스프링 → 노드, 30fps·멈춤) |
| `PetView.swift` | `PetBody` 프로토콜 추가(컨트롤러가 쓰는 react·base·lean·waveHand·character·walkingRight 등), `PetView`가 따름 |
| `PetController.swift` | `petView` 자리를 `PetBody`로, 캐릭터 설정이 '곰 3D'면 `Pet3DView` |
| `Character.swift` | 목록 맨 위 '곰 3D(기본)', 폴더에 `model.usdz`가 있으면 그 캐릭터도 3D |
| `Geometry.swift` | 자체 검사: 스프링 수렴·감쇠, 섞기 중간값, 고개 각도 제한, 동작 줄이기 |
| 문서 | README 캐릭터 절, CLAUDE.md 구조 |

## 순서
1. `PetBody` 프로토콜로 2D를 감싸기만 → 동작 그대로인지 빌드·자체 검사.
2. `Spring`·`MotionClip` 순수 계산 + 자체 검사.
3. `ProceduralBear` + `Pet3DView` 평소(숨쉬기·깜빡임·고개) → 개발자 탭 CSV로 CPU 1분 측정.
4. 나머지 모션 표 12줄을 상황 연결.
5. 설정 캐릭터 고르기, usdz 불러오기(노드 이름이 표와 다르면 몸 전체만 움직임).
6. 독립 검토·문서·커밋.

## 검사
- 자체 검사, CPU 측정(가만히 1분, 2D와 비교 수치를 plan에 기록).
- 사용자 확인: 모습·자연스러움·투명 배경·끌기.

## 순서 (두 기능 사이)
- F19를 먼저(작고 화면 구조만), 그다음 F18. F18의 캐릭터 고르기가 새 설정 화면 위에 들어가므로.

## 변경 이력
- 2026-10-29 초안
- 2026-10-29 사용자 승인
