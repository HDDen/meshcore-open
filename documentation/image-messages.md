# Image Messages

MeshCore Open can send a highly compressed image as channel GRP_DATA packets. Unlike a GIF reference or URL preview, the compressed image bytes travel over the mesh. A compatible recipient reconstructs them locally using the image model.

## Requirements and setup

- Companion firmware version code **11 or later** (identified in the connector as v1.15.0) for the current channel-data layout.
- A native runtime with a working ONNX backend. The web build has no image codec backend.
- The image model bundle installed through App Settings → Image model, and Enable image messages turned on.
- Enough storage for the roughly 1 GB bundle and enough available memory for reconstruction, which can peak above 2 GB. Actual latency and memory usage depend on hardware.

Downloads use the configured Hugging Face model bundle, support resume, and verify file checksums. Download the model while internet is available. Once installed, encoding and reconstruction run locally; photos are not uploaded for inference. Compatible recipients need the same supported codec/model format.

## Android: сбой при открытии отправки или обработке AEIC

Если приложение полностью закрывается при обработке AEIC на Android, причиной
может быть native runtime, а не размер изображения. В полученном отчёте Poco
зафиксирован SIGILL внутри старой ONNX Runtime 1.23.0. Для похожих сбоев на
Android 16 исправлялся выбор CPU-инструкций; это отличается от нехватки памяти.
См. [обсуждение ONNX Runtime](https://github.com/microsoft/onnxruntime/issues/27884).

Текущая зависимость приложения `flutter_onnxruntime` 1.9.0 использует Android
ORT 1.28.0. Перед повторной проверкой нужна сборка с обновлённой библиотекой;
важен состав установленного APK, а не только номер версии приложения.
Переустановка с сохранением данных не требует повторного скачивания модели.
После обновления проверить и отправку, и получение AEIC; если сбой повторится,
нужен новый logcat. Наличие NPU не гарантирует его использование кодеком:
текущий путь выполняет модель через CPU ONNX Runtime.

## Если пункт «Отправить изображение» не реагирует

`aeic_decoder_qdq_conv_pct.onnx` сам по себе занимает 3 066 597 байт — это
нормальный размер графа. Внешние веса находятся в соседнем файле
`aeic_decoder_qdq_conv_pct.onnx.data` (872 896 480 байт). Вместе с двумя
entropy-графами и CDF-таблицей комплект занимает 1 004 548 432 байта, около
958 МиБ. Размер отдельного `.onnx` нельзя сравнивать с размером всего комплекта.

Если приложение в списке установленных моделей показывает всего около 3 МБ,
комплект неполный. Ранее строка загрузки могла ошибочно показывать «Готово»
при наличии одной записи о графе. Теперь для «Готово» нужен весь актуальный
комплект; для неполной установки доступна кнопка «Скачать». Нажмите её при
доступном интернете и дождитесь завершения: целые файлы после проверки
контрольной суммы используются повторно, недостающие докачиваются. Удалять
приложение или его данные для этого не требуется. Пока зарегистрированные
веса декодера отсутствуют или не прошли проверку размера при сканировании,
AEIC-отправка и приём не запускают inference.


В прежней реализации меню могло показывать этот пункт обычным текстом, но без
обработчика нажатия, если `ImageCodecService` считал модель неготовой. При этом
меню не закрывалось и системный выбор файла не открывался — ONNX ещё не запускался.

Теперь видимый пункт остаётся доступным: меню закрывается, после чего приложение
проверяет готовность модели. Если она не готова, открывается окно с причиной:
модель выключена, отсутствует/не полностью установлена, загружается или недоступен
backend. Для исправления установки откройте «Настройки приложения → Модель
изображения» и проверьте выбранную модель и состояние загрузки. Диагностика с
тегом `ImageSend` записывает состояние и причину, если журнал приложения включён.

Это исправление обратной связи не подтверждает устранение прежнего native-краша.
Если модель готова, но приложение закрывается при кодировании/получении AEIC,
нужен новый logcat из установленной сборки. Если появляется окно недоступности,
для дальнейшей диагностики нужен его точный текст.

## Send an image

1. Open channel chat and tap the image button beside the composer.
2. Pick a photo from your gallery.
3. Wait for encoding. Inspect the source preview and, if available, the reconstructed preview.
4. Review transmitted bytes, packet count, and estimated send duration. Estimates use the current radio settings and are unavailable if those settings are unknown.
5. Choose whether to include a recovery packet, then send. The chat shows per-packet progress.

The current build ships one quality/model setting: **ft32**, with a 512×512 codec reconstruction and metadata used to restore a supported aspect ratio. Reserved rate/resolution codes are not additional selectable quality options.

The result is a lossy, AI-reconstructed image and can differ materially from the original. It is labeled accordingly. Send confirmation describes companion acceptance of packets, not end-to-end proof that every recipient reconstructed the image.

## Receive, reconstruct, and save

Chunks are reassembled into an image entry in channel chat. A partially received stream is retained for up to 60 seconds before expiry. An optional XOR parity packet can recover **one missing data chunk**, provided the parity and other required chunks arrive; it does not guarantee delivery.

В [энергосбережении](power-saving.md) можно включить «Приостанавливать очистку изображений в простое». Пятиисекундный таймер тогда работает только при наличии незавершённых потоков или временного кэша завершённых для защиты от дубликатов. Срок сборки 60 секунд от первого пакета сохраняется; проверка таймером может завершить ожидание позже этой границы, особенно при приостановке приложения ОС. Декодирование и хранение на диске не зависят от этой опции.

With Process images automatically enabled, complete images are queued for local reconstruction. Automatic decoding runs only while the app is in the foreground, one image at a time, with at most 3 images queued; when more arrive, the newest 3 are kept and the rest wait for a tap. Otherwise, tap an image entry to process it. Download/enable the model if prompted. A failed reconstruction can be retried; missing chunks and inference errors are different failures.

Tap a reconstructed image to inspect it. Long-press or right-click its chat bubble for Packet info, Delete, and Save (available once decoded). Deletion is local. Encoded streams and reconstructed images are persisted in application storage, capped at 200 images, 64 MB, and 30 days, plus a limit of 400 image entries (including ones waiting to be decoded and your own sent images once their data has expired). When the cap is reached, the oldest reconstructed images are evicted first and show "Image no longer stored"; they can be decoded again while their small encoded stream remains. Past 30 days the stream is removed too.

## Other image features

[GIFs and URL image previews](additional-features.md#url-image-previews) transmit references and fetch image content over the internet. They do not use this mesh image transport.

## Implementation reference

[image_chunk_transport.dart](../lib/services/image_chunk_transport.dart) defines the wire layout, capacities, metadata, and recovery algorithm. The current transport uses command 62, response 27, and data type `0xAE1C`. See the [protocol reference](ble-protocol.md#regions-and-image-data) and [fixture regeneration guide](../tools/aeic/README.md).


### Сохранённый AEIC-битстрим и повтор передачи

Сохранённую входящую картинку можно передать повторно без запуска нейросети:
helper `channel_image_replay.dart` восстанавливает чанки из битстрима тем же
сборщиком, что используется для отправки. PNG не перекодируется. Если битстрим
уже удалён, картинка не получена целиком или её метаданные неизвестны, повтор
не создаётся. Выбор канала учитывает его identity-группу, а не только номер слота.
У бинарного кадра AEIC нет времени сообщения; исходное время получения и
радиометрики в таком повторе клиенту не передаются. Эти изменения требуют обычной
пересборки приложения; новые модели и нативные библиотеки не требуются.
