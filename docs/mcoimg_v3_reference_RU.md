# Справочник MCOimg v3

Этот документ описывает текущий формат MCOimg v3 в том виде, в котором он
реализован эталонным Dart-кодеком в `lib/helpers/mcoimg_v3_codec.dart`.

Старые форматы v1/v2 намеренно не специфицированы здесь. Они остаются в
проекте для совместимости со старыми сообщениями и клиентами, но новые
реализации должны ориентироваться на v3.

Браузерно-ориентированная JavaScript-реализация кодера/декодера v3 также
доступна в `docs/mcoimg-js/`. Она полезна как reference для портирования,
цель cross-runtime tests и пример web-интеграции.

## Эталонная реализация

Нормативные файлы реализации:

- `lib/helpers/mcoimg_v3_codec.dart`: кодер/декодер тела изображения v3.
- `lib/helpers/channel_app_data_helper.dart`: официальная app-payload оболочка.
- `lib/helpers/channel_binary_data_helper.dart`: MeshCore channel binary
  маршрутизация для v3.
- `lib/helpers/mcoimg_types.dart`: общая модель изображения, enum палитр и
  профилей, режимы сканирования и константы уровней сжатия.
- `lib/helpers/mcoimg_palette.dart` и
  `lib/helpers/mcoimg_dynamic_palettes.dart`: фиксированные и динамические
  таблицы палитр.

Если этот документ и Dart-код расходятся, до обновления документации
эталоном следует считать Dart-код.

### Нормативные данные палитр

Идентификаторов профилей и размеров профилей из этого документа недостаточно,
чтобы воспроизвести цвета при отрисовке. Совместимая реализация должна
скопировать точные данные палитр из:

- `lib/helpers/mcoimg_palette.dart` для девяти фиксированных профилей (`mono`,
  `master4` ... `master64`, а также `grayscale8`, `grayscale16`,
  `grayscale32`);
- `lib/helpers/mcoimg_dynamic_palettes.dart` для RGB-таблицы Dynamic Global 512
  и отображений `dynamicGlobal8Indices` ... `dynamicGlobal512Indices` из
  локальных id профиля в глобальные индексы.

Отображения для `dynamicGlobal8` ... `dynamicGlobal256` являются явными
lookup-таблицами, а не первыми `N` элементами Dynamic Global 512.
`dynamicGlobal512Indices` является тождественным отображением `[0, 1, ..., 511]`.
Портам следует поставлять эти массивы без изменений. Другие RGB-значения
изменят результат отрисовки и квантования; другое динамическое отображение
также привяжет сериализованные profile-local ссылки к неверным цветам.

### Фикстуры совместимости

Готовые cross-runtime фикстуры лежат в `docs/mcoimg-js/tests/`:

- `v3-js-decoder-fixtures.json` содержит канонические тела, app payload,
  текстовые формы и ожидаемые декодированные изображения для контейнеров,
  алгоритмов, scan-режимов и дескрипторов локальных палитр v3;
- `v3-js-encoder-fixtures.json` содержит payload, созданные JavaScript-кодером
  для проверки Dart-реализацией;
- `generate_v3_dart_fixtures.dart`, `verify-v3-dart-fixtures.js`,
  `generate-v3-js-encoder-fixtures.js`, `verify_v3_js_encoder_fixtures.dart`
  и соседние скрипты выполняют Dart/JavaScript cross-verification.

Из корня репозитория JavaScript-набор тестов v3 можно запустить так:

```text
node docs/mcoimg-js/tests/run-v3-tests.js
```

Полный обмен фикстурами v3 между Dart и JavaScript запускается так:

```text
node docs/mcoimg-js/tests/run-cross-runtime-tests.js --v3-only
```

Последней команде нужен `dart` в `PATH` либо `DART_BIN`, указывающий на Dart,
поставляемый вместе с Flutter.

Также есть готовый браузерный JavaScript-порт в `docs/mcoimg-js/`. Он полезен
как интеграционный пример и для тестирования на стороне браузера. Веб-версия
кодера/декодера MCOimg доступна по адресу:

https://hdden.ru/MCOimg/

## Идея формата

MCOimg v3 - компактный lossless-формат для небольших изображений с индексной
палитрой. Он не выполняет dithering, resize или quantize произвольных bitmap.
Входное изображение уже представлено как:

- `width`, `height`, каждое в диапазоне `1..256`;
- `PaletteProfile`;
- row-major массив `pixels` с `width * height` ссылками на палитру;
- опциональная ссылка `transparentColor` на цвет палитры.

Кодек пробует много lossless-представлений и выбирает самое короткое бинарное
тело. Выбранное тело может передаваться либо через:

- официальный MeshCore group-data маршрут, `data_type = 0x0120`;
- текстовый fallback, `im3:<base91>`.

Само тело v3 не содержит имя отправителя. Метаданные отправителя находятся в
channel app envelope.

## Транспорт и оболочка

### Официальный MeshCore channel binary route

MCOimg v3 использует официальный app data type MCO Advanced:

```text
data_type = 0x0120
```

Реестр пространств, грамматика конверта и действия клиента с незнакомым ему
подтипом заданы в [`CHANNEL_APP_DATA_RU.md`](CHANNEL_APP_DATA_RU.md); этот
раздел описывает только то, как MCOimg v3 заполняет конверт.

Channel app payload внутри этого data type:

```text
senderNameLen(varuint) | senderName(UTF-8) | subtypeVersion(u8) | packetNonce(u8) + compressed image body
```

Внешний `senderNameLen` varuint - это беззнаковый LEB128, независимый от
bit-packed integer primitives внутри тела MCOimg:

```text
repeat:
  byte bits 0..6: next 7 low bits of the value
  byte bit 7:     1 when another byte follows, otherwise 0
  value >>= 7
until value == 0
```

Ноль кодируется одним нулевым байтом. Эталонный decoder envelope принимает не
больше пяти байт.

`packetNonce` обновляется при каждой отправке, чтобы одинаковое изображение
при повторной отправке не создавало идентичный radio payload.

Полный channel app payload, включая envelope с именем отправителя, должен
помещаться в текущий лимит MeshCore channel-data 165 байт:

```text
bodyMax = 165 - varuintLength(senderNameUtf8.length)
              - senderNameUtf8.length
              - 1 // subtypeVersion
```

Лимит radio frame равен 176 байтам. Приложения должны пользоваться
protocol helper'ами, а не предполагать, что весь frame доступен под app data.

При прямой работе с companion firmware внешний command frame выглядит так:

```text
CMD_SEND_CHANNEL_DATA(u8 = 62)
channelIndex(u8)
pathLength(u8)
path[pathLength]?               // absent when pathLength == 0xFF
dataTypeLE(u16 = 0x0120)
channelAppPayload
```

`pathLength = 0xFF` означает неизвестный выходной маршрут и запрашивает flood
delivery. Когда передан конкретный маршрут, `pathLength` содержит его длину в
байтах, а байты маршрута идут сразу после него. Data type хранится в
little-endian, поэтому `0x0120` отправляется как `0x20, 0x01`. Клиентская
библиотека, уже предоставляющая channel `group_data` или channel-data API,
должна получать только `dataType = 0x0120` и channel app payload; обычно она
сама строит этот command frame.

Для MCOimg v3:

```text
subtype id = 0x01 (content-type - MCOimg)
version    = 0x03 (content format version)
packed subtypeVersion = 0x13 (packed two variables into one byte)
```

Упакованный байт использует:

```text
bits 7..4: subtype id
bits 3..0: content version
```

### App payload без отправителя

Для файлов, хранения галереи и текстового fallback канонический app payload без
отправителя:

```text
0x13 | v3 body
```

Не храните голые тела v3 в переносимых файлах, если окружающий контейнер уже не
идентифицирует их как MCOimg v3.

### Текстовый fallback

Текстовая форма:

```text
im3:<Base91(0x13 | v3 body)>
```

Точный Base91-алфавит, в порядке индексов:

```text
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~"
```

Кодирование использует стандартную очередь basE91:

```text
queue = 0
bitCount = 0

for each input byte:
  queue |= byte << bitCount
  bitCount += 8
  if bitCount > 13:
    value = queue & 8191
    if value > 88:
      queue >>= 13
      bitCount -= 13
    else:
      value = queue & 16383
      queue >>= 14
      bitCount -= 14
    emit alphabet[value % 91]
    emit alphabet[value / 91]

if bitCount > 0:
  emit alphabet[queue % 91]
  if bitCount > 7 or queue > 90:
    emit alphabet[queue / 91]
```

Для `value / 91` используется целочисленное деление. Decoder выполняет обратное
правило той же 13/14-битной очереди:

```text
value = -1
queue = 0
bitCount = 0

for each input character:
  decoded = alphabet index of character
  reject when character is absent
  if value < 0:
    value = decoded
  else:
    value += decoded * 91
    queue |= value << bitCount
    bitCount += ((value & 8191) > 88) ? 13 : 14
    while bitCount > 7:
      emit queue & 0xff
      queue >>= 8
      bitCount -= 8
    value = -1

if value >= 0:
  emit (queue | (value << bitCount)) & 0xff
```

Декодированный payload - это v3 `subtypeVersion | body`, а не тело v1/v2.

## Публичный Dart API

### Кодирование

