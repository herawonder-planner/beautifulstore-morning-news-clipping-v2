#!/usr/bin/env bash
# 클리핑 결과 행을 Google 스프레드시트 첫 시트(gid 0)에 이어 씁니다. (Aside google-sheets 사용)
# 사용: bash append-to-sheet.sh <시트URL> <rows.tsv> <기준일YYYY-MM-DD> [--force]
# rows.tsv: 헤더 없는 탭 구분 12열
#   수집일시(서울) | 기준일 | 순번 | 매체 | 제목 | 발행일 | URL | 상태 | 요약 1 | 요약 2 | 요약 3 | 비고
# 종료코드: 0 성공 / 2 입력 오류 / 3 aside 없음 / 6 이미 쌓인 기준일 / 7 쓴 뒤 확인 실패
#           124 시간 초과 / 그 외 실패(실패 단계는 stderr)
# 이 스크립트는 지정한 시트 외에는 아무것도 쓰지 않고, 메일·공유 기능을 쓰지 않습니다.

set -u
shopt -u patsub_replacement 2>/dev/null || true

SHEET_URL="${1:-}"
ROWS="${2:-}"
DAY="${3:-}"
FORCE="${4:-}"

if [ -z "$SHEET_URL" ] || [ -z "$ROWS" ] || [ -z "$DAY" ]; then
  echo "사용법: bash append-to-sheet.sh <시트URL> <rows.tsv> <기준일YYYY-MM-DD> [--force]" >&2
  exit 2
fi
if [ -n "$FORCE" ] && [ "$FORCE" != "--force" ]; then
  echo "오류: 네 번째 인자는 --force만 사용할 수 있습니다." >&2
  exit 2
fi
if ! printf '%s' "$DAY" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || ! date -d "$DAY" '+%Y-%m-%d' >/dev/null 2>&1; then
  echo "오류: 기준일은 존재하는 날짜의 YYYY-MM-DD 형식이어야 합니다." >&2
  exit 2
fi

