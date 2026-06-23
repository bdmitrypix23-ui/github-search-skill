---
name: github-search
description: Максимально полный поиск по GitHub — найти готовые проекты, библиотеки, инструменты, MCP-серверы и подсмотреть, как люди реализуют функцию/тул в коде. Используй ВСЕГДА, когда пользователь пишет в таком духе (даже если слова «гитхаб/гит» нет): «найди на гите мсп такие?», «поищи на гите», «на гитхаб что есть похожего?», «как люди пишут такую функцию/тул», «может это уже сделали другие люди?», «есть готовое под X?», «чем/на чём сделать Y?», «альтернативы Z», «найди скил про V», «поищи скил на W», «есть готовый скил под Q?». Даёт широкую карту темы со скрытыми алмазами, а не первую ссылку. НЕ для: поиска по ЛОКАЛЬНОМУ репозиторию (это git log / grep / ripgrep); clone/install конкретного уже известного репо.
---

# Поиск по GitHub: максимальный охват + скрытые алмазы

## Главные принципы

- **Тема ≠ фраза.** Длинная фраза («pdf to markdown preserve tables») почти
  всегда даёт пусто/мусор. Тему раскрывают `--topic`, отдельные ключевые слова,
  имена тяжеловесов, поиск по импортам.
- **Один угол тему не раскрывает — комбинируй веер.** Обычная тема → 6-10 углов
  вручную (раздел «Веер углов»); большая/важная → скрипт `assets/gh_hunt.sh`
  (детали в «Технических заметках»).
- **Три движка дают РАЗНОЕ** — `gh search`, `gh api search/*` (REST),
  `gh api graphql`. Используй несколько, не один.
- **Показывай ВСЕ релевантные, а не топ-3.** Скрытые алмазы (мало звёзд, но
  свежие/функциональнее лидера) — часто и есть лучший ответ. Не отбраковывай по
  одним звёздам (пример: `whatsapp-mcp-extended` — 19⭐, но 26 тулзов против лидера
  на 5800⭐ — смотри свежесть и фичи).
- **Если показал не всё** — прямо пиши: *«есть ещё N штук, показать? среди них тоже
  могут быть стоящие»*. Пусть пользователь решает сам.
- **Сырое число ≠ релевантное.** `repositoryCount` (напр. 305) включает мусор
  (боты, форки, обёртки). Фильтруй до настоящих и показывай всех настоящих.
- **Читай README/бенчмарки лучших — не верь маркетингу.** Ищи цифры и сравнения.
- **Мало нашёл — копай ещё угол** (`in:name`, импорт, commits, smithery.yaml),
  прежде чем сказать «это всё».
- Если `gh` ругается на авторизацию → `gh auth status`.

## Рабочий процесс (делай по шагам)

1. **Разложи задачу** на 2-4 ключевых слова + 2-4 вероятных `topic` + 3-8 имён
   известных проектов в нише (из своих знаний).
2. **Прогон веера** (минимум 6 углов, см. ниже). Для большой темы — скрипт
   `assets/gh_hunt.sh`.
3. **Дедуп и ранжируй** по звёздам; выкинь форки-пустышки и оффтоп.
4. **Замерь нишу** (`repositoryCount`) — понять, океан это или узкая свежая тема
   (в узкой теме лидеры будут молодые, с малыми звёздами — это норма).
5. **Прочитай README/бенчмарки** топ-3 кандидатов (`gh api .../readme` +
   grep по таблицам).
6. **Отдай пользователю**: таблица со всеми релевантными по категориям + прямая
   рекомендация «что брать под его случай». Если что-то не показал — допиши
   «есть ещё N, показать?» (см. «Полнота выдачи»). Формат таблицы:

   ```markdown
   | ⭐ | Проект | Чем хорош / для чего |
   |---|---|---|
   | 5819 | lharries/whatsapp-mcp | Лидер, личный аккаунт (QR), Go+Python |
   | 65 | jlucaso1/whatsapp-mcp-ts | Один стек — чистый TypeScript (Baileys) |
   | 19 | FelixIsaac/whatsapp-mcp-extended | Мелкий, но 26 тулзов + активная поддержка |
   ```
   Группируй по смыслу (напр. «через личный аккаунт» / «через Cloud API»), если
   в нише есть развилка способа работы.

## Веер углов (комбинируй, не выбирай один)

