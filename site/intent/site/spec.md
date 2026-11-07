# Tasky 홍보 사이트 — spec

- 상태: 승인 (2026-11-07)
- 작성일: 2026-11-07
- 입력: `~/work/proposal/tasky/site/intent.md`(승인 2026-11-06), `~/work/media/design/tasky/site/design.md`(승인 2026-11-07), 시안 `landing/c2.html`

## 무엇을 만드나
c2.html을 화면·글·움직임 그대로 살린 정적 사이트. 빌드 없이 Vercel에 폴더째 배포한다.

```
index.html      c2.html 기반 (제목 "Tasky — 시안 C2" → "Tasky", 아래 변경만)
media/          c2가 쓰는 11장면의 .mp4·.jpg만 (00-hero, 03~05, 06-shrink, 07~12)
img/appicon.png
vercel.json     없음(기본값으로 충분). 필요해지면 그때 추가
```

## 동작 (c2에서 바뀌는 것만)
### 1. 다운로드 버튼 — 파일 이름 고정 (결정: 사용자 선택, ADR 0001)
- 앱 저장소의 `release.sh`가 버전 붙은 파일과 함께 `Tasky.dmg`·`Tasky.zip`도 올린다.
- 사이트의 `[data-dl]` 기본 주소: `https://github.com/hyeon0208/tasky/releases/latest/download/Tasky.dmg`(zip도 같음). JS·API 없이도 클릭 한 번에 받는다.
- 실행 중 API는 버전·소식에만 쓴다. API가 성공했는데 최신 릴리스에 해당 확장자 파일이 없으면 → `releases/latest` 페이지로 바꾼다(design.md 빈 상태). 확장자 파일이 있으면 그 주소로 둔다(옮겨 가는 동안 이름 고정 파일이 없어도 동작).
- API 실패 → 기본 주소 그대로.

### 2. 버전 표기·새로운 소식 (design.md '상태' 표)
| 경우 | 버전 | 새로운 소식 |
|---|---|---|
| 불러오는 중 | "최신 버전" | 시안의 샘플 줄을 지우고 빈 칸(샘플을 실제처럼 보이지 않게) |
| 성공 | 태그 이름 | 태그 + 본문 첫 줄. 첫 줄이 없으면 "바뀐 점은 GitHub에서 볼 수 있어요." |
| 빈 상태(공개 릴리스 없음) | "최신 버전" 그대로 | "아직 공개한 버전이 없어요" + GitHub 링크 |
| 오류(API 실패) | "최신 버전" 그대로 | "GitHub에서 보기" 링크만 |

### 3. 다운로드 클릭 집계
- `<head>`에 `window.va` 대기열 + Vercel Web Analytics 스크립트. 쿠키 없음(intent 제약 충족).
- `[data-dl]` 클릭 → `va('event', { name: 'download', data: { type: 'dmg'|'zip' } })`.
- 사용자 지정 이벤트는 Pro 이상에서만 집계된다. 지금 계정은 Hobby로 보여 코드만 넣고, 그동안은 GitHub 릴리스 파일별 `download_count`로 본다(결정: 사용자 선택).
- 스크립트 주소는 Vercel 대시보드에서 Web Analytics를 켤 때 받는 `/<unique-path>/script.js`다. 받기 전까지는 `/_vercel/insights/script.js`를 넣고, 배포 뒤 Network 탭에서 확인한다.

### 4. 설치 명령 복사 실패 처리
- 성공: "복사됨" 1.5초 (시안 그대로).
- 실패(`navigator.clipboard` 없음, 거부, http 등): 명령 글자를 전부 선택해 두고 버튼을 1.5초 동안 "⌘C로 복사"로 바꾼다(결정: 사용자 선택).

## 바꾸지 않는 것
글·토큰·레이아웃·탭 10개·재생 속도·영상 재생 규칙·움직임 줄이기 처리는 c2 그대로.

## 성공 기준 → 확인 방법
1. 클릭 한 번에 최신 .dmg를 받는다 → 앱 쪽 변경 뒤 `releases/latest/download/Tasky.dmg`가 302 → 실제 파일인지 확인
2. 모바일에서 깨지지 않는다 → 375px·820px 화면에서 가로 스크롤 없음 확인
3. 상태 4가지 → API 응답을 성공·빈 목록·실패로 바꿔 화면 확인
4. 복사 실패 → clipboard를 막고 눌러서 선택·글자 확인
5. 클릭 이벤트 → `va` 호출이 대기열에 쌓이는지 확인(실제 집계는 Pro 이후)

## 의존·순서
- 이름 고정 파일이 없으면 기본 주소가 404다. 사이트 공개 전에 앱 폴더에서: `release.sh` 수정 + v1.4.0에 `Tasky.dmg`·`Tasky.zip` 추가 업로드(`gh release upload`, 승인 필요). → `cd ~/work/dev/apple/tasky && ccd`
- 배포(Vercel 프로젝트 생성·공개)는 승인 후.

## design.md '확인할 것' — 개발 쪽 확인 결과
| 항목 | 결과 |
|---|---|
| 키 반복 "macOS 설정의 최고 속도보다 더 빠르게" | **코드상 맞다.** Tasky 반복 속도 범위 1~120(1/60초 단위, `Keyboard.swift:632·636`) → 최소 1 ≈ 17ms. 시스템 설정 최고는 KeyRepeat=2(30~33ms). 반복 시작도 Tasky 최소 10(≈167ms) < 시스템 최소 15. 단, ① 영상 `12-keyrepeat`의 "빠르게 33ms"는 값 2 = 시스템 최고와 같아서 영상 자체는 '더 빠름'을 보여 주지 않는다 ② 17ms가 실제 키보드에서 그대로 먹히는지는 측정하지 않았다 ③ design.md는 값 2를 30ms(15ms 단위), Tasky는 33ms(1/60초 단위)로 적어 단위가 다르다 |
| 한 줄 설치 명령 | main에 `scripts/install.sh` 있음(HTTP 200) |
| 클릭 한 번 다운로드 | 파일 이름 고정으로 결정(위 1) |
| 새로운 소식 내용 | 릴리스 본문이 모두 `**Full Changelog**: …` 한 줄(`--generate-notes`, PR 없음)이라 첫 줄은 항상 대체 문구가 된다. 실제 소식을 보이려면 앱 `release.sh`에서 노트를 써야 한다(앱 쪽 일) |
| `11-window` 재촬영, '코엑스 박람회', 처음 여는 방법 문구, 서랍 '+' 칩 | 개발(사이트) 범위 밖. 디자인·기획·앱 개발 쪽 |

## 변경 이력
- 2026-11-07 초안
- 2026-11-07 승인
