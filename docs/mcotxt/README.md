# MCOtxt для браузера: контракт и проверка совместимости

Добавлены автономный JS-кодек и демонстрация. Предварительные Dart-тесты
и 36 JS-проверок подтверждены владельцем; браузер и интеграция сайта ещё ожидают приёмки.
Формат приложения и модели поколения 0 не изменены.

## Размещение и подключение

Классический ES6-скрипт [assets/mcotxt.js](assets/mcotxt.js) создаёт
`window.MCOtxt`. Демонстрация — [index.html](index.html). Без modules, сборщика, CDN,
загрузки моделей по сети и зависимостей от Flutter.

Интерфейс демонстрации — на английском, документация и комментарии к коду — на русском.

Спецификация формата: [MCOtxt v1](../MCOTXT_V1_PROTOCOL_RU.md).
Основные источники реализации: `lib/MCOtxt/`,
`lib/helpers/mcotxt_app_codec.dart`, `lib/helpers/channel_app_data_helper.dart`.

Откройте `index.html` обычным браузером прямо с диска. Для встраивания
достаточно одного `mcotxt.js`; `demo.js` и `demo.css` нужны только странице.

```html
<script src="assets/mcotxt.js"></script>
<script>
  const encoded = MCOtxt.encode('Привет! Связь через ретранслятор.', {
    languages: ['ru', 'en'],
    senderName: '',
    base91: false
  });
  if (encoded.ok) {
    console.log(encoded.data, encoded.encodedBytes, encoded.textCompressionPercent);
    console.log(MCOtxt.decode(encoded));
  } else {
    console.error(encoded.error.code, encoded.error.message);
  }
</script>
```

## API

`MCOtxt.encode(text, options)` возвращает объект. Опции:

- `languages`: кандидаты для выбора основной пары; по умолчанию `['ru', 'en']`.
  Переключения на остальные встроенные языки разрешены. Декодер всегда знает
  все семь таблиц поколения 0, независимо от списка кандидатов кодирования.
- `languagePair`: необязательная явно закреплённая пара, например `['ru', 'en']`
  либо `['ru', null]`. Имеет приоритет над `languages`; нужна для точного
  воспроизведения поведения Dart с заданной парой. Без неё перебираются
  пары и одиночные языки из `languages`, включая оба порядка пары.
- `senderName`: имя отправителя; отсутствие или `''` опускает поле отправителя.
- `replyAuthorName` и `replyTimestamp`: задаются вместе; timestamp — целое
  число секунд Unix, от 0 до `0xffffffff`.
- `timestamp`: собственный timestamp сообщения в том же диапазоне. Если
  отсутствует, контейнер наследует время внешнего пакета (флаг `0x04`).
- `base91`: по умолчанию `false`; при `true` результат — ASCII-строка Base91.
- `modelGeneration`: поддерживается только `0` (оно же умолчание).

Результат содержит как минимум:

- `data`: `Uint8Array` либо Base91-строка **тела прикладного контейнера**.
  Внешний envelope и префикс `mct:` не добавляются.
- `type`: `binary` или `base91`; `format`: `body`.
- `originalText` и `normalizedText`: исходная и нормализованная строки.
- `decodedText`: результат декодирования созданного потока. Переносы строк
  и ограниченная композиция Unicode следуют Dart; UTF-8-декодер, как в Dart,
  пропускает начальный BOM конкретного UTF-8 поля или RAW/UTF8_RUN.
- `originalBytes`: длина исходного текста в UTF-8.
- `encodedBytes`: длина именно возвращённого `data` в байтах; для Base91
  считается ASCII-строка, а не размер исходного бинарного тела.
- `binaryBytes`: размер тела контейнера до преобразования в Base91.
- `compressionPercent`: `100 * (1 - encodedBytes / originalBytes)`.
  Отрицательное значение означает увеличение, для пустого текста — `null`.
- `textEncodedBytes` и `textCompressionPercent`: отдельная оценка только
  MCOtxt-frame текста, включая varuint длины в битах, без полей контейнера
  и без Base91. Для пустого текста процент также `null`.
