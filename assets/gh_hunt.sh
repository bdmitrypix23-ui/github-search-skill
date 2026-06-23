#!/bin/bash
# Шаблон большого захода по GitHub (50-100 поисков) с дедупом, JSON-итогом и логом.
# КАК ПОЛЬЗОВАТЬСЯ:
#   1. Правь массивы R/G/C/N под свою тему (примеры ниже — headless-браузеры).
#      Тему задай: GH_HUNT_TITLE='аудио в текст' bash gh_hunt.sh — попадёт в заголовок.
#   2. Запускай в фоне (~2-4 мин). Пути результата печатаются СРАЗУ.
#   3. Читай h_results.json (единственный артефакт; секции repos/code/recon/niches/techniques/run).
#      run.complete=false => были сбои (см. run.fail/rate_limited/auth_fail) => часть
#      запросов не отработала, улов может быть неполным.
# Помощники: R=REST repo-поиск, G=GraphQL repo, C=поиск по коду, N=проверка по имени,
#            raw=произвольный gh-вызов (логируется и ловит ошибки так же).
set +e   # намеренно: один упавший поиск не должен ронять весь заход

TITLE="${GH_HUNT_TITLE:-правь под тему}"
WORK="${GH_HUNT_OUT:-$(mktemp -d -t gh_hunt)}"
mkdir -p "$WORK"
ERRF="$WORK/.err"
REPOS="$WORK/h_repos.tsv"; CODE="$WORK/h_code.tsv"; TECH="$WORK/h_tech.tsv"; NICHE="$WORK/h_niche.tsv"
: > "$REPOS"; : > "$CODE"; : > "$TECH"; : > "$NICHE"
PAUSE=2.2   # под рейт-лимит Search API (30/мин; code search строже — 10/мин)
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
RUN="$(date +%Y%m%dT%H%M%S)-$$"

# --- ЛОГ (JSONL, friendly для агента: jq -c . <файл>) ---
LOGDIR="$HOME/.claude/logs/github-search"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/hunt-$(date +%F).jsonl"
# ротация: убрать логи старше 7 дней
find "$LOGDIR" -name 'hunt-*.jsonl' -type f -mtime +7 -delete 2>/dev/null
# ротация по размеру: пока папка > 1 ГБ, удалять самый старый файл
while [ "$(du -sk "$LOGDIR" 2>/dev/null | cut -f1)" -gt 1048576 ]; do
  oldest=$(ls -1tr "$LOGDIR"/hunt-*.jsonl 2>/dev/null | head -1); [ -z "$oldest" ] && break; rm -f "$oldest"
done

# logj engine label query status results error  → одна JSONL-строка
logj(){
  if [ "$HAVE_JQ" = 1 ]; then
    jq -nc --arg ts "$(date -u +%FT%TZ)" --arg run "$RUN" --arg title "$TITLE" \
      --arg engine "$1" --arg label "$2" --arg query "$3" --arg status "$4" \
      --argjson results "${5:-0}" --arg error "${6:-}" \
      '{ts:$ts,run:$run,title:$title,engine:$engine,label:$label,query:$query,status:$status,results:$results,error:$error}' >> "$LOG"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$RUN" "$1" "$2" "$4" "${5:-0}" "${6:-}" >> "$LOG"
  fi
}

# Счётчики прогона
OK=0; EMPTY=0; FAIL=0; RATE=0; AUTH=0

# Классифицировать ошибку gh по тексту stderr → вид + понятная подсказка
classify(){ # $1=stderr-текст ; печатает "вид|человеко-подсказка"
  case "$1" in
    *"rate limit"*|*"403"*|*"too quickly"*|*"exceeded"*) echo "rate_limit|RATE LIMIT — дальше будет падать; жди ~60с или гоняй реже" ;;
    *"auth"*|*"401"*|*"Bad credentials"*|*"gh auth"*)     echo "auth|НЕ АВТОРИЗОВАН — выполни: gh auth login" ;;
    *"Could not resolve"*|*"network"*|*"timeout"*)        echo "network|СЕТЬ недоступна — проверь интернет" ;;
    *) echo "other|$(printf '%s' "$1" | tr '\n' ' ' | cut -c1-80)" ;;
  esac
}

# Общий разбор результата вызова: rc, out → статус, счётчики, лог, friendly-маркер в stderr
finish(){ # $1=engine $2=label $3=query $4=rc $5=out
  local eng="$1" L="$2" Q="$3" rc="$4" out="$5" n status errkind errmsg
  if [ "$rc" -ne 0 ]; then
    local c; c=$(classify "$(cat "$ERRF" 2>/dev/null)"); errkind="${c%%|*}"; errmsg="${c#*|}"
    status=fail; FAIL=$((FAIL+1))
    [ "$errkind" = rate_limit ] && RATE=$((RATE+1)); [ "$errkind" = auth ] && AUTH=$((AUTH+1))
    printf '  [!] %-22s %s\n' "$L" "$errmsg" >&2
    logj "$eng" "$L" "$Q" "fail" 0 "$errkind"
    printf '%s\t%s\n' "$L" "ERR:$errkind" >> "$TECH"; return
  fi
  n=$(printf '%s' "$out" | grep -c '^.')
  if [ "$n" -gt 0 ]; then status=ok; OK=$((OK+1)); printf '  [+] %-22s %s\n' "$L" "$n" >&2
  else status=empty; EMPTY=$((EMPTY+1)); printf '  [-] %-22s 0\n' "$L" >&2; fi
  logj "$eng" "$L" "$Q" "$status" "$n" ""
  printf '%s\t%s\n' "$L" "$n" >> "$TECH"
}

