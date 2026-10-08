#!/usr/bin/env bash
# 지정한 날짜의 '아름다운가게' 네이버 뉴스 검색 결과를 TSV로 저장합니다.
# 사용: bash search-news.sh <YYYY-MM-DD> <저장.tsv>
# TSV 열: press, title, url, snippet (탭 구분, URL 기준 중복 제거)
# 종료코드: 0 성공(0건이면 헤더만) / 2 입력 오류 / 3 aside 없음 / 124 시간 초과 / 그 외 실패

set -u
shopt -u patsub_replacement 2>/dev/null || true

DAY="${1:-}"
OUT="${2:-}"

if [ -z "$DAY" ] || [ -z "$OUT" ]; then
  echo "사용법: bash search-news.sh <YYYY-MM-DD> <저장.tsv>" >&2
  exit 2
fi
if ! printf '%s' "$DAY" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "오류: 날짜는 YYYY-MM-DD 형식이어야 합니다." >&2
  exit 2
fi
if ! date -d "$DAY" '+%Y-%m-%d' >/dev/null 2>&1; then
  echo "오류: 존재하지 않는 날짜입니다." >&2
  exit 2
fi

if command -v aside >/dev/null 2>&1; then
  ASIDE=aside
elif [ -n "${LOCALAPPDATA:-}" ] && [ -x "$LOCALAPPDATA/Aside/CLI/current/aside.exe" ]; then
  ASIDE="$LOCALAPPDATA/Aside/CLI/current/aside.exe"
else
  echo "오류: aside 명령을 찾을 수 없습니다." >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")" || { echo "오류: 저장 폴더를 만들 수 없습니다." >&2; exit 4; }

DOT="${DAY//-/.}"   # 2026.10.07
NUM="${DAY//-/}"    # 20261007
QUERY="%22%EC%95%84%EB%A6%84%EB%8B%A4%EC%9A%B4%EA%B0%80%EA%B2%8C%22"
BASE="https://search.naver.com/search.naver?where=news&query=${QUERY}&sort=1&ds=${DOT}&de=${DOT}&nso=so:dd,p:from${NUM}to${NUM}"

# 한 쪽을 읽어 'ROW<탭>매체<탭>제목<탭>URL<탭>발췌' 줄로 출력하는 JS.
# __URL__ 자리에는 위에서 검증된 날짜로 만든 주소만 들어갑니다.
read -r -d '' JS_TEMPLATE <<'EOJS'
const pNs = await openTab('__URL__');
const lkNs = await pNs.evaluate(() => Array.from(document.querySelectorAll('a[href]')).map(a => [a.innerText.trim(), a.href]));
await closeTab(pNs);
const tailNs = /\s*새 창 열림\s*$/;
const cleanNs = (s) => String(s).replace(tailNs, '').replace(/\s+/g, ' ').trim();
const isArt = (h) => {
  let u;
  try { u = new URL(h); } catch (e) { return false; }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
  if (/(^|\.)naver\.com$/.test(u.hostname) || /(^|\.)navercorp\.com$/.test(u.hostname)) return false;
  if (u.pathname === '/' && !u.search) return false;
  return true;
};
const seenNs = new Set();
for (let i = 0; i < lkNs.length; i++) {
  const t = lkNs[i][0], h = lkNs[i][1];
  if (!isArt(h) || seenNs.has(h)) continue;
  seenNs.add(h);
  const title = cleanNs(t);
  const press = i > 0 ? cleanNs(lkNs[i - 1][0]) : '';
  let snip = '';
  for (let j = i + 1; j < lkNs.length; j++) {
    if (lkNs[j][1] === h) {
      const c = cleanNs(lkNs[j][0]);
      if (c && c !== title) { snip = c; break; }
    }
  }
  console.log('ROW\t' + [press, title, h, snip].join('\t'));
}
EOJS

WORK="$(mktemp -d)" || { echo "오류: 임시 폴더를 만들 수 없습니다." >&2; exit 4; }
trap 'rm -rf "$WORK"' EXIT
ALL="$WORK/all.txt"
SEEN="$WORK/seen.txt"
: > "$ALL"
: > "$SEEN"

PAGE=1
while [ "$PAGE" -le 5 ]; do
  START=$(( (PAGE - 1) * 10 + 1 ))
  if [ "$PAGE" -eq 1 ]; then PURL="$BASE"; else PURL="${BASE}&start=${START}"; fi
  CODE="${JS_TEMPLATE%%__URL__*}${PURL}${JS_TEMPLATE#*__URL__}"   # 치환(&가 깨짐) 대신 문자열 연결
  timeout 120 "$ASIDE" repl "$CODE" > "$WORK/page.txt"
  RC=$?
  if [ "$RC" -eq 124 ]; then
    echo "오류: ${PAGE}쪽 검색이 120초 안에 끝나지 않았습니다(시간 초과)." >&2
    exit 124
  fi
  if [ "$RC" -ne 0 ]; then
    echo "오류: Aside 실행에 실패했습니다(${PAGE}쪽, 종료코드 $RC)." >&2
    exit "$RC"
  fi
  NEW=0
  while IFS= read -r LINE; do
    LINE="${LINE%$'\r'}"
    case "$LINE" in ROW$'\t'*) ;; *) continue ;; esac
    ROW="${LINE#ROW$'\t'}"
    U="$(printf '%s' "$ROW" | awk -F'\t' '{print $3}')"
    [ -z "$U" ] && continue
    if ! grep -Fxq -- "$U" "$SEEN"; then
      printf '%s\n' "$U" >> "$SEEN"
      printf '%s\n' "$ROW" >> "$ALL"
      NEW=$((NEW + 1))
    fi
  done < "$WORK/page.txt"
  [ "$NEW" -eq 0 ] && break
  PAGE=$((PAGE + 1))
done

{
  printf 'press\ttitle\turl\tsnippet\n'
  cat "$ALL"
} > "$OUT.tmp" || { echo "오류: 결과를 저장하지 못했습니다." >&2; exit 4; }
mv -f "$OUT.tmp" "$OUT" || { echo "오류: 결과를 저장하지 못했습니다." >&2; exit 4; }

COUNT=$(wc -l < "$ALL" | tr -d ' ')
echo "저장 완료: $OUT (기사 ${COUNT}건)"
exit 0
