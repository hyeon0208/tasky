#!/bin/zsh
# F26 캐릭터(낙서 곰·길쭉 냥이) PNG 만들기 → Assets/Characters, 그리고 앱 폴더에 복사
set -euo pipefail
cd "${0:A:h}/.."
tmp=$(mktemp -d)
python3 scripts/make-characters.py "$tmp" >/dev/null
swiftc -O scripts/render-svg.swift -o "$tmp/render"
a=(); for f in "$tmp"/*/*.svg; do a+=("$f" "${f%.svg}.png"); done
"$tmp/render" "${a[@]}"
dest=~/Library/Application\ Support/Tasky/Characters
for c in doodlebear longcat; do
  mkdir -p "Assets/Characters/$c" "$dest/$c"
  cp "$tmp/$c"/*.png "Assets/Characters/$c/"
  cp "$tmp/$c"/*.png "$dest/$c/"
done
rm -rf "$tmp"
echo "만들었어요: Assets/Characters/{doodlebear,longcat}"
