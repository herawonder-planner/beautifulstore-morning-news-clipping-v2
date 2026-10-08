#!/usr/bin/env bash
# clipping-draft.md를 메일 본문용 간단한 HTML로 바꿉니다. (네트워크·Aside 사용 없음)
# 사용: bash make-mail-html.sh <clipping-draft.md> <out.html>
# 지원: # ## ### > 번호 목록(+ 근거 줄) 표 일반 문단. 표는 첫 행을 th, 나머지를 td로 만듭니다.
# 종료코드: 0 성공 / 2 입력 오류 / 4 저장 실패

set -u

IN="${1:-}"
OUT="${2:-}"

if [ -z "$IN" ] || [ -z "$OUT" ]; then
  echo "사용법: bash make-mail-html.sh <clipping-draft.md> <out.html>" >&2
  exit 2
fi
if [ ! -s "$IN" ]; then
  echo "오류: 입력 파일이 없거나 비어 있습니다: $IN" >&2
  exit 2
fi
mkdir -p "$(dirname "$OUT")" || { echo "오류: 저장 폴더를 만들 수 없습니다." >&2; exit 4; }

TMP="$OUT.tmp"
awk '
function esc(s) {
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  return s
}
function trim(s) {
  sub(/^[ \t]+/, "", s)
  sub(/[ \t]+$/, "", s)
  return s
}
function close_li() { if (in_li) { print "</li>"; in_li = 0 } }
function close_ol() { close_li(); if (in_ol) { print "</ol>"; in_ol = 0 } }
function close_table() { if (in_table) { print "</table>"; in_table = 0; row_no = 0 } }
function close_all() { close_ol(); close_table() }
BEGIN {
  print "<!DOCTYPE html>"
  print "<html lang=\"ko\"><head><meta charset=\"utf-8\"></head>"
  print "<body style=\"font-family:Manrope,Arial,sans-serif;color:#222;line-height:1.6;\">"
  in_table = 0; in_ol = 0; in_li = 0; row_no = 0
}
{
  line = $0
  sub(/\r$/, "", line)

  # 표 행
  if (line ~ /^[ \t]*\|/) {
    close_ol()
    t = trim(line)
    sub(/^\|/, "", t)
    sub(/\|$/, "", t)
    n = split(t, cells, "|")
    sep = 1
    for (i = 1; i <= n; i++) {
      c = trim(cells[i])
      cells[i] = c
      if (c !~ /^:?-+:?$/) sep = 0
    }
    if (sep) next
    if (!in_table) {
      print "<table style=\"border-collapse:collapse;margin:8px 0 16px;\">"
      in_table = 1; row_no = 0
    }
    printf "<tr>"
    for (i = 1; i <= n; i++) {
      if (row_no == 0)
        printf "<th style=\"border:1px solid #cfc8b8;padding:4px 10px;background:#f1ede2;text-align:left;\">%s</th>", esc(cells[i])
      else
        printf "<td style=\"border:1px solid #cfc8b8;padding:4px 10px;\">%s</td>", esc(cells[i])
    }
    print "</tr>"
    row_no++
    next
  }
  close_table()

  # 번호 목록 항목의 근거 줄
  if (in_li && line ~ /^[ \t]+-[ \t]+/) {
    s = line
    sub(/^[ \t]+-[ \t]+/, "", s)
    printf "<br><small>%s</small>", esc(s)
    next
  }

  # 번호 목록
  if (line ~ /^[0-9]+\.[ \t]+/) {
    close_li()
    if (!in_ol) { print "<ol>"; in_ol = 1 }
    s = line
    sub(/^[0-9]+\.[ \t]+/, "", s)
    printf "<li>%s", esc(s)
    in_li = 1
    next
  }

  close_ol()

  if (trim(line) == "") next
  if (line ~ /^---+[ \t]*$/) { print "<hr>"; next }
  if (line ~ /^<!--.*-->[ \t]*$/) next

  if (line ~ /^### /) { s = line; sub(/^### +/, "", s); print "<h3>" esc(s) "</h3>"; next }
  if (line ~ /^## /)  { s = line; sub(/^## +/, "", s);  print "<h2>" esc(s) "</h2>"; next }
  if (line ~ /^# /)   { s = line; sub(/^# +/, "", s);   print "<h1 style=\"color:#2D5A27;\">" esc(s) "</h1>"; next }
  if (line ~ /^>/)    { s = line; sub(/^>[ \t]*/, "", s); print "<p><em>" esc(s) "</em></p>"; next }

  print "<p>" esc(trim(line)) "</p>"
}
END {
  close_all()
  print "</body></html>"
}
' "$IN" > "$TMP" || { rm -f "$TMP"; echo "오류: 변환에 실패했습니다." >&2; exit 4; }

mv -f "$TMP" "$OUT" || { echo "오류: 결과를 저장하지 못했습니다." >&2; exit 4; }
echo "저장 완료: $OUT"