```bash
# --- РЕПОЗИТОРИИ ---
# 1. По темам (ГЛАВНЫЙ способ найти проект под задачу — точнее фраз)
gh search repos --topic web-scraping --topic anti-bot --sort=stars --limit 15 \
  --json fullName,stargazersCount,description -q '.[]|"\(.stargazersCount)⭐ \(.fullName) — \(.description)"'

# 2. По именам тяжеловесов (знаешь нишу — проверь лидеров поимённо)
for n in trafilatura mdream webclaw; do gh search repos "$n" --sort=stars --limit 1 --json fullName,stargazersCount,description -q '.[]|"\(.stargazersCount)⭐ \(.fullName)"'; done

# 3. order=asc — СКРЫТЫЕ АЛМАЗЫ с нижнего края (sort-desc их хоронит!)
gh api -X GET search/repositories -f q='html to markdown llm stars:>50' -f sort=stars -f order=asc -f per_page=8 \
  -q '.items[]|"\(.stargazers_count)⭐ \(.full_name) — \(.description)"'

# 4. sort=forks — кем РЕАЛЬНО пользуются (форки честнее звёзд)
gh api -X GET search/repositories -f q='topic:markdown html' -f sort=forks -f per_page=6 -q '.items[]|"\(.stargazers_count)⭐ \(.full_name)"'

# 5. Зрелые проверенные (created:<2021) и свежая волна (created:>2025)
gh api -X GET search/repositories -f q='pdf table extraction created:<2021 stars:>1000' -f sort=stars -f per_page=6 -q '.items[]|"\(.stargazers_count)⭐ \(.full_name)"'

# 6. Экосистема автора/конторы (нашёл хороший проект → смотри ВСЮ контору)
gh search repos --owner datalab-to --sort=stars --limit 8 --json fullName,stargazersCount,description -q '.[]|"\(.stargazersCount)⭐ \(.fullName)"'

# 7. GraphQL — ДРУГОЙ движок, находит то, чего gh search не даёт (термины КОРОТКИЕ!)
gh api graphql -f query='{ search(query:"undetected browser stars:>300", type:REPOSITORY, first:8){ nodes{ ... on Repository{ nameWithOwner stargazerCount description } } } }' -q '.data.search.nodes[]|"\(.stargazerCount)⭐ \(.nameWithOwner)"'

# --- КОД (как люди делают / кто что использует) ---
# 8. По ИМПОРТУ библиотеки — найти потребителей И БЕНЧМАРКИ (они тянут всех конкурентов!)
gh search code 'import trafilatura language:python' --limit 6 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# 9. По manifest-файлам MCP-серверов
gh search code 'gemini filename:smithery.yaml' --limit 6 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# 10. По тому, КАК инструмент ставят (CI / докер)
gh search code 'playwright headless filename:Dockerfile' --limit 6 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# --- РАЗВЕДКА ---
# 11. commits — найти НОВОРОЖДЁННЫЙ проект (ещё без звёзд) по "Initial commit"
gh search commits 'gemini web mcp' --limit 5 --json repository,commit -q '.[]|"\(.repository.fullName) — \(.commit.message|split("\n")[0])"'

# 12. PRs — увидеть, КАК прикрутили фичу (готовый рецепт)
gh search prs 'add table extraction support' --limit 5 --json repository,title -q '.[]|"\(.repository.nameWithOwner): \(.title)"'

# 13. Решённые issue — закрытый вопрос «как обойти X» = готовое решение в комментах
gh api -X GET search/issues -f q='bypass cloudflare playwright is:issue is:closed' -f per_page=5 -q '.items[]|"\(.title) — \(.html_url)"'

# 14. Эксперты/конторы темы → потом смотри их репозитории
gh api -X GET search/users -f q='browser automation stealth' -f per_page=5 -q '.items[]|"\(.login) (\(.type))"'

# 15. search/topics — какие ТЕГИ вообще существуют (мета-поиск, чтобы потом точно фильтровать)
gh api -X GET search/topics -f q='markdown' -H "Accept: application/vnd.github.mercy-preview+json" -q '.items[]|"#\(.name) — \(.short_description)"'

# --- ОЦЕНКА И ЧТЕНИЕ ---
# 16. repositoryCount — размер ниши (океан или узкая тема?)
gh api graphql -f query='{ search(query:"headless browser llm", type:REPOSITORY){ repositoryCount } }' -q '.data.search.repositoryCount'

# 17. Прочитать README/бенчмарк кандидата (цифры, а не маркетинг)
gh api repos/OWNER/REPO/readme -H "Accept: application/vnd.github.raw" | grep -iE 'f1|score|fast|benchmark|\|' | head -20
```

## Поиск кода и реализаций («как люди пишут такую функцию/тул»)

Отдельный кейс — не найти проект, а **подсмотреть реализацию** конкретной вещи
(ретрай при rate-limit, разбор вебхука, сборка MCP-тула). Когда задача про это —
**читай `references/code-search.md`**: там приёмы поиска по коду (по сигнатуре,
вызову, импорту, сниппеты `textMatches`) и свои грабли.

## Поиск готовых СКИЛОВ (не проектов, а Claude-скилов под задачу)

