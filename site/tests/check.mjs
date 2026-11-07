// node tests/check.mjs — index.html의 pickRelease·firstLine 검사, 참조 파일 존재 확인
import { readFileSync, existsSync } from 'node:fs';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const grab = name => html.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n}`))[0];
const { pickRelease } = new Function(`${grab('firstLine')}\n${grab('pickRelease')}\nreturn { pickRelease };`)();

const asset = n => ({ name: n, browser_download_url: `https://x/${n}` });
const rel = (o) => ({ draft: false, prerelease: false, tag_name: 'v1.4.0', body: '', assets: [], ...o });

// 1. 정상: 첫 줄 + 확장자별 주소
let r = pickRelease([rel({ body: '## 바뀐 점\n- **서랍** 새 디자인\n- 기타', assets: [asset('Tasky.dmg'), asset('Tasky.zip')] })]);
assert.deepEqual(r, { tag: 'v1.4.0', first: '서랍 새 디자인', assets: { dmg: 'https://x/Tasky.dmg', zip: 'https://x/Tasky.zip' } });
// 2. Full Changelog만 있는 본문 → 빈 첫 줄(화면은 대체 문구)
assert.equal(pickRelease([rel({ body: '**Full Changelog**: https://github.com/a/b/compare/v1...v2' })]).first, '');
// 3. draft·prerelease만 → null(빈 상태)
assert.equal(pickRelease([rel({ draft: true }), rel({ prerelease: true })]), null);
assert.equal(pickRelease([]), null);
// 4. 확장자 파일 없음 → undefined(화면은 releases/latest)
assert.deepEqual(pickRelease([rel({ assets: [asset('notes.txt')] })]).assets, { dmg: undefined, zip: undefined });

// 참조 파일이 모두 있는지
const refs = [...html.matchAll(/(?:src|poster)="((?:media|img)\/[^"]+)"/g)].map(m => m[1]);
for (const f of html.match(/'\d\d-[a-z]+'/g).map(s => s.slice(1, -1))) refs.push(`media/${f}.mp4`, `media/${f}.jpg`);
const missing = refs.filter(p => !existsSync(new URL(`../${p}`, import.meta.url)));
assert.deepEqual(missing, []);
// CSS로 img 가로를 정하면 높이도 정해야 함(태그 height 속성이 남아 늘어남)
const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
const badImg = [...css.matchAll(/([^{}]*\bimg)\{([^}]*)\}/g)].filter(m => /(^|;)\s*width:/.test(m[2]) && !/(^|;)\s*height:/.test(m[2])).map(m => m[1].trim());
assert.deepEqual(badImg, []);
console.log(`ok: 사례 4개, 참조 파일 ${new Set(refs).size}개`);
