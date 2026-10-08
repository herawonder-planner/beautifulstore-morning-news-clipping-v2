# 개인 기획서 구현 팀

팀: Opus 5.5 + Sonnet 5.5

- 같은 프로젝트·같은 대화에서 작은 완성마다 01 → 02 → 03을 반복하고, 현재 결과를 저장·공유할 때 04를 사용하세요.
- 1단계에서 기획서에 맞는 역할·담당 파일·완료 조건을 정하고 이 문서에 기록하세요.
- 작업자 수는 과제에 필요한 만큼만 구성하세요.
- Codex 총괄은 GPT-6.1 Sol Medium Standard, 구현은 Luna High입니다.
- Claude 총괄은 Opus 5.5 Medium, 구현은 Sonnet 5.5 Medium입니다.
- 설정과 실제 실행 모델은 다를 수 있으므로 실행 기록을 확인하세요. 사용할 수 없는 모델은 알리고 임의로 바꾸지 마세요.

---

## 첫 번째 작은 완성 · 기사 원문 1건 요약 (2026-10-08 확정)

### 범위
- 포함: 지정한 기사 URL 1건을 Aside로 열어 제목·매체·발행일·본문 확인 → 원문 근거가 붙은 3줄 요약을 `output/clipping-draft.md`로 저장. 원문 접근 실패 시 요약 없이 실패 기록.
- 제외: 전날 기사 검색·여러 건 수집·중복 처리·수집 CSV(다음 개선 1), 웹메일·메신저 초안(다음 개선 2), 예약 실행, 실제 발송.
- 결과물 내부 AI 처리: 원문 읽기 후 AI 요약 1회. 결과물 안에 에이전트 역할·병렬 처리·코디네이터를 두지 않습니다.

### 역할
| 역할 | 설정 모델 / 추론 | 하는 일 | 담당 파일 |
|---|---|---|---|
| 총괄 (메인 대화) | Opus 5.5 / Medium | 설계·지시·통합, Aside 실제 실행, 결과 대조 | `DESIGN.md`, `TEAM.md`, 실행 결과 `output/` |
| project_builder | Sonnet 5.5 / Medium (`.claude/agents/project_builder.md`) | 스킬 절차·출력 양식·샘플·사용 안내 작성 | `.claude/skills/news-clipping/SKILL.md`, `templates/clipping-draft.md`, `samples/`, `사용해보기.md` |
| project_reviewer | Opus 5.5 / Medium (`.claude/agents/project_reviewer.md`) | 원문과 요약 독립 대조(읽기 전용, 수정 없음) | 없음 |