```dart
final image = MCOImage(
  width: width,
  height: height,
  paletteProfile: PaletteProfile.dynamicGlobal128,
  pixels: pixels,
  transparentColor: null,
  encodingVersion: MCOImageEncodingVersion.v3,
);

final encoded = MCOImageV3Codec().encode(
  image,
  compressionLevel: mcoImageCompressionLevelHigh,
);

final body = encoded.body;
final appPayload = encoded.toAppPayloadWithoutSender(); // 0x13 | body
final text = MCOImageV3Codec.textFromBody(body);        // im3:...
```

`encode()` возвращает `EncodedMCOImageV3`:

- `body`: голое тело v3, включая packet nonce;
- `byteLength`: `body.length`;
- `subtypeId`: обычно `0x01`;
- `version`: обычно `0x03`;
- `subtypeVersion`: обычно `0x13`;
- `encodedCandidate`: диагностические метаданные выбранного candidate.

Опциональные настройки encoder:

```dart
MCOImageV3Codec().encode(
  image,
  backgroundColor: preferredBackground,
  backgroundCandidates: backgroundSlice,
  scanModes: scanSlice,
  includeNonScanCandidates: true,
  compressionLevel: mcoImageCompressionLevelHigh,
);
```

- `backgroundColor` задаёт предпочтительный background candidate.
- `backgroundCandidates` и `scanModes` ограничивают оценку candidates. В первую
  очередь они используются для worker slicing.
- `includeNonScanCandidates` управляет тем, будет ли slice также оценивать
  candidates, независимые от конкретного scan.
- Неизвестные integer-значения compression level нормализуются до High.

`debugEncode()` принимает те же аргументы и возвращает полную диагностику
candidates. `backgroundCandidatesFor()` отдаёт канонический список background
candidates, используемый для разделения работы.

### Декодирование

```dart
final image = MCOImageV3Codec().decodeBody(body);
final imageFromAppPayload =
    MCOImageV3Codec().decodeAppPayloadWithoutSender(appPayload);
final imageFromText = MCOImageV3Codec().decodeText(text);
```

### Инспекция

```dart
final info = MCOImageV3Codec.inspectBody(body);
final infoFromText = MCOImageV3Codec.inspectText(text);
final infoFromAppPayload =
    MCOImageV3Codec.inspectAppPayloadWithoutSender(appPayload);
```

`MCOImagePayloadInfo` сообщает:

- `version`: `3`;
- `algorithm`: человекочитаемая метка выбранного algorithm/container;
- `binaryLength`: длина тела в байтах.

Полезные payload helper'ы:

```dart
final isV3Text = MCOImageV3Codec.isTextPayload(text);
final appPayload =
    MCOImageV3Codec.appPayloadWithoutSenderFromText(text);
final body = MCOImageV3Codec.bodyFromText(text);
final textAgain =
    MCOImageV3Codec.textFromAppPayloadWithoutSender(appPayload);
final nonce = MCOImageV3Codec.nextPacketNonce();
```

### `packetNonce`

Каждое тело v3 начинается с одного байта packet nonce. Nonce намеренно
находится вне сжатого bitstream. Он нужен, чтобы ретранслируемое или повторно
отправленное изображение могло получить свежую бинарную идентичность пакета без
повторного расчёта compression candidate.

Без этого байта отправка только сжатого тела изображения каждый раз создавала
бы одинаковый payload для одной и той же картинки. Mesh-репитеры и duplicate
filters могут воспринять последующие отправки как уже слышанный пакет, потому
что packet hash идентичен; в итоге изображение может повториться один раз и
перестать выходить в эфир. Обновление nonce рандомизирует packet hash,
сохраняя само изображение неизменным.

Использование:

```dart
final refreshed = MCOImageV3Codec.refreshPacketNonce(body);
```

Это меняет `body[0]` и оставляет сжатые байты изображения неизменными.

## Уровни сжатия

Encoder принимает общие константы сжатия MCOimg:

```text
mcoImageCompressionLevelHigh    = 0
mcoImageCompressionLevelNormal  = 1
mcoImageCompressionLevelExtreme = 2
```

High используется по умолчанию. Уровень сжатия является только настройкой
encoder; он не хранится в payload.

Все уровни создают одну и ту же wire-грамматику v3. Уровень меняет только то,
какие encoder candidates оцениваются и сколько CPU encoder может потратить.

Количество candidates ниже описывает top-level candidate attempts до внутренних
вариантов descriptor/order локальных палитр, вариантов LZ parsing и
row/bitplane sub-choices. Пусть `B` - количество background candidates, а `V` -
количество region-layout variants, найденных для текущего изображения.

| Compression level | Доступные алгоритмы | Бюджет candidates | Активные ограничения | Multithreading |
| --- | --- | --- | --- | --- |
| Normal | Базовые block algorithms (`rawGlobal`, `rawLocal`, RLE, greedy `lzPixels`, `quadtree`, `bitplanes`, `adaptiveBitplanes`, row-delta, sparse и bicolor modes) плюс лёгкие regions. | Baseline block pass - около `17 + B*19` full-image attempts. Каждый cropped-bounds background может добавить до `80` attempts. Regions добавляют до `V*9` attempts на background в diagnostic/full-enumeration mode или один лучший region candidate на layout в normal selection mode. | `B <= 4`, scan modes `h`/`v`/`s`, до 12 regions, только non-hybrid region containers, маленький shared-palette beam только при `pixelCount <= 4096`. | Нет. |
| High | Normal плюс все scan modes, `directBitplanes`, `directRowDelta`, optimal LZ там, где позволяет бюджет, расширенные palette-order candidates и полные non-Extreme regions. | Baseline block pass - около `30 + B*25` full-image attempts. Каждый cropped-bounds background может добавить до `122` attempts. Regions добавляют до `V*13` attempts на background в diagnostic/full-enumeration mode или один лучший region candidate на layout в normal selection mode. | `B` включает preferred/white/до 8 частых цветов, плюс каждый использованный цвет для малых изображений при `pixelCount <= 4096` и `usedColorCount <= 64`; до 32 regions; High region beam width 3/depth 2. | Нет. |
| Extreme | High плюс bounded deep region search с reduced-cost evaluation и exact rerank. | Стартует с бюджета High. Для подходящих backgrounds может оценить до `1536` reduced region layouts, точно пересортировать до `32` из них и вернуть до `10` финальных deep-region layouts для полной оценки candidates. | Deep region search только для background rank `<= 5`, `pixelCount <= 1536`, `connectedComponentCount <= 20`; beam width 10/depth 8, evaluation budget 1536 layouts, final result limit 10. | Да, Flutter canvas делит Extreme candidate groups по worker pool. |

### Набор candidates Normal

Normal рассчитан на достаточно быструю работу, но всё равно пробует самые
сильные дешёвые candidates.

- Background candidates: не больше 4 candidates, начиная с явного background,
  transparent color или white fallback, затем самые частые цвета изображения.
- Top-level scan modes: `h`, `v`, `s`; `sv` пропускается.
- Bounds/full block algorithms:
  `rawGlobal`, `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`,
  `quadtree`, `bitplanes`, `adaptiveBitplanes`, `compactRowDelta`,
  `rowDelta`, `rowRepeat`, `compactSparse`, `varUintSparse`, `biColorMask`.
- Full-image background-independent algorithms:
  `rawGlobal`, `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`,
  `quadtree`, `rowRepeat`.
- Full-image background-sensitive algorithms:
  `bitplanes`, `adaptiveBitplanes`, `rowDelta`, `compactRowDelta`,
  `compactSparse`, `varUintSparse`, `biColorMask`.
- Region limit: до 12 regions.
- Region scan modes: `h`, `v`, `s`.
- Region block algorithms:
  `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`, `quadtree`,
  `bitplanes`, `adaptiveBitplanes`, `compactRowDelta`, `rowDelta`,
  `rowRepeat`, `compactSparse`, `varUintSparse`, `biColorMask`.
- Region container options: все non-hybrid комбинации common header,
  delta geometry и shared local palette, всего 8 комбинаций.
- Region geometry variants: connected components, empty-line split,
  sparse-line split и первый greedy rectangle variant.
- Normal shared-palette beam: когда изображение содержит не больше 4096
  пикселей, Normal может запустить маленький exact shared-palette
  compact-regions beam с width 3, depth 2 и до 8 neighbors на state.
- LZ pixel parsing использует greedy parser.
- Local palette search использует frequency, first-use и profile-order variants
  там, где это уместно. Transition, RGB и bitplane-optimized palette orders не
  включены.

### Набор candidates High

High используется по умолчанию и включает полную non-Extreme таблицу candidates.

- Background candidates: explicit/preferred background, white fallback, до 8
  самых частых цветов, а для малых изображений - каждый использованный цвет при
  `pixelCount <= 4096` и `usedColorCount <= 64`.
- Top-level scan modes: все четыре scan modes, `h`, `v`, `s`, `sv`.
- Bounds/full block algorithms: список Normal плюс `directBitplanes` и
  `directRowDelta`.
- Full-image background-independent algorithms: список Normal плюс
  `directBitplanes` и `directRowDelta`.
- Full-image background-sensitive algorithms: тот же список, что у Normal.
- Region limit: до 32 regions.
- Region scan modes: все четыре scan modes.
- Region block algorithms: список region Normal плюс `rawGlobal`,
  `directBitplanes` и `directRowDelta`.