Ищешь не проект, а готовый скил — есть живые способы без ручного чёса. В мире
~160k скилов, так что **сперва проверь реестр**, прежде чем счесть тему «пустой».
- **GitHub Code Search** (живой, по всему гиту): `gh api search/code -f q='ТЕМА filename:SKILL.md' -f per_page=10 -q '.items[]|"\(.repository.nameWithOwner) :: \(.path)"'`. Многословные капризны (см. «Тупики») — бери 1-2 точных слова.
- **ClawHub REST API** (живой, со звёздами/скачиваниями, 36k): `curl -s 'https://clawhub.atomicbot.ai/api/skills?search=ТЕМА&limit=10' | jq '.items[]|{slug,summary,stars:.stats.stars,downloads:.stats.downloads}'`. Параметры — в OpenAPI: `clawhub.atomicbot.ai/docs-json`.
- **Реестр `majiayu000/claude-skill-registry`** (~160k, индекс с метаданными): для массового/оффлайн скачай шарды `registry-shards/00..ff.json` из `claude-skill-registry-core` и грепай `jq`. Плюс `sk` CLI и веб-поиск.

## Полезные фильтры (квалификаторы в строке q)

`stars:>N` · `forks:>N` · `pushed:>2025-01-01` (активность) · `created:<2021`
(зрелость) / `created:>2025` (свежак) · `language:rust` (скорость) ·
`license:mit` · `archived:false` · `topics:>=4` (документированные) ·
`stars:500..5000` (диапазон) · `size:<2000` (компактные) ·
`good-first-issues:>0` (живые) · `in:name` / `in:description` / `in:topics`.

Через флаги `gh search repos`: `--match name,description`, `--language`,
`--stars`, `--topic` (несколько раз), `--sort {stars|forks|updated|help-wanted-issues}`,
`--order {asc|desc}`.

## Тупики и ошибки (проверено — не трать на это попытки)

| Не работает | Деталь |
|---|---|
| Длинная фраза (4+ слов) везде | `gh search` И GraphQL → пусто. Дроби на термины. |
| `--match readme` + фраза | Сваливается в **awesome-листы**, не в тулзы. |
| `OR` в `gh search repos` | Пусто. **НО в `gh api search/repositories` OR работает!** |
| `in:path`, `symbol:` в `gh search code` | Не поддерживаются → пусто. |
| Спецсимволы в code-запросе (`full_page=True`) | Ломают запрос → пусто. Бери голый идентификатор. |
| `gh search code` многословный | Скатывается в `.md`/доки. По коду — только точные идентификаторы (`import X`, имя функции). |
| `--repo owner/name` на старом имени | Падает, если проект **переименовали** (ищи текущее имя). |
| `sort=updated` без `stars:>N` | Мусорные форки с 0⭐. Всегда ставь порог. |
| Имена секретов/кук (`__Secure-1PSID`) | GitHub их **не индексирует** в code search. |
| `stars:>100000` на узкой теме | Пусто. Порог под размер ниши (см. repositoryCount). |
| Эмодзи / кириллица в запросе | Мусор и i18n-файлы. Запросы — по-английски. |
| Один общий токен (`parse`, `markdown`) | Максимальный шум. |
| `--owner` + свободная фраза | Часто пусто. `--owner` бери без фразы или с `--match`. |

## Технические заметки

- **Рейт-лимит — важно:** Search API = 30 запросов/мин. Ручной веер подряд ловит
  `403 rate limit` уже на ~10-м поиске, а `sleep` в харнесе заблокирован (паузу
  руками не вставить). Поэтому **больше ~15 поисков подряд руками не гони** —
  переходи на `gh_hunt.sh` (он сам паузит `sleep 2.2`). Если ручной веер оборвался
  на 403 — это **НЕ «нашёл всё»**: добери скриптом, не отдавай обрыв как полный результат.
- **JSON-поля разные:** repos → `fullName`/`stargazersCount`; REST → `full_name`/
  `stargazers_count`; commits → дата в `commit.committer.date`. Всегда `--json`/`-q`.
- **macOS grep:** BSD grep, **нет `-P`**. Используй `grep -E`.
- **Большой заход:** скрипт `assets/gh_hunt.sh` — правь массивы под тему
  (`GH_HUNT_TITLE='...' bash gh_hunt.sh`), он сам паузит и дедуплицирует. Читай
  **`h_results.json`** — единственный артефакт (секции `repos` / `code` / `recon` /
  `niches` / `techniques` / `run`), фильтруй через `jq`. Проверь **`run.complete`**:
  `false` = были сбои (`run.fail`/`rate_limited`/`auth_fail`), часть запросов не
  отработала → улов может быть неполным, при rate-limit перезапусти позже. Путь
  печатается в начале — бери по нему (по `ls -t` в temp можно схватить чужой прогон).
  Лог каждого вызова — JSONL в `~/.claude/logs/github-search/` (хранится 7 дней /
  до 1 ГБ). Гоняй в фоне: **~2-4 мин, просто ЖДИ уведомления, не поллингуй**.

## Развивай скил сам

Имеешь право править этот файл по ходу дела, кратко и без воды:
- Нашёл новый рабочий приём и **повторил его 2+ раза** с результатом → впиши в
  нужный блок (веер / фильтры / `references/code-search.md`).
- Приём **не сработал 2+ раза подряд** → перенеси в «Тупики» или удали.
- Что-то в GitHub изменилось и старый рецепт сломался → поправь или убери.