# 시트 주소: https://docs.google.com/spreadsheets/d/<ID>/... 형식만 허용
SHEET_ID=""
if [[ "$SHEET_URL" =~ ^https://docs\.google\.com/spreadsheets/d/([A-Za-z0-9_-]+)(/|\?|#|$) ]]; then
  SHEET_ID="${BASH_REMATCH[1]}"
else
  echo "오류: 시트 주소는 https://docs.google.com/spreadsheets/d/<ID>/... 형식이어야 합니다." >&2
  exit 2
fi

if [ ! -s "$ROWS" ]; then
  echo "오류: rows.tsv가 없거나 비어 있습니다: $ROWS" >&2
  exit 2
fi
BAD="$(tr -d '\r' < "$ROWS" | awk -F'\t' 'NF > 0 && NF != 12 {print NR; exit}')"
if [ -n "$BAD" ]; then
  echo "오류: rows.tsv ${BAD}번째 줄의 열 수가 12가 아닙니다." >&2
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

B64_ROWS="$(tr -d '\r' < "$ROWS" | base64 | tr -d '\r\n')"
FORCE_JS="false"
[ "$FORCE" = "--force" ] && FORCE_JS="true"
# ID와 기준일은 위에서 검증한 문자만 들어 있습니다. 계정 uid는 환경변수 CLIP_GOOGLE_UID(기본 0, 숫자만)입니다.
UID_N="${CLIP_GOOGLE_UID:-0}"
if ! printf '%s' "$UID_N" | grep -Eq '^[0-9]{1,2}$'; then
  echo "오류: CLIP_GOOGLE_UID는 숫자만 사용할 수 있습니다." >&2
  exit 2
fi
SHEET_BASE="https://docs.google.com/spreadsheets/u/${UID_N}/d/${SHEET_ID}/edit"

read -r -d '' JS_TEMPLATE <<'EOJS'
const baseUrlSh = '__BASE__';
const idSh = '__ID__';
const dayShh = '__DAY__';
const forceSh = __FORCE__;
const rowsSh = Buffer.from('__ROWS__', 'base64').toString('utf8')
  .split('\n').filter((l) => l.trim() !== '').map((l) => l.split('\t'))
  .map((r) => r.map((c) => (/^[=+@]/.test(c) ? ' ' + c : c)));
const HEADER_SH = ['수집일시(서울)', '기준일', '순번', '매체', '제목', '발행일', 'URL', '상태', '요약 1', '요약 2', '요약 3', '비고'];
const EXPORT_URL = 'https://docs.google.com/spreadsheets/d/' + idSh + '/export?format=csv&gid=0';
let stepSh = 'start';
let outSh = ['ERROR', stepSh, ''];
const sleepSh = (ms) => new Promise((r) => setTimeout(r, ms));
const normDate = (v) => {
  if (typeof v === 'number' && v > 30000 && v < 80000) {
    return new Date(Date.UTC(1899, 11, 30) + Math.round(v) * 86400000).toISOString().slice(0, 10);
  }
  const m = String(v).trim().match(/^(\d{4})\s*[-./]\s*(\d{1,2})\s*[-./]\s*(\d{1,2})/);
  return m ? m[1] + '-' + String(m[2]).padStart(2, '0') + '-' + String(m[3]).padStart(2, '0') : String(v).trim();
};
const hasVal = (c) => c && c.valueType !== 'empty' && c.value !== undefined && String(c.value).trim() !== '';
// 큰따옴표·쉼표·줄바꿈을 처리하는 간단한 CSV 파서
const parseCsv = (text) => {
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (q) {
      if (ch === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; }
      else cell += ch;
    } else if (ch === '"') q = true;
    else if (ch === ',') { row.push(cell); cell = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); cell = ''; rows.push(row); row = [];
    } else cell += ch;
  }
  if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
  while (rows.length && rows[rows.length - 1].every((c) => String(c).trim() === '')) rows.pop();
  return rows;
};
// CSV 내보내기. 실패 사유(상태 코드, HTML 로그인 페이지)를 why에 담는다.
const exportRows = async () => {
  try {
    const r = await fetch(EXPORT_URL);
    if (r.status !== 200) return { ok: false, why: '내보내기 응답이 200이 아님(상태 ' + r.status + ')' };
    const t = await r.text();
    if (/^\s*<(!doctype|html)/i.test(t.slice(0, 200))) return { ok: false, why: '내보내기 응답이 HTML(로그인 페이지로 보임)' };
    return { ok: true, rows: parseCsv(t) };
  } catch (e) {
    return { ok: false, why: '내보내기 요청 실패: ' + String(e && e.message ? e.message : e).replace(/\s+/g, ' ') };
  }
};
try {
  stepSh = '기존 내용 읽기(CSV 내보내기)';
  let existing = null; // 헤더 포함 행 배열
  let lastRow = 0;
  const ex = await exportRows();
  if (ex.ok) {
    existing = ex.rows;
    lastRow = existing.length;
  } else {
    // 보조: export가 실패할 때만 readSheet
    stepSh = '기존 내용 읽기(readSheet 보조)';
    const info = await googleSheets.getSpreadsheetInfo(baseUrlSh + '#gid=0');
    const sh = (info.sheets || []).find((s) => String(s.gid) === '0') || (info.sheets || [])[0];
    if (!sh) throw new Error('시트를 찾을 수 없습니다(' + ex.why + ')');
    const data = await googleSheets.readSheet(baseUrlSh + '#gid=' + String(sh.gid), String(sh.gid));
    const cells = (data.cells || []).filter(hasVal);
    lastRow = cells.length === 0 ? 0 : Math.max(cells.reduce((m, c) => Math.max(m, c.row || 0), 0), (sh.size && sh.size.rows) || 0);
    existing = [];
    for (const c of cells) {
      existing[(c.row || 1) - 1] = existing[(c.row || 1) - 1] || [];
      existing[(c.row || 1) - 1][c.col] = String(c.value);
    }
  }
  const urlSh = baseUrlSh + '#gid=0';
  const empty = lastRow === 0;

  stepSh = '중복 확인';
  const dup = existing.some((r, i) => i >= 1 && r && normDate(r[1] === undefined ? '' : r[1]) === dayShh);
  if (dup && !forceSh) {
    outSh = ['DUP', stepSh, '기준일 ' + dayShh + '은(는) 이미 쌓여 있습니다'];
  } else {
    // 다음 행 = 기존 행 수 + 1(헤더 포함). 비어 있으면 헤더와 함께 A1부터 씁니다.
    const startRow = empty ? 1 : lastRow + 1;
    const matrix = empty ? [HEADER_SH].concat(rowsSh) : rowsSh;

    stepSh = '시트 열기';
    await googleSheets.connect(urlSh);
    stepSh = '행 쓰기';
    await googleSheets.writeMatrix('A' + startRow, matrix);

    // 쓴 뒤 확인: 모든 행의 (기준일, URL) 쌍을 CSV 내보내기에서 찾는다. URL이 빈 행은 (기준일, 상태).
    stepSh = '쓴 뒤 확인(CSV 내보내기)';
    let whySh = '';
    let missing = rowsSh.length;
    for (let t = 0; t < 5; t++) {
      await sleepSh(2000);
      const back = await exportRows();
      if (!back.ok) { whySh = back.why; continue; }
      whySh = '';
      const got = back.rows.slice(startRow - 1);
      missing = rowsSh.filter((w) => {
        const d = normDate(w[1]); const u = String(w[6]).trim(); const s = String(w[7]).trim();
        return !got.some((g) => normDate(g[1] === undefined ? '' : g[1]) === d &&
          (u !== '' ? String(g[6] === undefined ? '' : g[6]).trim() === u
                    : (String(g[6] === undefined ? '' : g[6]).trim() === '' && String(g[7] === undefined ? '' : g[7]).trim() === s)));
      }).length;
      if (missing === 0) break;
    }
    const noteSh = dup ? ' (--force: 이미 쌓인 기준일에 다시 씀)' : '';
    if (whySh) {
      outSh = ['VERIFY_FAIL', stepSh, whySh + '. 쓰기는 했을 수 있으니 시트를 직접 확인해 주세요' + noteSh];
    } else if (missing === 0) {
      outSh = ['OK', stepSh, rowsSh.length + '행을 ' + startRow + '행부터 씀' + noteSh];
    } else {
      outSh = ['VERIFY_FAIL', stepSh, '쓴 ' + rowsSh.length + '행 중 ' + missing + '행을 시트에서 찾지 못함. 시트를 직접 확인해 주세요' + noteSh];
    }
  }
} catch (e) {
  outSh = ['ERROR', stepSh, String(e && e.message ? e.message : e).replace(/\s+/g, ' ')];
} finally {
  try { await googleSheets.dispose(); } catch (e2) {}
}
console.log('SHEET_RESULT\t' + outSh.join('\t'));
EOJS