- Shared-palette region algorithms: shared-список Normal с полным
  high-compression body evaluator.
- Region container options: 8 комбинаций Normal плюс 4 hybrid common-header
  комбинации, всего 12 комбинаций.
- Region geometry variants: connected components, empty-line split,
  sparse-line split, все greedy rectangle tie-break variants и payload-cost
  beam search при `pixelCount <= 4096`.
- High region beam: width 3, depth 2, до 8 neighbors на state, возвращает до 3
  улучшенных layouts.
- LZ pixel parsing использует optimal parser, когда block помещается в бюджет
  codec; более крупные blocks проходят через тот же safe encoding path.
- Local palette search также включает transition order, RGB order там, где это
  разрешено algorithm, и bitplane-optimized orders для adaptive bitplanes.

### Набор candidates Extreme

Extreme стартует с High и добавляет дорогой bounded region search. Он не
добавляет decoder-only grammar; он только тратит больше времени на поиск лучших
region layouts.

Глубокий Extreme region search выполняется только для background candidates с
rank `<= 5` и только когда:

```text
pixelCount <= 1536
connectedComponentCount <= 20
```

Когда он включён, используются:

```text
max search regions: 20
beam width:         10
beam depth:         8
neighbors/state:    32
evaluation budget:  1536 layouts
reduced rerank pool: 32 layouts
final result limit: 10 layouts
```

Сначала beam использует reduced region-cost evaluator, чтобы оставаться в
ограниченном бюджете, затем пересортировывает лучшие reduced-cost layouts
точным encoder v3 regions. Если изображение выходит за пределы Extreme bounds,
encoder возвращается к High region search для этого background candidate.

### Потоки и workers

Threading не является частью wire-формата MCOimg v3. Это деталь реализации
encoder и она не должна менять декодированное изображение или валидность
созданного payload. Candidate slices должны давать эквивалентное качество
сжатия, но byte-identical output не гарантируется: packet nonce генерируется
независимо, а equal-cost candidates могут быть увидены в другом порядке.

Dart API эталонного codec, `MCOImageV3Codec.encode()`, синхронный. Flutter
canvas integration запускает encode jobs через cancellable background compute,
чтобы UI оставался отзывчивым во время оценки candidates.

В текущей Flutter-реализации candidate-level worker slicing используется
только для уровня Extreme. Normal и High используют ту же v3 grammar и тот же
cacheable encode result path, но они не делятся между несколькими worker
isolates в Dart-приложении.

Для Extreme canvas делит независимые candidate groups и оценивает их через
worker pool:

- mobile worker limit: `min(6, Platform.numberOfProcessors)`;
- desktop worker limit: `floor(Platform.numberOfProcessors * 0.85)`, минимум
  один worker;
- фактическое количество workers также ограничено количеством созданных
  Extreme slices.

Browser или JavaScript ports могут использовать Web Workers для такого же
разделения candidates. Это опциональное поведение реализации: использование
workers должно оставаться decode-equivalent однопоточному encode.

## Порядок битов и integer primitives

Все bit fields записываются least-significant-bit first внутри byte stream.
Например, `writeBits(value, 3)` записывает bit 0, затем bit 1, затем bit 2 из
`value`.

Тело byte-aligned только в момент, когда `toBytes()` финализирует stream.
Финальные padding bits, если они есть, должны быть нулевыми. Decoders должны
отбраковывать ненулевые padding bits и trailing bytes.

### `bitVarUint`

`bitVarUint` - это little-endian 7-bit continuation integer, записываемый
целыми байтами через bit writer:

```text
byte bits 0..6: payload
byte bit 7:     continuation flag
```

Dart decoder принимает не больше пяти байт.

### `compactUint`

`compactUint` имеет короткие prefixes для малых значений. Prefix bits ниже
перечислены в порядке чтения/записи:

```text
0 + 2 bits              => 0..3
1,0 + 4 bits            => 4..19
1,1,0 + 8 bits          => 20..275
1,1,1 + bitVarUint      => 276+
```

### `rangeCompactUint(value, maxValue)`

Если `maxValue <= 7`, сохранить `value` в `bitLength(maxValue)` фиксированных
битах. Иначе сохранить `compactUint(value)`. Decoders должны отбраковывать
значения больше `maxValue`.

### `boundedCompactUint(value, maxValue)`

Если `maxValue <= 7`, сохранить `value` в `bitLength(maxValue)` фиксированных
битах. Иначе:

```text
0 + 2 bits                           => 0..3
1,0 + 4 bits                         => 4..19
1,1,0 + 8 bits                       => 20..275
1,1,1 + bitLength(maxValue-276) bits => 276..maxValue
```

Финальный escape недопустим, когда `maxValue < 276`.

## Макет тела v3

Голое тело v3:

```text
packetNonce(u8)
imageHeader(u8)
dimensions(bit-packed)
containerContext(u8)          // 3-bit container id + 5-bit context
transparentColor?             // present when imageHeader bit 7 is set
container body(bit-packed)
zero padding to next byte
```

### `packetNonce`

Первый байт не является частью сжатого состояния изображения. Decoders должны
игнорировать его при восстановлении картинки. Encoders могут регенерировать его
перед каждой отправкой.

Nonce решает практическую проблему mesh-сети: повторная отправка одного и того
же закодированного изображения иначе создала бы тот же byte-level payload.
Repeaters и packet deduplication logic могут принять его за уже виденный пакет,
а не за новую отправку. Меняя только этот один байт перед каждой send или
resend, клиент может сделать пакет отличающимся без recompress изображения и
без изменения отрисованных pixels.

### `imageHeader`

```text
bit 7:      transparent-color flag
bit 6:      implicit-white-background flag
bits 5..4:  top-level scan id
bits 3..0:  palette profile id
```

Scan ids соответствуют `ScanMode.index`:

| id | scan | обход из row-major pixels | длина строки для row codecs |
| -- | ---- | ------------------------- | --------------------------- |
| 0 | `h` | строки сверху вниз, каждая строка слева направо | image/block width |
| 1 | `v` | столбцы слева направо, каждый столбец сверху вниз | image/block height |
| 2 | `s` | horizontal snake: чётные строки слева направо, нечётные справа налево | image/block width |
| 3 | `sv` | vertical snake: чётные столбцы сверху вниз, нечётные снизу вверх | image/block height |

При определении чётности строки и столбцы считаются с нуля. Block algorithms
потребляют получившуюся одномерную последовательность. Decoders восстанавливают
тот же обход и раскладывают декодированные значения обратно в row-major order.

Profile ids соответствуют `PaletteProfile.index`:

| id | profile | size | bits |
| -- | ------- | ---- | ---- |
| 0 | `mono` | 2 | 1 |
| 1 | `master4` | 4 | 2 |
| 2 | `master8` | 8 | 3 |
| 3 | `master16` | 16 | 4 |
| 4 | `master32` | 32 | 5 |
| 5 | `master64` | 64 | 6 |
| 6 | `grayscale16` | 16 | 4 |
| 7 | `grayscale32` | 32 | 5 |
| 8 | `grayscale8` | 8 | 3 |
| 9 | `dynamicGlobal8` | 8 | 3 |
| 10 | `dynamicGlobal16` | 16 | 4 |
| 11 | `dynamicGlobal32` | 32 | 5 |
| 12 | `dynamicGlobal64` | 64 | 6 |
| 13 | `dynamicGlobal128` | 128 | 7 |
| 14 | `dynamicGlobal256` | 256 | 8 |
| 15 | `dynamicGlobal512` | 512 | 9 |

Для фиксированных profiles pixels в памяти и сериализованные color references
используют индексы этого фиксированного profile. Для dynamic profiles есть
важное различие:

- `MCOImage.pixels` и decoded output используют индексы палитры Dynamic Global
  512;
- каждая color reference, записанная в payload, использует profile-local color
  id;
- decoding отображает profile-local id обратно в индекс Dynamic Global 512.

Это отображение применяется к headers, backgrounds, transparency, local
palettes и direct algorithms. Dynamic input color, отсутствующий в выбранном
dynamic profile, недопустим.

### Размеры

Dimensions канонические. Decoders должны отбраковывать encoding размеров, если
тот же размер мог быть представлен более коротким mode.

Первые два бита выбирают:

| mode | meaning | fields |
| ---- | ------- | ------ |
| 0 | square up to 64 | `widthMinus1:6`; `height = width` |
| 1 | non-square up to 32x32 | `widthMinus1:5`, `heightMinus1:5` |
| 2 | non-small rectangle up to 64x64 | `widthMinus1:6`, `heightMinus1:6` |
| 3 | extended up to 256x256 | see below |

Extended mode:

```text
generalRectangle:1
if generalRectangle == 0:
  widthMinus1:8
  height = width
else:
  widthMinus1:8
  heightMinus1:8
```

Валидные dimensions: `1..256`.

### `containerContext`

`containerContext` - общий top-level container byte. Он выбирает body container
и даёт этому container маленькое 5-битное context value.

```text
bits 7..5: container id
bits 4..0: container-specific context
```

Container ids соответствуют `MCOImageV3Container.index`:

