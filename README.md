# 콩깍지 (Kongpod)

macOS 14 이상 데스크톱 펫. Swift Package, Xcode 없이 Command Line Tools로 빌드된다.

```
swift build
.build/debug/Kongpod             # 실행 (메뉴 막대의 잎 아이콘 → 종료)
.build/debug/Kongpod --selftest  # 위치·링 계산 검증
```

## 지금 되는 것 (1단계)
- 포커스를 뺏지 않는 투명 펫 창, 모든 Space에 표시
- 끌어서 이동, 가장자리·아래 구석 24pt 안에 놓으면 빼꼼, 호버 0.3초 뒤 고개 내밀기
- 클릭하면 콩 링 8칸 (화면 안 원 / 가장자리 반원 / 구석 부채꼴), 숫자 1~8·Esc, 바깥 클릭으로 닫기
- 좌우로 문지르면 쓰다듬기, 위치·모니터 기억, 모니터 분리 시 주 화면으로
- 폴더 서랍: ⌥를 누른 채 펫에 호버(또는 링의 '폴더 서랍'). 폴더 저장·탐색, 스페이스로 Quick Look,
  끌어내기, 파일을 끌어 넣기(같은 디스크는 이동, ⌥는 복사). 서랍 키는 `defaults write Kongpod drawerKey control|command`
- 드롭 변환: 파일을 펫에 끌어오면 형식별 링이 뜨고, 칸에 놓으면 원본 옆에 `이름 (깍지).확장자`로 만든다
  (`.build/debug/Kongpod --convert toJPEG 파일`로 명령줄에서도 확인 가능)
- 작업 알림: 링의 '작업 알림' 칸 → 아래 버튼으로 Claude Code·Codex 연결. 끝남·기다림·실패를 말풍선과 몸 안 콩알로 알린다.
  명령줄: `.build/debug/Kongpod --connect claude` / `--disconnect codex`. 훅은 이 실행 파일 경로를 가리키므로 `.build`를 지우면 다시 연결한다.
- 링의 편지·싱잉볼·설정 칸은 아직 "곧 만들어요"

## Supabase
`supabase/migrations/0001_letters.sql`을 프로젝트의 SQL Editor에서 실행하거나 `supabase db push`로 적용한다.
앱에는 프로젝트 URL과 anon(publishable) 키만 넣는다. service_role 키는 앱에 넣지 않는다.