- `languages`: языки, действительно использованные кодером; отдельно
  `languageA` / `languageB` описывают выбранную основную пару текста.
  `languages` учитывает и кодированные имена, `textLanguages` — только текст.
  В RAW_UTF8 таблицы не используются, поэтому соответствующий список пуст.
- `metadata`: timestamp и его источник, отправитель и пара reply, если есть.

Таким образом, `senderName: ''` позволяет сравнивать сжатие без имени.
Для измерения только текста нужно смотреть `textCompressionPercent`:
даже при отсутствии имени тело контейнера сохраняет обязательные байты формата.

`MCOtxt.decode({data, type, format, inheritedTimestamp})` принимает тело,
frame, открытый бинарный envelope приложения либо строку `mct:`.
Возвращает `{ok: true, text, languages, metadata, envelope, ...}` с текстом,
языками и метаданными, включая поля envelope,
когда они присутствуют. Для неоднозначных бинарных данных нужно явно задать
`format`; ошибка разбора возвращается как `{ok: false, error: {code, message}}`.
Такая же форма ошибки используется в `encode`, `encodeFrame`, `decodeFrame`.
Ошибки программирования не превращаются в успешный результат.

| `format` | Содержимое `data` |
|---|---|
| `body` | Тело контейнера: flags, метаданные, frame текста |
| `frame` | Только varuint длины в битах и поток MCOtxt |
| `envelope` | Внешнее имя, байт `0x31`, body |
| `payload` | Байт `0x31`, body |
| `mct` | Строка `mct:` + Base91 от payload |
| `auto` или не задан | Поиск body/envelope/payload; `mct:` определяется по префиксу |

Для строк без `mct:` подразумевается Base91; явно можно передать `type: 'base91'`.
Бинарный вход: `Uint8Array`, `ArrayBuffer`, view его байтов или массив 0–255.
Hex сначала преобразуется `fromHex`. Формат `frame` нужно задавать явно:
автоматический поиск не пытается угадать frame по произвольным байтам.

`metadata.timestampSource` равен `embedded` или `inherited`. Для inherited без
`inheritedTimestamp` возвращается `timestamp: null`; Dart в этом случае
использует `0`. Если передать время внешнего пакета, возвращается именно оно,
включая допустимый `0`. Для binary/envelope обычно нужно явно указать собственный
`timestamp` при encode; упаковка не подставляет текущее время автоматически.
`metadata.senderName` берётся только из body; внешнее имя доступно отдельно
как `envelope.outerSenderName`, без UI-подстановки `Unknown` для пустого имени.

Вспомогательные методы: `encodeFrame` / `decodeFrame` для текста
без прикладных метаданных, `getLanguages`, `normalizeText`, `toHex` / `fromHex`,
`toBase91` / `fromBase91`, `toTextTransport` и `wrapEnvelope`.
`getLanguages()` возвращает новые объекты `{code, id, name, modelGeneration, wireHash}`.
Точная длина в битах сохраняется во frame:
дополнение последнего байта нулями само по себе не обозначает конец потока.

`mct:` содержит Base91 от **`0x31 + body`**, а не от одного body.
Бинарный envelope содержит `varuint(nameLength) + outerName + 0x31 + body`;
штатное внешнее имя MCOtxt пустое. `dataType=0x0120` задаётся отдельно от
envelope. Сырые зашифрованные радиопакеты MeshCore здесь не декодируются.

```js
const encoded = MCOtxt.encode('Отвечаю!', {
  senderName: 'Иван', timestamp: 1700000000,
  replyAuthorName: 'Alice', replyTimestamp: 1699999999
});
if (encoded.ok) {
  const mct = MCOtxt.toTextTransport(encoded); // Строка, включает mct:
  const binary = MCOtxt.wrapEnvelope(encoded); // Объект с data: Uint8Array
  const restored = MCOtxt.decode({data: mct});
  const fromEnvelope = MCOtxt.decode(binary);
}
```