R(){ local L="$1" Q="$2" S="${3:-stars}" O="${4:-desc}" out
  out=$(gh api -X GET search/repositories -f q="$Q" -f sort="$S" -f order="$O" -f per_page=8 \
     -q '.items[] | "\(.stargazers_count)\t\(.full_name)\t\(.description // ""|.[0:70])"' 2>"$ERRF"); local rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | sed '/^$/d; s|$|\t'"$L"'|' >> "$REPOS"
  finish "REST" "$L" "$Q" "$rc" "$out"; sleep $PAUSE; }
G(){ local L="$1" Q="$2" out
  out=$(gh api graphql -f query="{ search(query:\"$Q\", type:REPOSITORY, first:8){ nodes{ ... on Repository{ nameWithOwner stargazerCount description } } } }" \
     -q '.data.search.nodes[] | "\(.stargazerCount)\t\(.nameWithOwner)\t\(.description // ""|.[0:70])"' 2>"$ERRF"); local rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | sed '/^$/d; s|$|\t'"$L"'|' >> "$REPOS"
  finish "graphql" "$L" "$Q" "$rc" "$out"; sleep $PAUSE; }
C(){ local L="$1" Q="$2" out
  out=$(gh search code "$Q" --limit 6 --json repository,path -q '.[] | "\(.repository.nameWithOwner)::\(.path)"' 2>"$ERRF"); local rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | sed '/^$/d; s|$|\t'"$L"'|' >> "$CODE"
  finish "code" "$L" "$Q" "$rc" "$out"; sleep $PAUSE; }
N(){ R "byname:$1" "$1 stars:>30"; }
# raw: произвольный gh-вызов в разведке. $1=engine $2=label $3=query-для-лога; команда из stdin
raw(){ local eng="$1" L="$2" Q="$3" out; out=$(eval "$4" 2>"$ERRF"); local rc=$?
  [ $rc -eq 0 ] && printf '%s\n' "$out" | sed '/^$/d' >> "$REPOS"
  finish "$eng" "$L" "$Q" "$rc" "$out"; sleep $PAUSE; }

echo "GH HUNT — тема: $TITLE   (run $RUN)"
echo "  гоняю веер (~2-4 мин, можно не следить). Результаты:"
echo "  json -> $WORK/h_results.json   (появится в конце, ~2-4 мин — читай его)"
echo "  лог  -> $LOG   (JSONL: jq -c . <файл>)"
echo "  -- прогресс (приём -> улов; [!] = ошибка) --"

############ ВЕЕР ПОИСКОВ — правь под свою тему ############
R "topic combo"        'topic:web-scraping topic:anti-bot stars:>100'
R "order=asc gems"     'headless browser llm stars:>50' stars asc
R "sort=forks used"    'headless browser automation stars:>500' forks
R "mature <2022"       'headless browser created:<2022 stars:>2000'
R "fresh >2025"        'browser agent screenshot created:>2025-06-01 stars:>100'
R "lang rust speed"    'headless browser language:rust stars:>50'
# OR работает в raw api, но НЕ комбинируй с общим словом (browser/web/app) — натащит мусор
R "OR raw api"         '(undetected OR antidetect) chromium stars:>200'
G "graphql short"      'undetected browser stars:>300'
# Имена тяжеловесов ниши
N undetected-chromedriver; N nodriver; N camoufox; N botasaurus; N seleniumbase
N browser-use; N stagehand; N lightpanda; N scrapling
# Код: импорты (находит потребителей + бенчмарки), CI/докер
C "import lib"         'import undetected_chromedriver language:python'
C "smithery mcp"       'playwright filename:smithery.yaml'
C "dockerfile"         'playwright headless filename:Dockerfile'
C "readable a11y"      'page.accessibility.snapshot'
# --- Разведка (через raw: логируется и обрабатывает ошибки так же) ---
R "owner eco" 'user:ultrafunkamsterdam'   # --owner БЕЗ свободной фразы, иначе пусто
raw "users"   "users"   "browser automation stealth" \
  "gh api -X GET search/users -f q='browser automation stealth' -f per_page=5 -q '.items[]|\"USER\t\(.login)\t\(.type)\"'"
