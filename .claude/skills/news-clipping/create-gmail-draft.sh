#!/usr/bin/env bash
# Gmail 임시보관함에 초안만 만듭니다. 이 스크립트는 메일을 보내지 않습니다.
# 사용: bash create-gmail-draft.sh <수신주소> <제목> <본문.html> <로그.md>
# 종료코드: 0 임시저장 확인 / 2 입력 오류 / 3 aside 없음 / 5 초안을 찾지 못함 / 124 시간 초과 / 그 외 실패

set -u
shopt -u patsub_replacement 2>/dev/null || true

TO="${1:-}"
SUBJECT="${2:-}"
BODY="${3:-}"
LOG="${4:-}"

if [ -z "$TO" ] || [ -z "$SUBJECT" ] || [ -z "$BODY" ] || [ -z "$LOG" ]; then
  echo "사용법: bash create-gmail-draft.sh <수신주소> <제목> <본문.html> <로그.md>" >&2
  exit 2
fi
if ! printf '%s' "$TO" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
  echo "오류: 수신 주소 형식이 올바르지 않습니다." >&2
  exit 2
fi
case "$SUBJECT" in
  *\"*|*\'*|*\\*|*\`*|*$'\n'*)
    echo "오류: 제목에 따옴표, 역슬래시, 줄바꿈은 사용할 수 없습니다." >&2
    exit 2
    ;;
esac
if [ ! -s "$BODY" ]; then
  echo "오류: 본문 HTML 파일이 없거나 비어 있습니다: $BODY" >&2
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

B64_BODY="$(base64 < "$BODY" | tr -d '\r\n')"
B64_SUBJ="$(printf '%s' "$SUBJECT" | base64 | tr -d '\r\n')"
UID_N="${CLIP_GOOGLE_UID:-0}"
if ! printf '%s' "$UID_N" | grep -Eq '^[0-9]{1,2}$'; then
  echo "오류: CLIP_GOOGLE_UID는 숫자만 사용할 수 있습니다." >&2
  exit 2
fi

# 제목·본문·확인 문구는 base64로 넘기고 JS 안에서 되돌립니다. 수신 주소는 위에서 형식을 검증한 값입니다.
# 저장 확인 순서: 1) 작성 창에 '임시보관함에 저장됨' 표시(최대 20초) 2) gmail.search 보조 확인.
# 보내기 동작은 이 코드에 없습니다. 작성 창은 저장 확인 뒤에만 closeTab으로 닫습니다.
read -r -d '' JS_TEMPLATE <<'EOJS'
const subjGd = Buffer.from('__SUBJ__', 'base64').toString('utf8');
const htmlGd = Buffer.from('__BODY__', 'base64').toString('utf8');
const markGd = Buffer.from('__MARK__', 'base64').toString('utf8');
const cpGd = await gmail.openComposer(__UID__, { to: '__TO__', subject: subjGd, bodyHtml: htmlGd });
const sleepGd = (ms) => new Promise((r) => setTimeout(r, ms));
let methodGd = '', tidGd = '';
for (let k = 0; k < 10 && !methodGd; k++) {
  await sleepGd(2000);
  try {
    const sGd = await snapshot(cpGd);
    if (String(sGd.tree).indexOf(markGd) >= 0) methodGd = 'WINDOW';
  } catch (e) {}
}
if (!methodGd) {
  try {
    const rGd = await gmail.search(__UID__, 'in:drafts subject:"' + subjGd + '"');
    const txtGd = JSON.stringify(rGd);
    if (txtGd.indexOf(subjGd) >= 0 || txtGd.indexOf(JSON.stringify(subjGd).slice(1, -1)) >= 0) {
      methodGd = 'SEARCH';
      const arrGd = Array.isArray(rGd) ? rGd : ((rGd && (rGd.threads || rGd.messages || rGd.results)) || []);
      for (const it of arrGd) {
        if (JSON.stringify(it).indexOf(subjGd) >= 0) { tidGd = String(it.threadId || it.id || ''); break; }
      }
    }
  } catch (e) {}
}
if (methodGd) { try { await closeTab(cpGd); } catch (e) {} }
console.log('DRAFT_RESULT\t' + (methodGd ? 'FOUND' : 'NOTFOUND') + '\t' + methodGd + '\t' + tidGd);
EOJS