fill() { # fill <텍스트> <자리표시자> <값> : 치환 문법 대신 문자열 연결
  printf '%s' "${1%%"$2"*}$3${1#*"$2"}"
}
CODE="$(fill "$JS_TEMPLATE" __BASE__ "$SHEET_BASE")"
CODE="$(fill "$CODE" __ID__ "$SHEET_ID")"
CODE="$(fill "$CODE" __DAY__ "$DAY")"
CODE="$(fill "$CODE" __FORCE__ "$FORCE_JS")"
CODE="$(fill "$CODE" __ROWS__ "$B64_ROWS")"

TMP="$(mktemp)" || exit 4
trap 'rm -f "$TMP"' EXIT

timeout 120 "$ASIDE" repl "$CODE" > "$TMP"
RC=$?
if [ "$RC" -eq 124 ]; then
  echo "오류: 120초 안에 끝나지 않았습니다(시간 초과). 시트에 일부 쓰였을 수 있으니 직접 확인해 주세요." >&2
  exit 124
fi
if [ "$RC" -ne 0 ]; then
  echo "오류: Aside 실행에 실패했습니다(종료코드 $RC)." >&2
  exit "$RC"
fi

LINE="$(grep -a '^SHEET_RESULT' "$TMP" | tail -n 1 | tr -d '\r')"
STATUS="$(printf '%s' "$LINE" | awk -F'\t' '{print $2}')"
STEP="$(printf '%s' "$LINE" | awk -F'\t' '{print $3}')"
MSG="$(printf '%s' "$LINE" | awk -F'\t' '{print $4}')"

case "$STATUS" in
  OK)
    echo "시트에 쌓았습니다: $MSG"
    exit 0
    ;;
  DUP)
    echo "이미 쌓인 기준일입니다: $MSG (다시 쓰려면 --force)" >&2
    exit 6
    ;;
  VERIFY_FAIL)
    echo "오류: [$STEP] $MSG" >&2
    exit 7
    ;;
  *)
    echo "오류: [${STEP:-알 수 없음}] ${MSG:-결과를 받지 못했습니다}" >&2
    exit 1
    ;;
esac