| id | container | context |
| -- | --------- | ------- |
| 0 | `block` | block algorithm id |
| 1 | `compactBlock` | block algorithm id |
| 2 | `boundsBlock` | block algorithm id |
| 3 | `compactBoundsBlock` | block algorithm id |
| 4 | `regions` | `regionCount - 1` |
| 5 | `compactRegionsStream` | `regionCount - 1` |
| 6 | `solidBackground` | low 5 bits of the solid color reference |
| 7 | `solidRects` | low 5 bits of `rectCount - 1` |

Для block-like containers context является `MCOImageV3BlockAlgorithm.index`.

Для region containers context хранит количество regions, поэтому counts 1..32
помещаются в context values 0..31.

Для `solidBackground` context хранит младшие 5 bits color reference. Если solid
color требует больше 5 bits и не является implicit white, оставшиеся high bits
записываются в body.

Для `solidRects` context хранит младшие 5 bits от `rectCount - 1`. Текущий
encoder ограничивает solid-rectangle candidates 64 rectangles, поэтому при
необходимости в body записывается один дополнительный high bit.

## Контейнеры

### Владение background и наследование

Background-bearing block algorithms: `compactSparse`, `varUintSparse` и
`biColorMask`. Их background reference принадлежит следующим уровням:

- в full-image `block` или `compactBlock` block body записывает собственный
  `backgroundRef`, если его не опустил implicit-white flag;
- `boundsBlock` и `compactBoundsBlock` записывают один container background
  перед geometry и передают его во вложенный block body, который не должен
  записывать второй background;
- `regions` и `compactRegionsStream` записывают один stream background и
  передают его в каждый region block;
- shared-palette sparse и bicolor region bodies наследуют тот же stream
  background;
- `solidBackground` хранит цвет в context и опциональном context tail;
  `solidRects` записывает один container background перед local palette.

Algorithms без background field ничего не записывают и не наследуют.
Implicit-white flag валиден только там, где выбранный container или block
algorithm имеет такую background role.

### `block`

`block` хранит full-image block со scan-dependent algorithm. Pixels
конвертируются в выбранный top-level scan order перед decoding/encoding block
body. После decoding результат конвертируется обратно в row-major order.

`block` не должен использоваться со scan-independent algorithms, которые могут
использовать `compactBlock`.

### `compactBlock`

`compactBlock` хранит full-image block с каноническим horizontal scan и без
зависимости от top-level scan. Сейчас он валиден только для algorithms, где
`_canUseCompactBlockHeader()` возвращает true:

- `rawGlobal`
- `rawLocal`
- `biColorMask`

Header scan должен быть `h`.

### `boundsBlock`

`boundsBlock` хранит background color плюс один rectangular block. Декодированное
изображение начинается как полностью заполненное background pixels; decoded
block перезаписывает сохранённые bounds.

Body:

```text
backgroundRef?        // absent when implicit-white-background flag is set
bounds geometry       // non-compact 8-bit axis fields
block body
```

Block scan равен top-level scan, если выбранный algorithm не является compact
header algorithm в `compactBoundsBlock`.

### `compactBoundsBlock`

`compactBoundsBlock` - версия `boundsBlock` с compact geometry. Geometry fields
используют минимум bits, необходимый для текущего размера изображения и
оставшегося extent.

Для compact-header algorithms top-level scan должен быть `h`, а block читается
как horizontal. Для остальных algorithms используется обычный top-level scan.

### `regions`

`regions` хранит несколько rectangular blocks поверх background. Geometry
использует non-compact 8-bit axis fields. Этот container существует для того же
логического layout, что и `compactRegionsStream`, но compact stream обычно
предпочтительнее.

У него нет stream flags, common header, delta geometry или shared palette:

```text
backgroundRef?                  // absent for implicit white
repeat regionCount times:
  x:8
  y:8
  widthMinus1:8
  heightMinus1:8
  algorithm:5
  scan:2?                       // omitted for compact-header algorithms
  block body
```

Поэтому каждый region имеет индивидуальный block header.

### `compactRegionsStream`

`compactRegionsStream` хранит несколько rectangular blocks поверх background с
опциональным stream-level compression:

```text
backgroundRef?                  // absent for implicit white
hasCommonBlockHeader:1
hasDeltaGeometry:1
hasSharedLocalPalette:1
common header?                  // if hasCommonBlockHeader
shared local palette?           // if hasSharedLocalPalette
region[regionCount]
```

Для каждого region:

```text
geometry                        // first full geometry, later delta if enabled
usesIndividualHeader:1?         // hybrid common header only
algorithm:5?                    // absent when the common header applies
scan:2?                         // absent for compact-header algorithms
block body
```

Region algorithm всегда хранится в 5 bits. Его scan хранится в 2 bits, если
только `_canUseCompactBlockHeader(algorithm)` не равен true (`rawGlobal`,
`rawLocal` или `biColorMask`); в таком случае подразумевается horizontal scan.

Когда `hasCommonBlockHeader` false, каждый region имеет собственный
`algorithm:5` и опциональный `scan:2`; бита `usesIndividualHeader` нет. При
strict common header common algorithm/scan записывается один раз, а regions не
несут header-selection bit.

Само поле common-header:

```text
commonAlgorithm:5
commonScan:2?                    // omitted for compact-header algorithms
```

Для strict header `commonAlgorithm` - настоящий algorithm id. Для hybrid header
`commonAlgorithm` - зарезервированный marker 31, после которого идут:

```text
realCommonAlgorithm:5
realCommonScan:2?                // omitted for compact-header algorithms
```

Когда `hasDeltaGeometry` true, region 0 использует full compact geometry, а
каждый следующий region хранит signed compact deltas от предыдущего region:

```text
dx, dy, dWidth, dHeight as signedCompactInt
```

`signedCompactInt` отображает signed values через zigzag:

```text
encoded = value < 0 ? (-value * 2) - 1 : value * 2
```

и хранит `encoded` как `compactUint`.

Когда `hasSharedLocalPalette` true, совместимые region block bodies используют
одну local palette, записанную перед списком regions.

Грамматика shared-palette block-body опускает собственную local palette каждого
block. Она валидна для:

```text
rawLocal, compactRle, varUintRle, compactSparse, varUintSparse,
lzPixels, quadtree, bitplanes, adaptiveBitplanes, compactRowDelta,
rowDelta, rowRepeat, biColorMask
```

Она не валидна для `rawGlobal`, `directBitplanes` или `directRowDelta`. Sparse
и bicolor bodies наследуют stream background. Для shared `biColorMask`
foreground является local palette index, а не profile color reference.

`hasCommonBlockHeader` может быть strict или hybrid. Common algorithm id 31 -
это 5-битный hybrid marker: за ним идут настоящий common `algorithm:5` и
опциональный `scan:2`. Каждый region затем имеет один bit
`usesIndividualHeader`:

```text
0 => use the common algorithm and scan
1 => read this region's algorithm:5 and optional scan:2
```

### `solidBackground`

`solidBackground` заполняет всё изображение одним цветом. Если implicit white
flag установлен, body bits для цвета не нужны. Иначе младшие 5 bits color
reference хранятся в container context, а оставшиеся high bits - после
опционального transparent color field.

### `solidRects`

`solidRects` хранит background color, одну local palette для цветов rectangles и
несколько solid rectangles. Он предназначен для простых icon-like изображений с
небольшим количеством заполненных rectangles.

Body:

```text
backgroundRef?                  // absent for implicit white
localPalette
high rect-count bit
rect[rectCount]
```

Для каждого rectangle:

```text
compact bounds geometry
local color index
```

Младшие 5 bits `rectCount - 1` находятся в container context. В body хранится
ещё один high bit, поэтому диапазон stored count равен 1..64.

## Геометрия regions и bounds

Non-compact geometry использует 8 bits для каждого field:

```text
x:8
y:8
widthMinus1:8
heightMinus1:8
```

Compact geometry использует:

```text
x:bitLength(imageWidth - 1)
y:bitLength(imageHeight - 1)
widthMinus1:bitLength(imageWidth - x - 1)
heightMinus1:bitLength(imageHeight - y - 1)
```

Здесь `bitLength(0) = 0`, поэтому field, единственное допустимое значение
которого равно нулю, не занимает bits. Декодированный rectangle должен
оставаться внутри изображения.

## Локальные палитры

Многие algorithms сначала хранят local palette, а затем кодируют local color
indexes.

`localBits = bitLength(localPalette.length - 1)`.

Для palette sizes до 64 flat prefix:

```text
0
lengthMinus1:globalBits(profile)
```

Для более крупных profiles flat lengths кодируются так:

```text
0 + 6 bits                    => lengths 1..64
10 + 6 bits                   => lengths 65..128
110 + 8 bits                  => lengths 129..384
1110 + 7 bits                 => lengths 385..512
```

Descriptor palettes используют:

```text
small profiles (<=64 colors): 1 + descriptor:2
large profiles:               1111 + descriptor:2
```

Descriptor ids:

| id | descriptor |
| -- | ---------- |
| 0 | bitmap |
| 1 | sorted delta |
| 2 | range runs |
| 3 | banked descriptor |

Encoder также имеет внутренний ordered-banked descriptor variant. В wire-формате
он выбирается через descriptor id 3, а затем первым битом внутри тела banked
descriptor.