MARK_B64="$(printf '%s' '임시보관함에 저장됨' | base64 | tr -d '\r\n')"

# 값 안의 &가 치환 문법에 쓰이지 않도록 문자열 연결로 자리를 채웁니다.
fill() { # fill <텍스트> <자리표시자> <값>
  printf '%s' "${1%%"$2"*}$3${1#*"$2"}"
}
CODE="$(fill "$JS_TEMPLATE" __SUBJ__ "$B64_SUBJ")"
CODE="$(fill "$CODE" __BODY__ "$B64_BODY")"
CODE="$(fill "$CODE" __MARK__ "$MARK_B64")"
CODE="$(fill "$CODE" __TO__ "$TO")"
CODE="$(fill "$CODE" __UID__ "$UID_N")"

NOW="$(TZ=UTC-9 date '+%Y-%m-%d %H:%M')"
mkdir -p "$(dirname "$LOG")" || { echo "오류: 로그 폴더를 만들 수 없습니다." >&2; exit 4; }

TMP="$(mktemp)" || exit 4
trap 'rm -f "$TMP"' EXIT

write_log() {
  if [ ! -s "$LOG" ]; then
    printf '# Gmail 임시보관함 초안 로그\n\n> 이 로그는 초안 생성 기록입니다. 메일은 발송하지 않았습니다. 같은 기준일을 다시 실행하면 초안이 중복 생성될 수 있습니다.\n\n' > "$LOG"
  fi
  {
    printf -- '- 시각(서울): %s\n' "$NOW"
    printf '  - 수신자: %s\n' "$TO"
    printf '  - 제목: %s\n' "$SUBJECT"
    printf '  - 결과: %s\n' "$1"
    if [ -n "${2:-}" ]; then printf '  - threadId: %s\n' "$2"; fi
    if [ -n "${3:-}" ]; then printf '  - 확인 방식: %s
' "$3"; fi
  } >> "$LOG"
}

timeout 120 "$ASIDE" repl "$CODE" > "$TMP"
RC=$?

if [ "$RC" -eq 124 ]; then
  write_log "실패(120초 시간 초과)"
  echo "오류: 120초 안에 끝나지 않았습니다(시간 초과). Gmail 임시보관함을 직접 확인해 주세요." >&2
  exit 124
fi
if [ "$RC" -ne 0 ]; then
  write_log "실패(Aside 종료코드 $RC)"
  echo "오류: Aside 실행에 실패했습니다(종료코드 $RC)." >&2
  exit "$RC"
fi

LINE="$(grep -a '^DRAFT_RESULT' "$TMP" | tail -n 1 | tr -d '\r')"
STATUS="$(printf '%s' "$LINE" | awk -F'\t' '{print $2}')"
METHOD="$(printf '%s' "$LINE" | awk -F'	' '{print $3}')"
TID="$(printf '%s' "$LINE" | awk -F'	' '{print $4}')"

if [ "$STATUS" = "FOUND" ]; then
  if [ "$METHOD" = "WINDOW" ]; then MLABEL="작성 창 표시"; else MLABEL="검색"; fi
  write_log "임시저장 확인" "$TID" "$MLABEL"
  echo "Gmail 임시보관함 저장을 확인했습니다(확인 방식: $MLABEL). 발송하지 않았습니다."
  exit 0
fi

write_log "실패(작성 창 저장 표시와 검색 모두 확인하지 못함)" "" "작성 창 표시 / 검색"
echo "오류: 저장 표시도 검색 결과도 확인하지 못했습니다. Gmail 임시보관함을 직접 확인해 주세요." >&2
exit 5
