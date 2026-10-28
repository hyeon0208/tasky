# F11 에셋 생성 프롬프트
- 작성: 2026-10-23 · 근거: ASSETS.md(확정)
- 사용법: 이미지 생성 도구에 **해당 캐릭터의 참고 사진(reference/chosen-N)** 을 함께 넣고, 아래 `[공통 스타일]` + `[캐릭터]` + `[표정]`을 이어 붙여 한 장씩 만든다.
- 영어 프롬프트가 대부분의 이미지 모델에서 더 일관되게 나온다. 한국어 설명은 확인용.

## 일관성을 위한 요령
1. 캐릭터마다 **`idle`을 먼저** 만들고, 마음에 드는 `idle`을 나머지 표정의 참고 이미지로 함께 넣는다(원본 참고 사진 + 내 idle).
2. 같은 도구·같은 설정(가능하면 같은 seed)으로 한 캐릭터의 표정을 연달아 만든다.
3. 크기·바닥선이 어긋나면 그대로 보내도 된다. 넣을 때 맞추는 것은 내가 확인해서 알려 준다.
4. 배경이 흰색으로 나오면 콩깍지 드롭 변환의 '배경 지우기'로 지운다(1024×1024 PNG로 저장).

## [공통 스타일] — 모든 그림 앞에 붙이기
```
A single cute chubby round character, hand-drawn crayon and colored-pencil texture, thick wobbly dark-brown outline, soft grainy fill, tiny dot eyes, deadpan minimalist expression, flat front view, full body, centered, the bottom of the body resting on an invisible floor line at about 12% from the bottom of the image, same size and position in every image, transparent background, no shadow, no ground line, no text, no frame, square 1024x1024.
```

## [캐릭터] — 하나 골라 붙이기 (참고 사진과 함께)
| 폴더 | 프롬프트 | 참고 |
|---|---|---|
| `chick` | `a round yellow baby chick with a small tuft of feathers on top, short horizontal slit eyes, small orange beak, tiny wing marks on the sides` | chosen-1 |
| `capybara` | `a round fluffy brown capybara with shaggy fur strokes, dark brown snout, tiny ears, small dot eyes` | chosen-2 왼쪽 |
| `hamster` | `a round grey and white hamster, grey back and white belly, small round ears with pink inside, tiny pink nose, small whiskers` | chosen-2 오른쪽 |
| `seal` | `a round white seal pup with a dark grey head cap, a yellow ring around the face, black nose, small dark tail at the back` | chosen-3 왼쪽 |
| `blueshark` | `a chubby blue and white shark, rounded blue back and pointed head, white belly, small black eye, small fins` | chosen-3 가운데 |
| `shiba` | `a round chubby shiba inu, orange back and white face and belly, white eyebrow spots, small triangle ears, half-closed unimpressed eyes` | chosen-3 오른쪽 |
| `cat` | `a round black and white cat, black head and back, white face and belly, pointed ears, small whiskers, fluffy dark tail` | chosen-4 왼쪽 |
| `grayshark` | `a chubby grey and white shark seen from the front, grey back, white belly, small black eye on the side, small fins` | chosen-4 오른쪽 |
| `bird` | `a round egg-shaped brown and white bird, brown back with a white triangle belly, pink blush cheeks, short slit eyes, tiny beak` | chosen-5 |

## [표정] — 파일 이름별로 붙이기
| 파일 | 프롬프트 |
|---|---|
| `idle.png` ★ | `neutral calm expression, sitting still` |
| `blink.png` ★ | `same pose as neutral, eyes fully closed as a short curved line, mouth unchanged` |
| `sleep.png` ★ | `sleepy, eyes closed, head slightly drooping forward, body a little slumped, peaceful` |
| `happy.png` ★ | `happy, mouth wide open in a big laugh, eyes squeezed shut into arcs, tiny blush` |
| `surprised.png` ★ | `surprised, small round wide-open eyes, small round "o" mouth, body slightly stretched up` |
| `sad.png` ★ | `sad and dejected, droopy eyes, small frown, body slightly sunken` |
| `handup.png` ★ | `raising one small arm (wing or fin for birds and sharks) straight up high, eager expression` |
| `mouthopen.png` ★ | `mouth opened very wide as if about to swallow something, eyes looking up` |
| `squish.png` ★ | `squished flat from above like a soft mochi, wider and shorter body, eyes squeezed shut` |
| `dangle.png` | `being lifted up from the top of the head, body stretched long and dangling, legs hanging, mildly annoyed face` |
| `walk1.png` | `side view facing left, walking, front foot forward, small bounce` |
| `walk2.png` | `side view facing left, walking, back foot forward, same size as the other walking frame` |
| `bowl.png` | `sitting and hugging a small golden brass singing bowl in front of its belly with both arms, calm closed eyes` |
| `grumpy.png` | `grumpy and sulky, side-eye glare, puffed cheeks, turned slightly away` |

예) 병아리 웃음:
```
[공통 스타일] a round yellow baby chick with a small tuft of feathers on top, short horizontal slit eyes, small orange beak, tiny wing marks on the sides. happy, mouth wide open in a big laugh, eyes squeezed shut into arcs, tiny blush.
```

## 효과 그림 (공용, 256×256) — `Effects/`
공통 앞부분:
```
A small hand-drawn doodle icon, thick wobbly dark-brown crayon line, minimal, centered, transparent background, no text other than described, square 256x256.
```
| 파일 | 프롬프트 |
|---|---|
| `zz.png` | `the letters "zz" drawn sleepily` |
| `dots.png` | `a small round thought bubble with three dots inside and a tiny tail` |
| `exclaim.png` | `a single exclamation mark` |
| `question.png` | `a single question mark` |
| `heart.png` | `a small heart filled with soft pink crayon` |
| `sweat.png` | `a single light-blue sweat drop` |
| `sparkle.png` | `three small sparkle stars` |
| `puff.png` | `a small puff of breath cloud, like a sigh` |
| `note.png` | `a single music note` |
| `shock.png` | `three short surprise lines radiating outward` |

## 넣는 곳
`~/Library/Application Support/Kongpod/Characters/<폴더>/<표정>.png`, 효과는 `~/Library/Application Support/Kongpod/Effects/<이름>.png`

## 변경 이력
- 2026-10-23 작성