Преобразования и упаковка бросают `MCOtxt.MCOtxtError` с `code` и `message`
при неверном аргументе. Они не возвращают `{ok: false}`. `wrapEnvelope`
по умолчанию проверяет транспортный предел 165 байт; для работы с произвольным
контейнером вне радиотранспорта можно явно задать `{enforceRadioLimit: false}`.
Для поля результата Base91 используется `{base91: true}`, внешнее имя —
`{outerSenderName: 'Legacy'}` (по умолчанию пустое).

Реализация ограничивает каждую кодируемую строку 4096 Unicode code points,
декодируемый бинарный контейнер — 1 МиБ. Это защита синхронного браузерного
API от чрезмерных входов, не новые ограничения MCOtxt. Значения доступны в
`MCOtxt.limits`. Непарные UTF-16 surrogate при кодировании заменяются U+FFFD.

## Итоговая проверка JS и браузера

### Интеграция в сайт compress

Сайт расположен в `hdden.ru/public_html/compress/`; каталог в рабочей папке —
ссылка на `O:\OSPanel\home\hdden.ru`. Предварительный пакет
`tool/test_compress_site_baseline.cjs`: текущие UTF-8-метрики, сохранённые
примеры/словари/настройки, экранирование и порядок строк, лимит ввода,
подключение Mesh-compressor/LZW — подтверждён владельцем, как и отдельные
36 проверок JS-кодека. Пакеты не запускают браузер или сетевые скрипты.

MCOtxt подключён отдельной карточкой и переключателем, по умолчанию выключенным.
Выбор сохраняется в `compression-demo.settings.mcotxtEnabled`; примеры, словари
и остальные настройки сохраняются. Уже добавленные примеры пересчитываются
при включении/выключении метода. Binary и Base91 используют **один и тот же
frame**, с ru/en как кандидатами основной пары, без sender/timestamp/reply/envelope.
Hex — только отображение binary: размер считается по байтам, не по числу Hex-символов.
Проценты в общей таблице следуют её прежнему правилу: `(encoded - original) / original`,
отрицательное значение означает уменьшение. Это знак, обратный `compressionPercent`
в API кодека, где положительное значение означает экономию.

В сайт скопирован байт-в-байт `assets/mcotxt/mcotxt.js` из автономного порта;
специфика адаптации вынесена в `assets/mcotxt/mcotxt-comparison.js`.
Base91 получается из уже закодированных binary-байтов, без второго запуска
планировщика. Ошибки кодека/загрузки показываются нейтральной строкой с `—`
вместо размера/экономии, остальные методы продолжают работать.

Для итоговой проверки после интеграции владелец выполняет:

```powershell
Set-Location O:\_git\meshcore-open
node tool/test_compress_site_baseline.cjs
if ($LASTEXITCODE -ne 0) { throw 'Compress site baseline failed' }
node tool/test_compress_site_mcotxt.cjs
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt site integration failed' }
```

Новый пакет использует настоящий JS-кодек/адаптер и текущий app.js с минимальным
DOM: проверяет размеры, decode frame, вызов планировщика один раз, сохранение
toggle и прежних данных, общий rowspan, совместную работу методов, Unicode,
ошибки и точность копии исходного кодека. Исходные девять baseline-сценариев
не переписывались. Эти итоговые проверки ещё ожидают подтверждения владельца.

В браузере откройте сайт `/compress/`, включите MCOtxt и добавьте русские,
английские и смешанные сообщения. Убедитесь, что две строки появляются также
для старых примеров, а выбранное состояние сохраняется после обновления
страницы; проверьте совместно с Mesh-compressor, LZW и словарями.

Изменённые файлы для переноса на сайт:

- `public_html/compress/index.html`;
- `public_html/compress/app.js`;
- `public_html/compress/assets/mcotxt/mcotxt.js`;
- `public_html/compress/assets/mcotxt/mcotxt-comparison.js`.