Bitmap, sorted-delta, range-runs и bank-bitmap descriptors восстанавливают
цвета в возрастающем порядке profile-local references. Поэтому encoder может
использовать эти descriptors только когда его local palette уже строго
возрастает в этом порядке. Иначе local pixel indexes после decoding будут
ссылаться на другие цвета. Ordered-banked 8x64 variant сохраняет произвольный
порядок local-palette и является единственной descriptor form, которая может
представлять несортированную palette. Flat local-palette form тоже сохраняет
произвольный порядок.

Descriptor bodies:

- bitmap: один bit на каждый profile color, в profile order.
- sorted delta: local palette length, первый ref в `globalBits`, затем
  `compactUint(ref - previousRef - 1)` для каждого следующего ref.
- range runs: `rangeCompactUint(runCount - 1, paletteSize - 1) + 1`, затем
  `start:globalBits` и `compactUint(length - 1)` для каждого run.
- bank bitmaps: selector bit `0`, `bankMask:8`, затем для каждого выбранного
  64-color bank 64-bit bitmap.
- ordered banked 8x64: selector bit `1`, затем:

```text
localPaletteLength
multipleBanks:1

if multipleBanks == 0:
  bank:3
  repeat localPaletteLength times:
    offsetInBank:6
else:
  bankMask:8
  banks = ascending set-bit indexes from bankMask
  bankBits = bitLength(banks.length - 1)
  repeat localPaletteLength times:
    bankIndex:bankBits
    offsetInBank:6
```

`bankIndex` адресует компактный возрастающий список `banks`, а не исходный
номер bank 0..7. Decoder применяет эти дополнительные правила валидности:

- когда `multipleBanks == 0`, `localPaletteLength` не должен превышать 64, и
  все entries используют один явно заданный bank;
- когда `multipleBanks == 1`, `bankMask` должен выбрать минимум два banks;
- `localPaletteLength` не должен превышать `popcount(bankMask) * 64`;
- каждый декодированный `bankIndex` должен находиться внутри компактного списка
  selected-bank;
- каждый bank, выбранный `bankMask`, должен использоваться хотя бы одной
  palette entry.

Как и у любого local-palette descriptor, duplicate reconstructed color
references недопустимы.

Descriptor-specific `local palette length`, используемый sorted-delta и
ordered-banked bodies:

```text
if profileSize <= 64:
  lengthMinus1:globalBits(profile)
else:
  0  + value:6 => length = value + 1       // 1..64
  10 + value:6 => length = value + 65      // 65..128
  11 + value:bitLength(profileSize - 129)
                => length = value + 129    // 129..profileSize
```

Финальная ветка `11` недопустима для profiles размером не больше 128. Banked
descriptor и его ordered-banked variant валидны только для `dynamicGlobal512`;
его восемь banks содержат по 64 profile-local references.

Decoders должны отбраковывать duplicate local colors и references вне profile.

## Блочные алгоритмы

Block algorithm ids соответствуют `MCOImageV3BlockAlgorithm.index`:

| id | algorithm |
| -- | --------- |
| 0 | `rawGlobal` |
| 1 | `rawLocal` |
| 2 | `compactRle` |
| 3 | `compactSparse` |
| 4 | `biColorMask` |
| 5 | `rowRepeat` |
| 6 | `lzPixels` |
| 7 | `quadtree` |
| 8 | `bitplanes` |
| 9 | `adaptiveBitplanes` |
| 10 | `directBitplanes` |
| 11 | `compactRowDelta` |
| 12 | `directRowDelta` |
| 13 | `rowDelta` |
| 14 | `varUintRle` |
| 15 | `varUintSparse` |

### `rawGlobal`

Хранит каждый pixel как color reference, используя `globalBits(profile)`.

### `rawLocal`

Хранит local palette, затем каждый pixel как local palette index.

### `compactRle`

Хранит local palette. Затем повторяет записи, пока не будет заполнено
количество pixels в block:

```text
localColorIndex:localBits
runLengthMinus1:boundedCompactUint(remainingPixels - 1)
```

### `varUintRle`

Хранит local palette. Затем повторяет записи до заполнения:

```text
localColorIndex:localBits
runLength:bitVarUint
```

`runLength` должен быть положительным и не должен выходить за пределы block.

### `lzPixels`

Хранит local palette. Затем повторяет записи до заполнения:

```text
isMatch:1
if isMatch == 0:
  literalLengthMinus1:rangeCompactUint(remainingPixels - 1)
  localColorIndex[ literalLength ]:localBits
else:
  distanceMinus1:rangeCompactUint(decodedPixels - 1)
  lengthMinus3:rangeCompactUint(remainingPixels - 3)
```

Matches требуют минимум три pixels. Distance становится one-based после
прибавления единицы к encoded value.

### `quadtree`

Хранит local palette. Block декодируется как рекурсивное 2D tree только в
horizontal geometry. Non-horizontal scan недопустим.

Каждый node начинается с:

```text
isSolid:1
if isSolid:
  localColorIndex:localBits
else:
  children...
```

Non-solid `1x1` node недопустим. Порядок split детерминирован:

- если `width == 1`, split vertical в верхний и нижний children;
- иначе если `height == 1`, split horizontal в левый и правый children;
- иначе split на четыре children в порядке: top-left, top-right, bottom-left,
  bottom-right.

Размеры split используют integer halves:

```text
leftWidth = width ~/ 2
topHeight = height ~/ 2
```

Второй child по каждой оси получает оставшиеся pixels.

### `bitplanes`

Хранит local palette. Для каждого bit local color indexes, начиная с младшего:

```text
isRle:1
if isRle == 0:
  raw bit for every pixel
else:
  startingBit:1
  repeat until pixelCount is filled:
    runLengthMinus1:rangeCompactUint(remainingPixels - 1)
```

Каждая decoded run length равна `runLengthMinus1 + 1`. RLE run lengths
заполняют всё количество pixels и меняют bit value после каждого run.
Run-count field или terminator не хранятся.

### `adaptiveBitplanes`

Хранит local palette, если не используется direct algorithm. Для каждого
bitplane записывается один из этих prefixes. Prefix bits перечислены в порядке
чтения stream:

```text
0                       raw bits
1,0 + startingBit       legacy RLE, rangeCompactUint run lengths
1,1,0 + startingBit     short RLE
1,1,1,0,0               constant zero
1,1,1,1,0               constant one
1,1,1,0,1               sparse one positions
1,1,1,1,1               sparse zero positions
```

Short RLE run lengths используют:

```text
0                 => 1
1,0               => 2
1,1,0             => 3
1,1,1 + rangeCompactUint(length - 4, remaining - 4)
```

Sparse bitplane positions записываются функцией
`_writeSparseBitplanePositions`. Они кодируются так:

```text
countMinus1:rangeCompactUint(pixelCount - 1)
repeat count times:
  gapFromPreviousMinus1:rangeCompactUint(maxGap)
```

`previous` начинается с `-1`. Для position `i`, когда после неё ещё остаётся
`remainingPositions` unread:

```text
maxGap = pixelCount - previous - remainingPositions - 2
position = previous + gap + 1
```

### `directBitplanes`

Этот algorithm валиден только для grayscale и dynamic profiles. Он пропускает
local palette и запускает `adaptiveBitplanes` прямо по profile-local values, с:

```text
valueBits = globalBits(profile)
```

Для dynamic profiles body использует dynamic-profile color ids и отображает их
обратно через `MCOImageDynamicPalette.globalIndexForProfileColorId()`.

### `rowDelta`

Хранит local palette. Конвертирует block в выбранный scan order и делит его на
rows с длиной scan row из таблицы scan. `valueBits` - ширина local-palette index.

Body начинается с:

```text
useVirtualBaseRow:1
allowShiftPredictors:1
firstRow[valueBits]?      // rowLength values; absent for a virtual base row
row operations...
```

Когда `useVirtualBaseRow` true, row 0 кодируется относительно virtual row,
состоящей из нулей, и raw first row отсутствует. Иначе первая row хранится raw,
а operations начинаются с row 1.

Каждая следующая operation начинается с `op:2`:

| id | operation | following payload |
| -- | --------- | ----------------- |
| 0 | raw row | `rowLength` values in `valueBits` |
| 1 | repeat previous row | none; predictor is always `same` |
| 2 | indexed changes | optional predictor, change count and changed positions/values |
| 3 | extended | `extendedOp:2`, then operation-specific payload |

Для indexed changes:

```text
predictor?                         // only when allowShiftPredictors == 1
changeCount:bitLength(rowLength)
repeat changeCount times:
  x:bitLength(rowLength - 1)       // strictly increasing
  value:valueBits
```

`changeCount` может быть нулевым. Начните с predicted row и замените
перечисленные positions.

Extended operations:

| id | operation | following payload |
| -- | --------- | ----------------- |
| 0 | mask | optional predictor, `rowLength` mask bits, then one value per set bit |
| 1 | segments | optional predictor, segment geometry and values |
| 2 | same-scalar mask | optional predictor, `rowLength` mask bits, one shared value |
| 3 | repeat run | repeat count only; predictor is always `same` |

Mask должен содержать минимум один set bit. Segment payload:

```text
segmentCountMinus1:bitLength(rowLength - 1)
repeat segmentCount times:
  start:bitLength(rowLength - 1)
  lengthMinus1:bitLength(rowLength - 1)
  value[length]:valueBits
```

Segments должны быть non-empty, ordered, non-overlapping и находиться внутри row.