raw "commits" "commits" "headless browser stealth" \
  "gh search commits 'headless browser stealth' --limit 5 --json repository,commit -q '.[]|\"COMMIT\t\(.repository.fullName)\t\(.commit.message|split(\"\n\")[0]|.[0:48])\"'"
raw "prs"     "prs"     "add stealth bypass" \
  "gh search prs 'add stealth bypass' --limit 5 --json repository,title -q '.[]|\"PR\t\(.repository.nameWithOwner)\t\(.title|.[0:48])\"'"
raw "issues"  "issues"  "bypass cloudflare is:closed" \
  "gh api -X GET search/issues -f q='bypass cloudflare is:issue is:closed' -f per_page=5 -q '.items[]|\"ISSUE\t\(.title|.[0:55])\t\(.html_url)\"'"
raw "topics"  "meta-topics" "headless" \
  "gh api -X GET search/topics -f q='headless' -H 'Accept: application/vnd.github.mercy-preview+json' -q '.items[]|\"TOPIC\t#\(.name)\t\(.short_description // \"\"|.[0:42])\"'"
# Замер ниш
for q in "headless browser" "undetected browser" "headless browser llm" "cloudflare bypass"; do
  c=$(gh api graphql -f query="{ search(query:\"$q\", type:REPOSITORY){ repositoryCount } }" -q '.data.search.repositoryCount' 2>/dev/null)
  printf '%s\t%s\n' "$q" "${c:-?}" >> "$NICHE"; sleep $PAUSE
done

############ ИТОГ ПРОГОНА ############
TOTAL=$((OK+EMPTY+FAIL))
if [ "$FAIL" -eq 0 ]; then COMPLETE=true; STATUS_TXT=complete; else COMPLETE=false; STATUS_TXT=partial; fi
logj "run" "SUMMARY" "$TITLE" "$STATUS_TXT" "$TOTAL" "ok=$OK empty=$EMPTY fail=$FAIL rate=$RATE auth=$AUTH"

############ JSON — ЕДИНСТВЕННЫЙ артефакт (читает агент) ############
if [ "$HAVE_JQ" = 1 ]; then
  REPOS_J=$(grep -E '^[0-9]' "$REPOS" | sort -t$'\t' -k2,2 -u | sort -t$'\t' -k1,1 -nr \
            | jq -R -s 'split("\n")|map(select(length>0)|split("\t")|{stars:(.[0]|tonumber? // 0),repo:.[1],desc:.[2],found_by:.[3]})')
  CODE_J=$(sort -u "$CODE" | jq -R -s 'split("\n")|map(select(length>0)|split("\t")|{hit:.[0],found_by:.[1]})')
  RECON_J=$(grep -E '^(USER|COMMIT|PR|ISSUE|TOPIC)' "$REPOS" | sort -u \
            | jq -R -s 'split("\n")|map(select(length>0)|split("\t")|{type:.[0],label:.[1],detail:.[2]})')
  NICHE_J=$(jq -R -s 'split("\n")|map(select(length>0)|split("\t")|{query:.[0],count:.[1]})' "$NICHE")
  TECH_J=$(sort "$TECH" | jq -R -s 'split("\n")|map(select(length>0)|split("\t")|{technique:.[0],result:.[1]})')   # result: число попаданий или "ERR:<вид>"
  jq -n --arg t "$TITLE" --arg run "$RUN" --argjson complete "$COMPLETE" \
        --argjson ok "$OK" --argjson empty "$EMPTY" --argjson fail "$FAIL" --argjson rate "$RATE" --argjson auth "$AUTH" \
        --arg log "$LOG" --argjson r "$REPOS_J" --argjson c "$CODE_J" --argjson rc "$RECON_J" --argjson ni "$NICHE_J" --argjson te "$TECH_J" \
        '{title:$t, run:{id:$run, complete:$complete, ok:$ok, empty:$empty, fail:$fail, rate_limited:$rate, auth_fail:$auth, log:$log},
          repos:$r, code:$c, recon:$rc, niches:$ni, techniques:$te}' > "$WORK/h_results.json" 2>/dev/null
else
  echo "{\"note\":\"jq не найден — поставь 'brew install jq' и перезапусти. Сырые данные лежат в $WORK/h_*.tsv\"}" > "$WORK/h_results.json"
fi

############ ФИНАЛ для агента ############
echo "  ----------------------------"
echo "DONE: $STATUS_TXT  (всего $TOTAL: ok=$OK empty=$EMPTY fail=$FAIL rate_limit=$RATE auth=$AUTH)"
echo "  читай: $WORK/h_results.json   (run.complete=$COMPLETE)"
echo "  лог:   $LOG"
[ "$RATE" -gt 0 ] && echo "  ВНИМАНИЕ: $RATE падений по rate-limit — результат НЕПОЛНЫЙ, подожди ~минуту и перезапусти."
[ "$AUTH" -gt 0 ] && echo "  ВНИМАНИЕ: ошибки авторизации — выполни 'gh auth login' и перезапусти."
exit 0   # скрипт отработал; полнота результата — в run.complete, НЕ в exit-коде
