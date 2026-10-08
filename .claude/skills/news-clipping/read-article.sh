#!/usr/bin/env bash
# 기사 URL 1건을 Aside로 열어 접근성 트리(snapshot) 전체를 파일로 저장합니다.
# 사용: bash .claude/skills/news-clipping/read-article.sh "<URL>" "<저장경로>"
# 종료코드: 0 성공 / 2 입력 오류 / 그 외 실패 (메시지는 stderr)

set -u

URL="${1:-}"
OUT="${2:-}"

if [ -z "$URL" ] || [ -z "$OUT" ]; then
  echo "사용법: bash read-article.sh \"<URL>\" \"<저장경로>\"" >&2
  exit 2
fi

case "$URL" in
  http://*|https://*) ;;
  *) echo "오류: http 또는 https 주소만 사용할 수 있습니다." >&2; exit 2 ;;
esac

case "$URL" in
  *"'"*|*'\'*)
    echo "오류: 주소에 작은따옴표 또는 역슬래시가 있어 처리하지 않습니다." >&2
    exit 2
    ;;
esac

# aside 명령 찾기
if command -v aside >/dev/null 2>&1; then
  ASIDE=aside
elif [ -n "${LOCALAPPDATA:-}" ] && [ -x "$LOCALAPPDATA/Aside/CLI/current/aside.exe" ]; then
  ASIDE="$LOCALAPPDATA/Aside/CLI/current/aside.exe"
else
  echo "오류: aside 명령을 찾을 수 없습니다." >&2
  exit 3
fi

mkdir -p "$(dirname "$OUT")" || { echo "오류: 저장 폴더를 만들 수 없습니다." >&2; exit 4; }

CODE="const pA = await openTab('$URL'); const sA = await snapshot(pA); console.log(sA.tree); await closeTab(pA);"

TMP="$OUT.tmp"
timeout 150 "$ASIDE" repl "$CODE" > "$TMP"
RC=$?

if [ "$RC" -eq 124 ]; then
  rm -f "$TMP"
  echo "오류: 150초 안에 기사를 읽지 못했습니다(시간 초과)." >&2
  exit 124
fi
if [ "$RC" -ne 0 ]; then
  rm -f "$TMP"
  echo "오류: Aside 실행에 실패했습니다(종료코드 $RC)." >&2
  exit "$RC"
fi

mv -f "$TMP" "$OUT" || { echo "오류: 결과를 저장하지 못했습니다." >&2; exit 4; }
echo "저장 완료: $OUT"