Repeat run представляет минимум две consecutive rows, каждая из которых равна
непосредственно предыдущей row:

```text
repeatCountMinus2:
  rangeCompactUint(remainingRowCount - 2)
```

Predictors:

| compact prefix | predictor |
| -------------- | --------- |
| `0` | same previous row |
| `10` | left-shifted previous row |
| `11` | right-shifted previous row |

Prefix bits показаны в порядке чтения/записи. Shift predictors wrap at the row
edge:

```text
same[x]  = previous[x]
left[x]  = previous[(x - 1) mod rowLength]
right[x] = previous[(x + 1) mod rowLength]
```

Predictor bits полностью отсутствуют, когда `allowShiftPredictors` false; тогда
подразумевается same-row predictor. Shifted predictor недопустим для row 0,
когда эта row использует virtual base.

### `compactRowDelta`

Хранит local palette и использует ту же scan-row construction и wraparound
predictors, что и `rowDelta`. Body начинается с:

```text
useVirtualBaseRow:1
firstRow[valueBits]?      // rowLength values; absent for a virtual base row
row operations...
```

Каждая operation начинается с `op:3`:

| id | operation | following payload |
| -- | --------- | ----------------- |
| 0 | repeat previous row | none; same predictor is implied |
| 1 | raw row | `rowLength` values in `valueBits` |
| 2 | indexed changes | predictor, optional residual flag, positions and values |
| 3 | same scalar | predictor, optional residual flag, positions and one shared value/delta |
| 4 | segments | predictor, optional residual flag, segment geometry and values |
| 5 | trimmed mask | predictor, optional residual flag, mask geometry and values |
| 6 | repeat run | `rangeCompactUint(remainingRowCount - 2) + 2` |
| 7 | predicted row, no changes | predictor only |

Для operations 2, 3, 4, 5 и 7 сначала читается compact predictor:

```text
0   => same
1,0 => left
1,1 => right
```

Для operations 2..5 direct grayscale bodies затем хранят `useResidual:1`;
local-palette и direct-dynamic bodies опускают этот bit и используют absolute
values.

Indexed и same-scalar positions кодируются gap-coded:

```text
changeCountMinus1:rangeCompactUint(rowLength - 1)
previousX = -1
for each changed position i:
  remaining = changeCount - i - 1
  maxGap = rowLength - previousX - remaining - 2
  gap:rangeCompactUint(maxGap)
  x = previousX + 1 + gap
  previousX = x
```

Indexed mode затем хранит одно changed value для каждой position. Same-scalar
mode хранит одно absolute value или один shared residual delta и применяет его
к каждой position.

Segments используют:

```text
segmentCountMinus1:rangeCompactUint(rowLength - 1)
previousEnd = 0
repeat segmentCount times:
  remaining = segmentCount - currentIndex - 1
  gap:rangeCompactUint(rowLength - previousEnd - remaining - 1)
  start = previousEnd + gap
  lengthMinus1:rangeCompactUint(rowLength - start - remaining - 1)
  previousEnd = start + length
changed values in position order
```

Trimmed-mask mode использует:

```text
start:rangeCompactUint(rowLength - 1)
spanMinus1:rangeCompactUint(rowLength - start - 1)
changedMask[span]:1
changed values for set bits, in position order
```

Trimmed mask должен иметь минимум один set bit.

Когда `useResidual` установлен, каждое changed grayscale value представляется
ненулевой delta от predicted value:

```text
deltaCode = delta > 0 ? delta * 2 - 1 : -delta * 2
stored = compactUint(deltaCode - 1)
decodedValue = predictedValue + decodedDelta
```

Восстановленное value должно оставаться внутри выбранного profile.

### `directRowDelta`

Этот algorithm валиден только для grayscale и dynamic profiles. Он пропускает
local palette и запускает `compactRowDelta` прямо по profile-local values, с:

```text
valueBits = globalBits(profile)
```

Для grayscale profiles включено residual value coding. Для dynamic profiles
body использует dynamic-profile color ids без grayscale residuals.

### `compactSparse`

Хранит или наследует background reference. Хранит local palette foreground
colors, которая не должна содержать background. Затем хранит sparse segments,
пока не будет исчерпан segment count. Segments - это runs non-background pixels.

Этот вариант использует bounded compact integers для segment counts, skips и
lengths:

```text
segmentCountMinus1:boundedCompactUint(pixelCount - 1)
repeat segmentCount times:
  skipBackgroundPixels:boundedCompactUint(pixelCount - currentPosition - 1)
  localColorIndex:localBits
  segmentLengthMinus1:boundedCompactUint(pixelCount - segmentStart - 1)
```

### `varUintSparse`

Хранит или наследует background reference. Хранит local palette foreground
colors, которая не должна содержать background. Затем:

```text
segmentCount:bitVarUint
repeat segmentCount times:
  skipBackgroundPixels:bitVarUint
  localColorIndex:localBits
  segmentLength:bitVarUint
```

### `biColorMask`

Хранит или наследует background reference. Затем хранит один foreground color и
one-bit mask по всем pixels. Set bit выбирает foreground; unset bit выбирает
background. Этот algorithm использует compact block header, когда это возможно.

### `rowRepeat`

Хранит local palette и делит выбранную scan sequence на scan rows. Первую row
хранит raw. Каждая следующая row начинается с одного bit для всей row:

```text
firstRow[rowLength]:localColorIndex
repeat for each remaining row:
  sameAsPreviousRow:1
  if sameAsPreviousRow == 0:
    row[rowLength]:localColorIndex
```

Когда `sameAsPreviousRow` установлен, копируется вся предыдущая row. В этом
algorithm нет per-pixel equality bits.

## Неявный белый фон

Когда header bit `implicit-white-background` установлен, подходящие containers
и algorithms опускают свою background color reference и используют белый цвет
активного palette profile.

Это валидно для:

- sparse/background block algorithms;
- bounds containers;
- regions containers;
- solid containers.

Это невалидно для full block algorithms, у которых нет background reference.

## Прозрачность

Если transparent-color flag установлен, одна color reference хранится после
container/context byte и перед container body. Это только metadata. Pixel stream
по-прежнему содержит обычные palette references. Renderer должен рисовать
pixels, равные `transparentColor`, с alpha zero.

## Кодирование и подготовка к отправке

### За что отвечает encoder

Кодек v3 начинает работу с уже индексированного `MCOImage`. Преобразование
произвольного PNG, JPEG или RGBA bitmap в поддерживаемый palette profile - это
отдельный шаг quantization, не являющийся частью wire-формата v3.

Перед кодированием:

1. Проверьте `width` и `height` в диапазоне `1..256`.
2. Проверьте `pixels.length == width * height`.
3. Держите входные pixels в row-major order.
4. Выберите один `PaletteProfile`, содержащий каждый pixel color и
   опциональный transparent color.
5. Для fixed profiles используйте индексы этого profile напрямую.
6. Для dynamic profiles храните индексы Dynamic Global 512 в `MCOImage.pixels`,
   но каждую сериализуемую reference отображайте в profile-local id выбранного
   profile.
7. Рассматривайте `transparentColor` как rendering metadata. Не удаляйте эти
   pixels из pixel sequence.

Encoder может создать любую валидную комбинацию container и algorithm. Он не
обязан воспроизводить Dart candidate search. Candidate search влияет на размер
payload, а не на semantics decoding.

### Минимальный совместимый encoder

Небольшая реализация может поддержать любой валидный indexed input одной
комбинацией:

```text
container = compactBlock (id 1)
algorithm = rawGlobal (id 0)
scan      = h (id 0)
implicitWhiteBackground = false
```

Это не всегда достаточно compact для radio transport, но это полезный baseline
и fallback. Его body можно записать так:

Для `rawGlobal`, `rawLocal` и `biColorMask` `compactBlock` обязателен, а не
просто предпочтителен. Кодирование любого из этих scan-independent algorithms в
обычном container `block` является non-canonical, и эталонный decoder его
отбраковывает.

```text
writer.writeBits(packetNonce, 8)

imageHeader =
    (hasTransparentColor ? 0x80 : 0)
  | (0 << 6)                         // no implicit white background
  | (scanH << 4)
  | paletteProfileId
writer.writeBits(imageHeader, 8)

writeCanonicalDimensions(writer, width, height)

containerContext =
    (compactBlockId << 5)
  | rawGlobalAlgorithmId             // 0x20
writer.writeBits(containerContext, 8)

if hasTransparentColor:
  writer.writeBits(
    profileLocalRef(transparentColor),
    globalBits(profile),
  )

for pixel in rowMajorPixels:
  writer.writeBits(profileLocalRef(pixel), globalBits(profile))

body = writer.toBytes()              // zero-pad the final partial byte
```

`containerContext` - логическое 8-битное field, записанное на текущем bit
offset; оно не обязательно выровнено по физической границе byte после packed
dimensions. То же относится ко всем последующим fields.

Этот baseline каноничен при scan `h`. Если он превышает transport budget,
добавляйте compact candidates постепенно, например:

1. `solidBackground` для одноцветных изображений.
2. `rawLocal`, `compactRle` и `varUintRle`.
3. `biColorMask` и sparse modes для background-heavy images.
4. bounds containers, когда non-background pixels занимают меньший rectangle.
5. bitplane, row-delta, quadtree и LZ candidates.
6. region containers и alternative palette orders.

