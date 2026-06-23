# Поиск кода и реализаций — «как люди пишут такую функцию/тул»

Этот файл для отдельного кейса: нужно не найти проект, а **увидеть, как люди
реализуют конкретную вещь** (распарсить вебхук, ретрай при rate-limit, собрать
MCP-тул, обойти пагинацию). `gh search code` ищет по ВСЕМУ публичному коду — это
живая база примеров.

Читай этот файл, когда задача именно про реализацию в коде, а не про выбор
проекта (для проектов — основной SKILL.md).

## Главное правило кода: ищи по точному коду, не по описанию

Бери идентификатор, сигнатуру, имя метода, цепочку вызовов — то, что **буквально
стоит в файле**. Описание словами («как обработать вебхук») даёт пусто или доки.

```bash
# По сигнатуре функции (как объявляют + рядом видно тело)
gh search code 'def send_with_retry language:python' --limit 8 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# По характерному вызову API (как используют конкретный метод)
gh search code 'client.get_dialogs limit language:python' --limit 8 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# По двум вызовам рядом (паттерн целиком: декоратор тула + логика)
gh search code 'mcp.tool get_dialogs' --limit 8 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# Сузить языком и типом файла
gh search code 'FloodWaitError sleep language:python' --limit 8 --json repository,path -q '.[]|"\(.repository.nameWithOwner) :: \(.path)"'

# Со сниппетами прямо в выдаче (куски строк вокруг совпадения, без чтения файла)
gh search code 'exponential backoff retry' --json repository,path,textMatches \
  -q '.[]|"\(.repository.nameWithOwner) :: \(.path)\n   \(.textMatches[]?.fragment|gsub("\n";" ")|.[0:120])"' --limit 6

# Прочитать найденный файл ЦЕЛИКОМ, чтобы увидеть всю реализацию
gh api repos/OWNER/REPO/contents/PATH -H "Accept: application/vnd.github.raw"
```

## Правила

- **2-3 точных токена кода**, не фразы. `def parse_webhook`, `connect_over_cdp`,
  `@mcp.tool`, `page.screenshot` — да. «как обработать вебхук» — нет.
- **Прогоняй варианты написания**: называют по-разному (`send_message` /
  `sendMessage` / `send_text`) — пробуй 2-3 имени.
- **`textMatches`** даёт сниппет прямо в выдаче — отсей нерелевантное, не открывая
  файлы. Полный файл читай только у 1-2 лучших.
- **Поиск по импорту** — мощный смежный приём: `gh search code 'import LIB'`
  находит, кто тянет библиотеку (видно, как применяют), а проекты-бенчмарки так
  всплывают даром (они импортируют всех конкурентов сразу).

## Не работает (не трать попытки)

- `in:path`, `symbol:` в `gh search code` → не поддерживаются, пусто.
- Спецсимволы (`=True`, `()`) → ломают запрос. Бери голый идентификатор.
- Длинные фразы → скатываются в `.md`/доки вместо кода.