- 실제 사용 모델(2026-10-08, 실행 기록 subagents/*.jsonl의 model 값으로 확인): project_builder = claude-sonnet-5-5, project_reviewer = claude-opus-5-5, 총괄 = claude-opus-5-5.
- Aside·브라우저 실행은 총괄만 합니다. 하위 에이전트의 추가 위임 금지.

### 의존 관계와 통합 책임
1. project_builder: 양식·스킬 절차·샘플 작성 (DESIGN.md 2절 형식 준수)
2. 총괄: 결과 통합 → Aside로 정상 샘플 실행 → `output/clipping-draft.md` 생성
3. project_reviewer: 원문 ↔ 출력 대조 보고
- 각 단계가 앞 단계 결과를 사용하므로 병행하지 않습니다. 통합 책임은 총괄에게 있습니다.

### 정상 샘플 (실제 기사)
- 기사: 아름다운가게, '세계 자원봉사자의 해' 특별 나눔전 개최···일상 속 봉사 가치 확산
- 매체 / 입력: 스마트비즈 / 2026.10.08 09:51
- URL: https://www.smartbizn.com/news/articleView.html?idxno=155883
- 선정 이유: 제목에 '아름다운가게' 포함, 로그인 없이 본문 공개(2026-10-08 총괄이 내장 브라우저로 열람 확인).
- 실행 위치: 이 프로젝트 폴더를 연 Claude Code에서 스킬 호출 (예: "이 URL로 뉴스 클리핑 해줘")

### 완료 조건
- [x] Aside로 위 URL 원문을 실제로 열었다는 실행 기록이 있다.
- [x] `output/clipping-draft.md`가 DESIGN.md 시안 B 형식으로 생성된다.
- [x] 제목·매체·발행일·URL이 원문과 정확히 일치한다.
- [x] 3줄 요약의 각 근거 인용이 원문에 실제로 존재하고, 원문에 없는 내용이 없다.
- [x] 실제 기사 결과에 `[가상 예시]` 표시가 없고, 가상 데이터로 검증할 때는 표시가 있다.
- [x] 접근 불가 URL에서는 요약 없이 `접근 실패`가 기록된다(가벼운 확인 1회).
- [x] project_reviewer의 독립 대조 결과와 실제 사용 모델이 기록된다.

### 2단계 실행 기록 (2026-10-08)
- project_builder(Sonnet 5.5): SKILL.md·read-article.sh·템플릿·가상 샘플·사용해보기.md 작성. 총괄이 서울 시간 오류(Git Bash에서 `TZ=Asia/Seoul`이 UTC로 출력)를 찾아 `TZ=UTC-9`로 수정 요청 → 반영.
- 총괄: `read-article.sh`로 Aside repl 실행 → `output/raw/article-snapshot.txt` 저장(종료코드 0, 연속 2회 정상). SKILL.md 절차대로 `output/clipping-draft.md`, `output/clipping-draft-virtual.md` 생성. 근거 인용 6개 원문 일치(grep -F).
- 접근 실패 시험: 없는 기사 번호 URL → 제목·본문 없음 → `output/access-fail-test.md`. 정상 결과를 덮어쓰지 않으려고 별도 파일로 저장(실제 스킬은 `output/clipping-draft.md`에 기록).
- 스킬 호출: 이 대화는 스킬 생성 전에 시작돼 `/news-clipping`이 목록에 없어 총괄이 SKILL.md 절차를 따라 실행. 새 대화에서 `/news-clipping` 호출은 3단계에서 확인 예정(미확인).
- project_reviewer(Opus 5.5): 결과·가상·실패·형식·범위 5개 항목 통과, 왜곡·없는 수치 없음.

### 3단계 결과 확인 기록 (2026-10-08)
- 이번 작은 완성에 해당하는 TEST: TEST-01 일부(원문 1건 읽기·출처·발행일·근거 요약), TEST-02 일부(본문 접근 불가). 0건 보고서·수집 CSV(다음 개선 1), TEST-03 웹메일 초안(다음 개선 2)은 제외.
- 실제 스킬 호출: `/news-clipping samples/가상기사-되살림터-개소.txt` 호출 성공 → `output/clipping-draft-virtual.md` 갱신(16:15), 근거 3개 샘플 일치.
- 예외 시험(read-article.sh): 빈 입력 RC=2, http 아님 RC=2, 따옴표 포함 RC=2, Aside 없음 RC=3 — 모두 결과 파일 미생성.
- 발견·수정: SKILL.md에 '샘플 파일 없음/빈 파일' 처리 규칙이 없어 project_builder가 추가(가상 내용 생성 금지).
- 입력 바꿔보기용 기사 확인: 한국NGO신문 https://www.ngonews.kr/news/articleView.html?idxno=239591 (기사입력 2026.10.01 10:25) Aside로 제목·입력일 읽기 확인.
- 참가자 직접 실행: 미확인.

## 다음 개선 1+2 일부 · 전날 수집 + 시트 쌓기 + Gmail 임시보관함 초안 + 매일 8시 루틴 (2026-10-08, 참가자 요청)
- 범위: 전날 '아름다운가게' 기사 검색·원문 읽기·키워드/중복/실패 판정, 수집 CSV·요약 초안, Google 시트 '2026 뉴스클리핑' 쌓기, Gmail 임시보관함 초안(발송 없음), 매일 08시 예약. 제외: 실제 발송·공유.
- project_builder(Sonnet 5.5): search-news.sh, create-gmail-draft.sh, make-mail-html.sh, append-to-sheet.sh, daily-clipping 양식, 가상 검색 샘플, SKILL.md 6~9절, routine/daily-8am.md.
- 총괄 실행 중 발견·수정: ① Git Bash `&` 치환 버그로 검색 주소가 깨짐 → 문자열 연결로 수정 ② 메일 HTML 표 값 누락 → make-mail-html.sh ③ gmail.search 불안정 → 작성 창 '임시보관함에 저장됨' 표시로 확인 ④ 시트 readSheet 재확인 실패 → CSV 내보내기로 확인·중복 방지.
- 실제 실행(기준일 2026-10-07): 검색 10 / 원문 확인 3 / 접근 실패 0 / 제외(키워드 불일치) 3 / 중복 4. 근거 인용 9개 grep -F 원문 일치.
- 시트: 헤더+10행 쌓임(CSV 내보내기로 확인), 같은 기준일 재실행 시 종료코드 6으로 건너뜀 확인.
- Gmail: config.local.env의 수신 주소 수신 초안 임시저장 확인(16:53). 발송 없음. 남은 정리: 표가 깨진 이전 초안(16:45)과 시험 초안(16:46)은 담당자가 직접 삭제 필요.
- 예약: Claude 앱 예약 작업 `beautifulstore-news-clipping-8am` 매일 08시대(앱 표시 08:12). 앱과 PC가 켜져 있고 Aside 로그인 필요.
- 미확인: 예약 실행 1회차 결과, '네이버 Keep' 링크로 search-results.tsv 매체 칸이 틀리는 문제(최종 매체명은 원문에서 확인해 영향 없음).