Всегда сохраняйте `rawGlobal` как valid fallback, даже когда он слишком велик
для целевого transport. Это позволяет encoder отличать “cannot represent this
image” от “valid image, but no candidate fits the current payload limit”.

### Построение и выбор candidates

Для каждого candidate:

1. Выберите top-level scan и конвертируйте row-major pixels в этот traversal.
2. Выберите container и algorithm, законный для этого container.
3. Выберите или унаследуйте background там, где он требуется.
4. Постройте local palettes там, где они требуются, и отобразите pixels в local
   indexes.
5. Закодируйте полное nonce-prefixed body, включая zero padding.
6. Отбракуйте candidate, если нарушено любое ограничение color, local index,
   geometry или algorithm.

Local-palette order не влияет на отрисованное изображение, но меняет local
indexes и поэтому compression. Базовый encoder может использовать first-use или
frequency order. Эталонный encoder дополнительно пробует profile, transition,
RGB и bitplane-optimized orders там, где это полезно.

Используйте один packet nonce при сравнении candidates либо placeholder byte:
nonce даёт одинаковую one-byte cost для каждого candidate. После выбора winner
обновляйте его nonce непосредственно перед каждой реальной send или resend.

Прямой вызов `MCOImageV3Codec.encode()` выбирает самое короткое binary body.
Когда два bodies имеют одинаковую byte length, он сравнивает только image-mode
rank:

```text
biColorMask, sparseBg, rowRepeat, rleLocal, rawLocal,
rawGlobal, extended, rowDelta, regionsBg
```

Если byte length и image-mode rank одинаковы, выбранным остаётся первый
увиденный candidate.

Более широкий helper `MCOImageCodec.selectBestCandidate()` используется, когда
caller, например Flutter canvas, объединяет candidates, созданные независимыми
worker slices. Порядок tie-break:

1. меньшая целевая длина: `byteLength` для `MCOImageOutputTarget.binary` или
   `charLength` для `MCOImageOutputTarget.text`;
2. меньший background-candidate rank;
3. bounds candidate перед non-bounds candidate;
4. container rank: bounds, затем ordinary full-image, затем regions;
5. image-mode rank:
   `extended`, `biColorMask`, `sparseBg`, `rowRepeat`, `rowDelta`,
   `rleLocal`, `rawLocal`, `rawGlobal`, `regionsBg`;
6. меньший scan id.

Если все fields равны, остаётся первый увиденный candidate. Другие encoders
могут выбрать любой valid equal-size candidate; эти предпочтения не меняют wire
compatibility. Если text transport имеет собственный character limit, после
выбора также измеряйте финальную строку `im3:` Base91.

Compression levels из этого документа являются рекомендуемыми search policies:

- Normal оценивает сокращённую candidate table.
- High - полный non-Extreme search по умолчанию.
- Extreme добавляет bounded deep region search.

Они не хранятся в body и не меняют decoder behavior.

### Канонические payload

После encoding держите три слоя раздельно:

```text
bare body:
  packetNonce | imageHeader | dimensions | containerContext | image data

app payload without sender:
  0x13 | bare body

channel app payload:
  senderNameLen(ULEB128) | senderNameUtf8 | 0x13 | bare body
```

Используйте app payload without sender для переносимых `.mcoimg.bin` файлов и
gallery storage. Не храните sender envelope в этих файлах.

Для text transport:

```text
im3: + Base91(0x13 | bare body)
```

Для binary channel transport:

```text
dataType = 0x0120
payload  = senderNameLen | senderNameUtf8 | 0x13 | bare body
```

Отбраковывайте binary output, если полный channel app payload превышает 165
байт. Поэтому sender-name envelope уменьшает body budget. Body, помещающееся с
коротким sender name, может не поместиться с более длинным.

### Dart-поток кодирования

Прямой эталонный вызов синхронный:

```dart
final image = MCOImage(
  width: width,
  height: height,
  paletteProfile: paletteProfile,
  pixels: List<int>.unmodifiable(pixels),
  transparentColor: transparentColor,
  encodingVersion: MCOImageEncodingVersion.v3,
);

final encoded = MCOImageV3Codec().encode(
  image,
  backgroundColor:
      transparentColor ?? MCOImagePalette.whiteIndexFor(paletteProfile),
  compressionLevel: mcoImageCompressionLevelHigh,
);
```

Подготовьте binary send через app helper:

```dart
final outbound = ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
  image: encoded,
  senderName: senderName,
);

if (outbound == null) {
  // Unsupported transport or payload exceeds the current binary limit.
  return;
}

// outbound.dataType == 0x0120
// outbound.payload is the complete sender-name app envelope.
```

`tryEncodeMcoImageV3Outbound()` копирует выбранное body и обновляет его nonce
перед построением envelope. При ручной сборке envelope сначала вызовите
`MCOImageV3Codec.refreshPacketNonce()`.

Низкоуровневый companion client затем может построить command frame:

```dart
final frame = buildSendChannelDataFrame(
  channelIndex,
  outbound.dataType,
  outbound.payload,
  pathBytes: selectedPath, // null/empty uses flood delivery
);
```

Приложение MeshCore обычно передаёт encoded result через channel-send path
`MeshCoreConnector`, а не вызывает `sendFrame` напрямую. Этот higher-level path
также применяет выбранный flood scope, radio-quiet delay, pending-message
tracking и retransmission bookkeeping; эти behaviours находятся вне формата
MCOimg.

### UI-паттерн интерактивного encoder

`lib/screens/canvas_editor_screen.dart` - эталонная UI-интеграция. Она убирает
синхронный codec с Flutter UI isolate и следует такому паттерну:

1. Захватить immutable encode request, содержащий dimensions, palette profile,
   pixels, transparency, preferred background, output target и compression
   level.
2. Debounce canvas changes и дождаться окончания активного drawing gesture.
3. Запустить `MCOImageV3Codec.encode()` в cancellable background compute task.
4. Отменять старые tasks, когда pixels или settings меняются.
5. Связывать каждый refresh с монотонно растущим request id и отбрасывать
   results для устаревшего canvas state.
6. Кешировать encoded result по всем fields, влияющим на encoding, включая
   полный pixel list.
7. Держать предыдущий valid size/result видимым, пока replacement encode
   выполняется или падает.
8. Перед sending дождаться текущего encode, пересчитать реальный transport size,
   проверить limit и только затем вернуть encoded result в chat.

Normal и High используют один background compute task для полного search.
Extreme может делить работу на независимые slices:

```text
one non-scan/regions slice per background candidate
one scan slice per (background candidate, scan mode)
```

UI собирает candidates из всех завершённых slices и выбирает лучший. При
cancellation или worker failure он останавливает оставшиеся tasks; текущая
реализация может вернуться к single encode, если parallel Extreme evaluation
падает.

Отображаемый payload size должен соответствовать выбранному transport:

```text
binary:
  uleb128ByteLength(senderNameUtf8.length)
  + senderNameUtf8.length
  + 1                         // subtypeVersion
  + body.length

text:
  length("im3:" + Base91(0x13 | body))
```

Сам canvas может продолжать rendering и editing обычных indexed pixels, пока
compression выполняется в background. Encoding progress и payload size - это UI
state; они не являются частью формата MCOimg v3.

Этот же экран демонстрирует переиспользуемый импорт/экспорт `.mcoimg.bin`.
Export сохраняет канонический app payload без отправителя, а не channel
transport envelope. Для v3 это:

```text
0x13 | packetNonce | imageHeader | dimensions | containerContext | image data
```

Когда такой файл импортируется обратно в editor, приложение декодирует его для
canvas, но также принимает импортированное binary body как текущий encoded
candidate. Пока пользователь не меняет pixels, dimensions, palette,
transparency, output target или compression settings, editor может
переиспользовать это точное compressed representation вместо повторного запуска
candidate search. Перед последующей отправкой обновляется только однобайтный
`packetNonce` v3; сжатый image bitstream остаётся byte-for-byte неизменным.

### Паттерн встроенной MCOimg-галереи

`lib/screens/mco_image_gallery_screen.dart` и
`lib/storage/mco_image_gallery_store.dart` - эталонная app-side интеграция
галереи. Галерея не является частью wire-формата; это удобный UI для выбора уже
закодированных MCOimg payloads.

Приложение держит два источника gallery items:

- пользовательские/импортированные items, сохранённые в app preferences;
- установленные image packs, сохранённые в app support directory в
  `mcoimg_packs/`.

Каждый gallery item содержит байты `.mcoimg.bin`, которые будут отправлены по
сети. Pack items также могут содержать упорядоченные candidates "original",
например Lottie, PNG, GIF или JPEG files, которые используются только для
локального preview и для замены полученных LoRa-quality MCOimg-сообщений на
более качественный original, если у получателя установлен тот же pack.

При открытии галереи pack groups загружаются как обычные collapsible gallery
groups. Обязательная default group для non-pack imports - локализованная группа
"common". Bundled packs можно поставлять как Flutter assets в `assets/mcopacks/`;
при startup/gallery access store устанавливает отсутствующие bundled
`.mcoimg.pack` archives в ту же app-support pack directory.

### Image packs `*.mcoimg.pack`

MCOimg image pack - это ZIP archive с расширением `*.mcoimg.pack`. Корень
archive содержит `info.json` и directory `images/`. Каждая непосредственная
subdirectory внутри `images/` представляет один gallery item:

