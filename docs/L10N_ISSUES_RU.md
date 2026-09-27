# Локализация: известные ошибки

Аудит 2026-09-27 прошёл все 16 переводов, кроме эталонных en и ru, и исправил их на месте. Ниже то, что осталось: ошибки в самих en и ru, расхождения текста с кодом, одна правка кода и дубликаты ключей. Исправленный пункт удаляй из списка.

## Проблемы к устранению

### ru

| Ключ | Сейчас | Нужно |
|---|---|---|
| `repeater_cliHelpSetLoopDetect` | значения переведены («выключено», «минимальная», …) | латиницей, как их принимает CLI: `off`, `minimal`, `moderate`, `strict` |
| `repeater_cliHelpSetPrvKey` | «(Только через последовательный порт) …» | без пометки, как в en: `set prv.key` принимается и удалённо, только через serial работает `get prv.key` (`CommonCLI.cpp`) |
| `settings_mcmp_useSign` | «Проверка подписи» | «Подпись сообщений»: переключатель включает подпись исходящих |
| `settings_mcmp_noSign` | «Без проверки подписи» | «Без подписи» |
| `receivedImage_decoderMissing` | «Получен изображение — декодирование изображения неправильное» | по en: изображение получено, декодирование изображений выключено |
| `imageSend_floodNote` | «Руководство по маршрутизации потоков…», «перераспределяет», «занятным» | по en: при flood каждый ретранслятор в зоне повторяет каждый пакет, поэтому канал занят дольше указанного |
| `repeater_txDelay` | «Задержка в работе системы Flood TX» | «Задержка передачи flood» |
| `messageStatus_repeated` | ключ задан дважды, первая копия «Услышал несколько раз» | удалить первую копию; действует вторая, «Услышано повторение» |
| `login_repeaterDescription`, `login_roomDescription` | «…для доступа к настройкам и статусу» | по en: пароль для гостевого или администраторского доступа |
| `channelPath_timeLabel` | «Время получения/создания» | по en: время получения |
| `settings_modSettingsSubtitle` | нет «добавленные MCOa» | по en: опции, добавленные MCOa, которых нет в оригинальном meshcore_open |
| `tcpHostLabel`, `tcpErrorHostRequired` | «IP-адрес» | подходит и имя хоста: «Адрес», «Укажите адрес.» |
| `settings_copyMsgPathEditTemplateDscr` | «%hopKey% - ключ хопа» | «префикс хопа» |
| `losBlockedSpotsTitle` | «Зарезервированные места» | точки, где линия видимости перекрыта: «Препятствия» |
| `translation_manualUrlLabel` | «Ссылка на руководство» | URL модели, введённый вручную: «URL модели (вручную)» |
| `map_zoomOut` | «Увеличить масштаб», так же как `map_zoomIn` | «Уменьшить масштаб» |
| `map_centerMap` | «Карта центра» | «Центрировать карту» |
| `radioStats_screenTitle` | «Статистика радиовещания» | «Статистика радио» |

### en

- `repeater_cliHelpSetPathHashMode`: «0 = legacy, 1 = standard, 2 = strict. Affects how routing paths are matched» не соответствует прошивке. Режим задаёт ширину хеша хопа в пути: 0, 1, 2 означают 1, 2, 3 байта (companion шлёт flood с `path_hash_mode + 1`, CLI на другое значение отвечает «Error, must be 0,1, or 2»). Ошибку повторяют все 17 переводов: поправить en и ru, потом остальные.
- `appSettings_languageHu`, `appSettings_languageJa`, `appSettings_languageKo` написаны по-английски, хотя остальные пункты списка языков даны самоназваниями («Deutsch», «Русский»). Вслед за этим все локали переводят эти три пункта и `appSettings_languageEn` («Венгерский», «Японский», «Корейский», «Английский»). Если нужны самоназвания («Magyar», «日本語», «한국어», «English»), менять во всех 18 файлах.

### Текст расходится с кодом, во всех 18 файлах

- `settings_frequencyHelper` пишет «300.0 - 2500.0», а `settings_screen.dart` и текст ошибки `settings_frequencyInvalid` принимают 150–2500 МГц. Поменять 300 на 150 в en и ru, потом в остальных.
- `imageSend_deviceUnsupported` требует «companion firmware 13 or newer», а `supportsChannelData` проверяет version code 11 (прошивка v1.15.0). Поправить число в en и ru, потом в остальных.

### Код

- `settings_screen.dart` разбирает частоту и координаты узла через `double.tryParse` без замены запятой, в отличие от `_normalizeDecimal` в `repeater_settings_screen.dart`. С клавиатуры с десятичной запятой ввод «868,0» отвергается как неверная частота. Подсказка частоты во всех локалях уже с точкой, но надёжнее принимать и запятую, как в настройках ретранслятора.

### Дубликаты ключей

Значения копий совпадают, кроме `messageStatus_repeated` в ru (см. выше), так что сейчас это ни на что не влияет. Но gen-l10n читает последнюю копию, и правка одной первой копии пропадёт незаметно: менять все копии или удалить лишние. Мёрджи из upstream могут возвращать их, как и устаревшие ключи.

| Файл | Ключей | Что продублировано |
|---|---|---|
| bg, pl, sk, sl, uk, zh | 35 | блок `telemetry_*` |
| ko | 38 | блок `telemetry_*`, `messageStatus_pending`, `_sent`, `_delivered` |
| de | 15 | ключи регионов `settings_region*`, `settings_deleteRegion*`, `channels_region*`, `channels_clearRegion` и две `@`-метаданные |
| it | 11 | `contacts_search*` с `@`-метаданными, `contacts_manageRoom`, `notification_receivedNewMessage` |
| ru | 9 | `common_clear`, `common_deleteAll`, `common_done`, `common_undo`, пять `messageStatus_*` |
| ja | 6 | `common_undo`, пять `messageStatus_*` |
| en | 2 | `common_clear`, `chat_mcmpSignedTimestamp` |
