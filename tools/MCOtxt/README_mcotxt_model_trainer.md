# MCOtxt v1 model trainer

`mcotxt_model_trainer.py` строит статическую TOP-4 модель одного языка MCOtxt v1 и экспортирует её в Dart и C/C++/nRF.

## Требования

- Python 3.10+
- внешние пакеты не нужны

## Что делает trainer

- читает UTF-8 corpus;
- нормализует CRLF/CR в LF и Unicode в NFC;
- приводит uppercase к lowercase **только через встроенный явный case-map языка** (`str.lower()`/`casefold()` не используются);
- считает частоты символов, START и `previous -> next` переходы;
- строит TOP-4 для START и для каждого символа;
- выбирает 31 primary symbol и до 32 extension symbols;
- по умолчанию primary выбирается по **literal-savings**: преимущество получают символы, которые часто не попадают в TOP-4 и поэтому реально экономят 2 бита при `PRIMARY_LITERAL=7` вместо `EXTENSION_LITERAL=9`;
- валидирует индексы и ограничения MCOtxt v1;
- считает validation TOP-4 hit rate и примерную стоимость MCOtxt v1;
- экспортирует Dart, C header и Markdown report.

Поддерживаются wire IDs:

- `0` EN
- `1` RU
- `2` FR
- `3` DE
- `4` IT
- `5` UK
- `6` BE

ASCII digits `0..9` входят в canonical alphabet каждого языка. SPACE также всегда входит в языковую модель.

## Рекомендуемый формат корпуса

Лучше всего JSONL, одна запись = одно реальное сообщение:

```jsonl
{"text":"Привет, ты где?"}
{"text":"Я уже на месте"}
{"text":"Первая строка\nВторая строка"}
```

Так сохраняются настоящие границы сообщений для `startTop4`, а внутри сообщения можно иметь LF.

TXT тоже поддерживается. В режиме `lines` каждая физическая строка считается отдельным сообщением.

Для обучения конкретной языковой модели желательно использовать преимущественно **монолингвальный corpus** этого языка. Смешанные RU+EN сообщения лучше держать в отдельном end-to-end benchmark: A/B TOGGLE относится уже к encoder, а не к per-language TOP-4 модели.

## Рекомендуемый объём

Для первого теста достаточно примерно 100–500 тыс. символов на язык. Для модели, которую планируется заморозить, разумная цель — 1–5 млн символов качественной разговорной переписки на язык.

## Запуск с отдельным validation corpus

```powershell
python .\mcotxt_model_trainer.py `
  --lang ru `
  --train .\corpora\ru\train `
  --validation .\corpora\ru\validation `
  --format auto `
  --out-dir .\generated\ru `
  --punctuation-dart O:\_git\meshcore-open\lib\mcotxt\models\punctuation.dart `
  --debug-json
```

`--train` и `--validation` принимают файл, директорию или glob. Директории обходятся рекурсивно.

## Автоматический train/validation split

Если `--validation` не указан, по умолчанию 20% сообщений детерминированно уходят в validation через SHA-256:

```powershell
python .\mcotxt_model_trainer.py `
  --lang ru `
  --train .\corpora\ru `
  --validation-ratio 0.20 `
  --out-dir .\generated\ru
```

Одинаковые сообщения при таком split получают одинаковое решение train/validation, что уменьшает leakage дубликатов.

## Выход

Для `--lang ru`:

```text
model_ru.dart
model_ru.h
model_ru_report.md
model_ru_debug.json   # только с --debug-json
```

### Dart

Dart-файл содержит:

- `primarySymbols` codepoints;
- `extensionSymbols` codepoints;
- `startTop4Indexes`;
- flattened `top4Indexes`;
- runtime-compatible `startTop4` codepoints;
- runtime-compatible nested `top4` codepoints;
- `uppercaseToLowercase` codepoint map;
- готовый `McotxtLanguageModel`.

По умолчанию генерируется:

```dart
import 'mcotxt_model.dart';
```

При необходимости поменяйте через:

```text
--dart-import "../mcotxt_model.dart"
```

или передайте пустую строку, чтобы import не генерировался.

### C/C++ / nRF

C header хранит TOP-4 именно как `uint8_t symbol indexes`:

```text
primary_symbols      uint16_t[]
extension_symbols    uint16_t[]
start_top4           uint8_t[4]
top4                 uint8_t[symbolCount * 4]
uppercase_map        uppercase uint16_t + lowercaseSymbolIndex uint8_t
```

Для GCC/Clang uppercase pair помечен `packed`, чтобы пара занимала 3 байта.

## Punctuation

В trainer зашита fallback-копия MCOtxt v1 punctuation page:

```text
0  SPACE
1  .
2  ,
3  !
4  ?
5  :
6  ;
7  -
8  —
9  _
10 '
11 "
12 «
13 »
14 “
15 ”
16 „
17 ‘
18 ’
19 (
20 )
21 [
22 ]
23 /
24 \
25 @
26 #
27 %
28 &
29 +
30 =
31 LF
```

Но **источником истины должен быть ваш `punctuation.dart`**. Поэтому перед freeze модели рекомендуется всегда запускать с:

```text
--punctuation-dart O:\_git\meshcore-open\lib\mcotxt\models\punctuation.dart
```

Trainer ищет в Dart-файле 32-элементный integer list и завершает работу ошибкой, если он не совпадает с ожидаемой таблицей. Если текущий `punctuation.dart` строит список не литералами, а выражениями/константами, best-effort parser потребуется немного адаптировать.

## Метрика bits/char

Report считает реальную для одной языковой модели стоимость:

- TOP-4: 3 bits;
- SHIFT: 5 bits;
- primary literal: 7 bits;
- punctuation: 8 bits;
- extension literal: 9 bits;
- header: 9 bits на сообщение.

В отчёте отдельно показываются:

- token-only bits/char;
- bits/char с 9-bit header на каждое validation message.

Это **per-language** оценка. Она пока не моделирует A/B `TOGGLE_LANGUAGE` и `SWITCH_OTHER_LANGUAGE` в смешанных сообщениях — такой benchmark лучше делать отдельным инструментом поверх уже готового Dart-кодека.

## Unsupported

Символ, который не входит в alphabet выбранного языка и не является punctuation v1:

- не участвует в модели;
- при validation считается skipped;
- выводится в отчёте по частоте;
- не сбрасывает previous-symbol context, как и в MCOtxt v1.

Это особенно полезно для поиска мусора в корпусе: emoji, символов другого языка, необычных Unicode punctuation и т. п.

## Перед freeze v1

Рекомендованный порядок:

1. собрать реальные/публичные conversational corpora для каждого языка;
2. держать train и validation раздельно;
3. обязательно сверить `punctuation.dart`;
4. сравнить `literal-savings` с `--primary-selection frequency`;
5. проверить TOP-4 hit rate и bits/char на validation;
6. отдельно прогнать реальные mixed-language сообщения через полный Dart encoder;
7. только после этого заморозить generated tables как MCOtxt v1.