```text
/
  info.json
  images/
    arbitrary-folder-name-1/
      arbitrary-name.lottie.json | arbitrary-name.lottie |
      arbitrary-name.webp |
      arbitrary-name.png | arbitrary-name.gif |
      arbitrary-name.jpg | arbitrary-name.jpeg
      arbitrary-name.mcoimg.bin
      arbitrary-name.md5?
    arbitrary-folder-name-2/
      ...
```

Каждая image folder должна содержать:

- один файл `*.mcoimg.bin`: канонический MCOimg payload, отправляемый по сети;
- минимум один поддерживаемый original file:
  `*.lottie.json`, `*.lottie`, `*.webp`, `*.png`, `*.gif`, `*.jpg` или
  `*.jpeg`.

Image folder без валидного original file или без файла `*.mcoimg.bin`
пропускается. Folder и file names произвольные, но import sanitizes их для
безопасного хранения в filesystem. Items упорядочиваются по
natural/alphanumeric order имён image folders, поэтому folders `1`, `2`, `10`
показываются именно в таком порядке.

Если для одного item присутствует несколько original files, receiver пробует их
в таком порядке приоритета:

```text
.lottie.json, .lottie, .webp, .png, .gif, .jpg, .jpeg
```

Files с одинаковым format priority упорядочиваются по natural filename order.
Если original с более высоким приоритетом не удаётся загрузить, renderer
переходит к следующему candidate. Если ни один original candidate не работает,
показывается decoded MCOimg image.

Опциональный файл `*.md5` хранит identity hash, используемый для сопоставления
полученного MCOimg-сообщения с pack original. Его содержимое - 32-character
hexadecimal MD5 string. Каноническая formula реализована в
`lib/helpers/mco_image_identity.dart`: lowercase MD5 от bytes файла
`.mcoimg.bin`, при этом nonce byte тела v3 перед hashing обнуляется. Если файл
`*.md5` отсутствует, приложение вычисляет тот же hash из `.mcoimg.bin` при
построении pack-originals index.

`info.json` содержит metadata pack:

```json
{
  "name": "Pack name, for example Smiles",
  "id": "Internal pack id, for example smiles",
  "ver": "Pack version, for example 1.0.0",
  "author": "Author name, for example Aiwan",
  "authorUrl": "Optional author website URL",
  "packUrl": "Optional URL where this pack can be downloaded",
  "maxImageSize": 48
}
```

Required fields: `name`, `id` и `ver`. `author`, `authorUrl`, `packUrl` и
`maxImageSize` optional. `maxImageSize`, если присутствует и является
положительным, ограничивает longest side gallery preview для этого pack.

Installed folder name выводится из metadata:

```text
mcoimgpack_<id>_<author-or-unknown>_<ver>
```

Если pack с тем же derived folder name импортируется повторно, старая installed
folder удаляется и заменяется содержимым нового archive. Installed packs
показываются по алфавиту `name`; group title галереи:

```text
name (author, ver. version)
```

или, когда author отсутствует:

```text
name (ver. version)
```

## Поиск candidates encoder

Совместимый decoder не обязан воспроизводить encoder search. Ему нужно только
декодировать все valid containers и block algorithms.

Чтобы воспроизвести качество сжатия Dart encoder, реализуйте candidate search
примерно так:

1. Постройте background candidates. Normal проверяет preferred background плюс
   самые частые цвета. High и Extreme могут exhaustively проверить все
   использованные цвета для малых изображений.
2. Проверьте full-image block containers по разрешённым scan orders и
   algorithms.
3. Проверьте bounds containers, когда background оставляет меньший
   non-background rectangle.
4. Проверьте solid background и solid rectangles.
5. Проверьте connected/split/greedy/beam region layouts.
6. Для каждого local-palette algorithm проверьте local palette orders, которые
   имеют значение: frequency, first-use, profile order, transition order, RGB
   order и bitplane-optimized order, когда это разрешено compression level.
7. Выберите самый маленький payload. Ties предпочитают более
   простые/стабильные modes, используя Dart candidate ranking.

Encoder search намеренно может развиваться без изменения wire-формата.

## Требования к валидации decoder

Надёжный port должен отбраковывать:

- unknown subtype/version при чтении canonical app payloads;
- unsupported palette, scan, container или algorithm ids;
- non-canonical dimension encodings;
- colors вне выбранного profile;
- duplicate local palette colors;
- local indexes вне local palette length;
- invalid sparse, RLE, LZ, row-delta, quadtree или region ranges;
- non-zero final padding bits;
- trailing bytes после завершения bit reader.

## Минимальные Dart-примеры

### Кодирование для channel binary

```dart
final encoded = MCOImageV3Codec().encode(image);

final outbound = ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
  image: encoded,
  senderName: 'MyName',
);

if (outbound != null) {
  // outbound.dataType == 0x0120
  // outbound.payload == senderNameLen | senderName | 0x13 | refreshedBody
}
```

### Кодирование как text fallback

```dart
final encoded = MCOImageV3Codec().encode(image);
final text = MCOImageV3Codec.textFromBody(encoded.body);
```

### Декодирование channel app payload

```dart
final envelope = ChannelAppDataHelper.tryDecodeEnvelope(payload);
if (envelope?.subtypeId == ChannelAppDataHelper.mcoImageSubtype &&
    envelope?.version == ChannelAppDataHelper.mcoImageV3Version) {
  final image = MCOImageV3Codec().decodeBody(envelope!.body);
}
```

### Декодирование canonical file payload

```dart
final image = MCOImageV3Codec().decodeAppPayloadWithoutSender(fileBytes);
```

`image` - это data object `MCOImage`, а не Flutter widget и не PNG. Это
decoded indexed image:

- `image.width`, `image.height`: dimensions в pixels;
- `image.paletteProfile`: palette profile, используемый pixel indexes;
- `image.pixels`: immutable row-major palette references, длина
  `width * height`;
- `image.transparentColor`: опциональная palette reference, которую нужно
  rendering с alpha zero.

Чтобы прочитать один decoded pixel:

```dart
final pixel = image.pixels[y * image.width + x];
```

Здесь `x` - горизонтальная coordinate слева направо, а `y` - вертикальная
coordinate сверху вниз. Обе zero-based:

```text
x: 0 .. image.width - 1
y: 0 .. image.height - 1
```

`pixels` - плоский row-major list, поэтому index для `(x, y)` равен
`y * image.width + x`.

Для display или export отобразите каждую pixel reference через palette table
для `image.paletteProfile` и примените `transparentColor` как alpha zero.

### Конвертация decoded image в RGBA или PNG

Чтобы отрисовать или сохранить decoded image, сначала конвертируйте indexed
pixels в RGBA buffer:

```dart
final rgba = Uint8List(image.width * image.height * 4);
final palette = image.paletteProfile.isDynamic
    ? MCOImageDynamicPalette.global512
    : MCOImagePalette.colorsFor(image.paletteProfile);

for (var i = 0; i < image.pixels.length; i++) {
  final colorIndex = image.paletteProfile.isDynamic
      ? image.pixels[i].clamp(0, MCOImageDynamicPalette.global512.length - 1)
      : image.pixels[i].clamp(0, palette.length - 1);
  final color = palette[colorIndex.toInt()];
  final offset = i * 4;

  rgba[offset] = (color.r * 255).round().clamp(0, 255).toInt();
  rgba[offset + 1] = (color.g * 255).round().clamp(0, 255).toInt();
  rgba[offset + 2] = (color.b * 255).round().clamp(0, 255).toInt();
  rgba[offset + 3] =
      image.transparentColor != null &&
          image.pixels[i] == image.transparentColor
      ? 0
      : (color.a * 255).round().clamp(0, 255).toInt();
}
```

После этого передайте RGBA buffer в image encoder целевой platform. Во Flutter
эталонная реализация использует `ui.decodeImageFromPixels(...)` с
`ui.PixelFormat.rgba8888`, затем `ui.Image.toByteData(format:
ui.ImageByteFormat.png)`. Полный поток PNG export см. в
`MCOImageFileSaver.savePng(...)` в Dart-приложении.

### Инспекция без полной отрисовки

```dart
final info = MCOImageV3Codec.inspectAppPayloadWithoutSender(fileBytes);
print('${info.algorithm}, ${info.binaryLength} bytes');
```

## Чеклист портирования

1. Точно перенести palette tables, включая dynamic profile mapping.
2. Реализовать LSB-first bit reader/writer и integer primitives.
3. Реализовать минимальный encoder и decoder `compactBlock + rawGlobal`.
4. Реализовать parsing и creation app payload: `0x13 | body`.
5. Реализовать sender-envelope ULEB128 и binary route `0x0120`.
6. Реализовать preamble тела v3, dimensions и container/context byte.
7. Реализовать local palette descriptors.
8. Реализовать дополнительные block algorithms.
9. Реализовать containers, особенно compact bounds и compact regions.
10. Запустить существующие fixtures из `docs/mcoimg-js/tests/` против port и
    добавить fixtures для новых wire cases.
11. Добавить roundtrip tests для каждого palette profile и каждого
    block/container family.
12. Только после устойчивого basic encoder/decoder parity переносить полный
    encoder candidate search и UI worker slicing.