Это статические файлы, отдельная сборка не нужна. Агент изменяет локальную
папку сайта; удалённая публикация и браузерная приёмка не выполнялись.
Целевые файлы находятся за symlink вне checkout приложения: сам symlink
в Git приложения не включает содержимое сайта.

### Проверки автономного демо

Node.js нужен только для тестов, не для использования кодека. Запускать из корня:

```powershell
Set-Location O:\_git\meshcore-open
node --check docs/mcotxt/assets/mcotxt.js
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt JS syntax failed' }
node --check docs/mcotxt/assets/demo.js
if ($LASTEXITCODE -ne 0) { throw 'Demo JS syntax failed' }
node tool/test_mcotxt_js.cjs
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt JS checks failed' }
dart --packages=.dart_tool/package_config.json tool/mcotxt_js_reference.dart --check
if ($LASTEXITCODE -ne 0) { throw 'Frozen Dart reference differs' }

$mcotxtTests = @(
  'test/MCOtxt/mcotxt_codec_test.dart'
  'test/MCOtxt/mcotxt_encode_determinism_test.dart'
  'test/MCOtxt/mcotxt_js_reference_baseline_test.dart'
)
flutter test @mcotxtTests --exclude-tags=slow --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt Dart checks failed' }
flutter analyze
```

JS-проверки сравнивают frame/body/Base91/mct/envelope с сохранёнными Dart
байтами, все литералы моделей — с Dart-таблицами. Дополнительно проверяются
выбор пары, размеры, отсутствие имени, reply, границы времени, повреждённые
входы и ограничения. Старый Dart-вариант с явным пустым sender читается,
но новый encode намеренно опускает пустое поле.

Для проверки страницы откройте `index.html`: Encode → «Send to decoder», затем
«Get mct:» → «Send to decoder» и envelope → «Send to decoder». Проверьте Unicode,
reply, пустое имя, Base91, frame и узкое окно. Размер самого текста смотрите
по отдельной строке «Text frame only». При выборе транспортного вывода
метрики остаются метриками исходного encode; размер оболочки указан рядом.
Никакой JS-проверкой через Node не подтверждается отрисовка страницы в браузере.

## Как был зафиксирован предварительный эталон

Владелец запускает из корня репозитория. Команда `--write` создаёт JSON
с буквальными эталонными байтами текущего Dart-кодека и отказывается
перезаписывать существующий файл. Повторная проверка выполняется `--check`.

```powershell
Set-Location O:\_git\meshcore-open
dart --packages=.dart_tool/package_config.json tool/mcotxt_js_reference.dart --write
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt reference export failed' }
dart --packages=.dart_tool/package_config.json tool/mcotxt_js_reference.dart --check
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt reference differs' }

$mcotxtBaselineTests = @(
  'test/MCOtxt/mcotxt_codec_test.dart'
  'test/MCOtxt/mcotxt_encode_determinism_test.dart'
  'test/MCOtxt/mcotxt_js_reference_baseline_test.dart'
)
flutter test @mcotxtBaselineTests --exclude-tags=slow --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'MCOtxt baseline failed' }
flutter analyze
```

Скрипт использует рабочий кодек и frame, но собирает прикладной контейнер
независимо: настоящий `MCOtxtAppCodec` транзитивно зависит от Flutter.
Новый Flutter-тест сравнивает этот контейнер, `mct:` и envelope с рабочими
реализациями. Один снимок строится на весь тестовый файл.
Корпус покрывает семь языков, другие языки при паре ru/en, регистр,
пунктуацию, UTF-8, ограниченную нормализацию Dart, переносы строк,
пустой текст, имена, reply, унаследованное время и границу uint32.

Полученный `test/MCOtxt/fixtures/js_reference_v1.json` нужно сохранить
в Git вместе с тестами **до** дальнейших изменений кодека. Его нельзя
обновлять автоматически вслед за изменением реализации: расхождение
сначала нужно объяснить. Не запускайте `--write` повторно вместо `--check`.
