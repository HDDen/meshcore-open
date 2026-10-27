# Учёт незавершённой фоновой работы

`lib/helpers/background_work_tracker.dart` — общий для платформ реестр операций.
Подключение выполнено в коннекторе для общего handshake, записи кадров и ожидания команд,
синхронизации контактов/каналов и сообщений, активной отправки и повторов,
а также выполнения scheduled/deferred очередей, передачи изображений
и основных операций сохранения истории и уведомлений.
Снимок доступен через `backgroundWorkSnapshot`. При выключенной CPU-политике
учёт остаётся наблюдательным. Новая Android-группа через CpuSleepBinding связывает
выбранные виды работы с собственным CPU lock и подготовкой перед run(); пассивные
ожидания повторов исключены. Пустота снимка сама по себе не разрешает сон.
Правила и проверки: [сон CPU](android-cpu-sleep.md).

Описания этапов ниже фиксируют границы ранее добавленного учёта. Фразы о прежней
CPU-политике относятся к этим этапам; действующее управление описано по ссылке выше.

## Удержания операций

`begin(kind)` возвращает отдельный `BackgroundWorkLease`. Две операции одного
типа имеют два независимых удержания; освобождение одного не завершает другое.
Повторный `release()` ничего не меняет. Это отличается от существующего набора
причин `BackgroundService`: повторный `start` с той же причиной остаётся
идемпотентным, его правила не заменены новым реестром.

`run(kind, operation)` удерживает работу до завершения переданного callback,
возвращает результат и освобождает удержание в `finally`, в том числе при
синхронной или асинхронной ошибке. Операция должна включать всю защищаемую часть:
например, разбор и сохранение сообщения, если именно их завершение требуется
перед продолжением синхронизации.

Таймаут ожидания у вызывающего кода не отменяет выполняющуюся операцию. Если
вызывающий перестал ждать `run(...).timeout(...)`, реестр продолжает учитывать
исходную работу до её фактического завершения. Если сам callback возвращает
обёртку `future.timeout(...)`, реестр видит завершение именно этой обёртки;
завершение исходного ввода-вывода она не гарантирует. Границу удержания нужно выбирать
в месте владения операцией, а не по произвольному внешнему таймауту.

## Подключение записи и команд

`lib/helpers/frame_background_work.dart` использует общий реестр коннектора:

- `transportWrite` охватывает Future исходного низкоуровневого writer, ниже
  внешнего таймаута. Если `sendFrame` уже завершился по timeout, удержание записи
  остаётся до завершения исходного Future. Это завершение API транспорта,
  а не подтверждение доставки клиенту или передачи в эфире.
- `commandReply` создаётся только у команды с ожидающим completer: от регистрации
  ответа через запись до завершения логического ожидания. Ранний OK/ERR не
  завершает эту команду, пока не закончилась запись. После прежнего ACK timeout
  удержание снимается; пассивный tombstone в очереди удержанием не является.

Порядок регистрации ответа, байты, транспортные ветки и последовательные
таймауты 5 секунд записи / 5 секунд ответа сохранены. Команда без ожидания ACK
не получает `commandReply`, даже если запись в очереди ответов ещё остаётся.
Подготовка до `_sendFrameDirect`, начальная синхронизация и остальные
владельцы требуют отдельного подключения. Граница обработки приёма описана ниже.

При `dispose` коннектор закрывает реестр без сброса активных удержаний.
Начатые записи и команды освобождают их своим `finally`. Поздние вызовы после
закрытия выполняются по прежнему коду без новых удержаний: закрытие учёта не
добавляет новых ошибок или отмены транспорта. Поэтому закрытый снимок также
не доказывает полноту учёта и не может разрешать сон.

## Снимки и завершение

`snapshot` содержит ревизию, состояние закрытия, общее число удержаний и
неизменяемые счётчики по типам работы. Снимок не меняется вслед за реестром.
Кадры, адреса, ключи и содержимое сообщений в нём не хранятся.

`close()` запрещает новые удержания, сохраняя незавершённые до их освобождения.
Он не отменяет операции и не объявляет их завершёнными. Общего сброса активных
удержаний и автоматического освобождения по времени нет. Удержание старого
реестра не может изменить новый реестр.

Реестр не создаёт таймеров, потоков событий или платформенных вызовов. Само
наличие счётчиков не обеспечивает охват всех операций, пробуждение устройства
или сохранение сроков ACK/retry при сне. Подключение потребителей и решение о
разрешении сна — отдельные этапы. Текущие CPU/Wi-Fi lock,
heartbeat, транспорты, хранение истории и профили сохраняются.

## Проверка

```powershell
$frameWorkTests = @(
  'test/helpers/background_work_tracker_test.dart'
  'test/helpers/frame_background_work_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/frame_work_tracking_test.dart'
  'test/connector/pending_command_replies_test.dart'
)
flutter test @frameWorkTests --reporter expanded
flutter analyze
```

Тесты проверяют владение, параллельные и вложенные операции, ошибки, таймаут
ожидания, неизменяемость снимка и закрытие. Они не измеряют расход батареи,
работу native wake lock или поведение ОС в фоне.

Перед подключением реестра к командам отдельно подготовлен и принят baseline настоящего
`MeshCoreConnector.sendFrame`: физический writer заменён синтетическим, очередь
ответов и входящий dispatch работают как в приложении. Фиксируются ранние OK/ERR,
ошибка/таймаут записи, отдельное ожидание ACK, его tombstone и конкретный код
ответа вместо общего OK. Исходные 5 секунд записи и последующие 5 секунд ACK
сохраняются. Его ожидания не переписаны; отдельные регрессии счётчиков находятся
в `test/connector/frame_work_tracking_test.dart`.

## Обработка полученных сообщений

`lib/helpers/message_processing_background_work.dart` добавляет `messageSync`
на время `_processPotentialQueuedMessage`: от входа в общий путь до окончания
обработки и её продолжения очереди. Это охватывает contact/channel сообщения
и channel data, проходящие через этот метод, включая сообщения вне очереди и
локальные источники. Разбор, проверка и ожидаемая обработчиком запись истории
остаются внутри удержания. При запуске следующего `SYNC_NEXT_MESSAGE` обработка
ещё удерживается; запись кадра получает собственный `transportWrite`.

Синхронная/асинхронная ошибка освобождает только удержание своей операции.
Прежняя queued-ветка останавливает синхронизацию при ошибке; вне очереди исходная
ошибка передаётся вызывающему. Внешний timeout ожидания и потеря связи не
завершают ещё работающий Future. Dispose закрывает учёт, сохраняя начатые
операции; поздние вызовы не получают новых удержаний и выполняются прежним кодом.

Ожидание ответа ноды учитывается отдельным `queuedMessageRequest`, описанным ниже.
Отдельно предстоит учитывать deferred/unknown-sender replay,
восстановление direct echo, другие RX-пути, отложенные записи, уведомления и
продолжение обработки FR01/MCOimg после возврата из callback. Существующие
неожидаемые Futures не стали ожидаемыми ради учёта. Наличие записи в истории
и полный учёт всех асинхронных работ — разные гарантии.

Перед подключением учёта приёма подготовлен
`test/connector/queued_message_processing_baseline_test.dart`. Он вызывает
настоящий контроль очереди через тестовый адаптер, подменяя только callback
разбора/сохранения. Это позволяет удержать обработку дольше пяти секунд и
проверить, что транспортный timeout уже отменён, а повторные запросы и
`MSG_WAITING` не продвигают очередь до завершения callback. Ошибка queued-обработки
останавливает синхронизацию; ошибка вне активной очереди передаётся вызывающему.
Локальный источник не считается ответом на ожидающий запрос.

Этот baseline не заменяет тесты настоящей истории. Вместе с ним проверяется
неизменённый `queued_message_notifications_test.dart`: direct/channel приём,
история перед следующим запросом и независимость от задержанного уведомления.
Принятый baseline сохранён; алгоритм внутри `_processPotentialQueuedMessageCore`
сохранился. Новые счётчики проверяются отдельно, без изменения его ожиданий.

```powershell
$messageWorkTests = @(
  'test/helpers/message_processing_background_work_test.dart'
  'test/connector/queued_message_processing_baseline_test.dart'
  'test/connector/queued_message_work_tracking_test.dart'
  'test/connector/queued_message_notifications_test.dart'
)
flutter test @messageWorkTests --reporter expanded
flutter analyze
```

Регрессии проверяют границы обработки/записи, передачу следующему writer,
ошибки, внешний timeout, параллельные операции, потерю связи и закрытие учёта.
Управление CPU и четырнадцать пользовательских параметров остаются прежними.

## Ожидание ответа очереди

`lib/helpers/queued_message_request_background_work.dart` добавляет отдельное
удержание `queuedMessageRequest`. Оно начинается до отправки SYNC_NEXT и остаётся
после завершения writer, пока прежний алгоритм ожидает ответ. Пустой ответ,
таймаут, остановка очереди или сброс sync/transport-состояния завершают ожидание.
При обычном полученном сообщении `messageSync` уже создан до снятия ожидания
ответа. Принятый queued-фрагмент завершает текущий запрос и запускает следующий
по прежним правилам; само ожидание остальных фрагментов требует отдельного учёта.

Удержание содержит токен запроса. Завершение прежнего токена не снимает новый;
успешное позднее завершение старого writer освобождает только его I/O. Существующий
catch ошибки записи по-прежнему останавливает всю очередь, поэтому при такой
остановке снимается её текущее логическое ожидание. Это поведение не исправлялось
в рамках добавления счётчиков. Завершение ожидания не подтверждает доставку.

Обычные OK/ERR не стали завершением очереди. Сообщение с локальным источником,
проходящее через общий обработчик, не снимает чужое ожидание ответа. Внешний
таймаут вызывающего также его не отменяет. Если исходный writer ещё выполняется
после прежнего write timeout, его отдельный `transportWrite` сохраняется.

Helper не добавляет таймеров: используются прежние границы очереди.
Dispose закрывает реестр, сохраняя начатые удержания; pending wait может
завершиться прежним таймаутом. Поздний запрос после close выполняется по прежнему
коду без нового удержания. Закрытый снимок не используется для разрешения сна.

Перед подключением оставшегося промежутка ожидания подготовлен
`test/connector/queued_message_request_baseline_test.dart`. Девять сценариев
вызывают настоящие `syncQueuedMessages` и входящий dispatch с подменой только
физического writer. Срок ответа отсчитывается от начала запроса, до завершения
записи, и не переносится на пять секунд после неё. Пустой ответ может завершить
очередь раньше окончания записи; позднее успешное завершение старой записи
не должно изменять уже начатый новый запрос.

Также фиксируются остановка при ошибке/таймауте записи без автоматического
повтора, сброс sync-состояния, отсутствие новых запросов после dispose,
отсутствие отправки без подключения и независимость очереди от обычных OK/ERR.
Тестовый `resetSyncProgressForTest` вызывает настоящий сброс флагов/таймеров;
это проверка данной части cleanup, а не всего native teardown.
Callbacks только записывают наблюдения; проверки выполняются вне них.
Принятые request/processing baseline-файлы не переписаны. В прежних регрессиях
обработки сохранены ожидания `messageSync`/`transportWrite` и отдельно добавлен
новый счётчик запросов. Для fragment continuation используется тестовый адаптер;
сам FR01 parser/ACK проверяется отдельными прежними тестами.

```powershell
$queueRequestWorkTests = @(
  'test/helpers/background_work_tracker_test.dart'
  'test/helpers/queued_message_request_background_work_test.dart'
  'test/connector/queued_message_request_baseline_test.dart'
  'test/connector/queued_message_request_work_tracking_test.dart'
  'test/connector/queued_message_processing_baseline_test.dart'
  'test/connector/queued_message_work_tracking_test.dart'
  'test/connector/queued_message_notifications_test.dart'
  'test/helpers/south_queued_fragment_ack_tracker_test.dart'
  'test/connector/south_frame_fragment_protocol_test.dart'
)
flutter test @queueRequestWorkTests --reporter expanded
flutter analyze
```

Существующие FR01-тесты сохраняют контекст queued ACK и байты расширенного
SYNC_NEXT. Формат, сроки и control flow очереди сохраняются; новые регрессии
проверяют границы счётчиков. CPU/Wi-Fi lock, heartbeat и четырнадцать
пользовательских параметров остаются прежними.

## Baseline загрузки контактов и каналов

Перед подключением `contactSync`/`channelSync` подготовлен
`test/connector/contact_channel_sync_baseline_test.dart` с 16 сценариями.
Используются настоящие `getContacts`, `getChannels`, входящий dispatch и таймеры;
физический writer синтетический. Mock preferences и запрет получения desktop
support directory исключают чтение и ремонт реальных файлов настроек.

Контакты сохраняют активное состояние после записи команды до END_OF_CONTACTS
или десятисекундного timeout тишины. START переустанавливает этот timeout;
проверяются также незапрошенный START, фильтр since, повторный запрос во время
загрузки, ранний END, ошибка записи и переход к очереди сообщений.

Каналы запрашиваются последовательно: timeout одного слота — две секунды,
после трёх повторов слот без кэша остаётся неподтверждённым, начинается следующий.
Проверяются пустые слоты, ERR_NOT_FOUND, отложенный force restart, ранние ответы,
ошибка writer, reset и отсутствие подключения. Существующий async hook
финализации удерживается через `setChannelImageStampForTest`: пока он не закончен,
sync остаётся активным, повторов и запуска ожидающей очереди сообщений нет.

Фикстура не привязывает ноду и использует пустые слоты. Она не проверяет
SQLite, восстановление непустого кэша, миграции, реальные контакты с историей
или native handshake. Владелец подтвердил предварительный пакет; baseline
сохранён без изменений при подключении учёта ниже.

```powershell
$syncBaselineTests = @(
  'test/connector/contact_channel_sync_baseline_test.dart'
  'test/connector/contact_push_codes_test.dart'
  'test/connector/queued_message_request_baseline_test.dart'
)
flutter test @syncBaselineTests --reporter expanded
flutter analyze
```

## Учёт загрузки контактов и каналов

`helpers/sync_background_work.dart` разделяет логическое ожидание sync-ответов
и фактически выполняющиеся асинхронные участки. Оба используют соответствующий
kind (`contactSync` или `channelSync`), поэтому счётчик одного kind может быть
больше единицы. Он считает удержания работы, а не число синхронизаций.

Контакты учитываются во время подготовки/записи запроса и отдельно до END,
прежнего idle timeout, ошибки запуска или reset. Незапрошенный START создаёт
ожидание; повторный START переустанавливает прежний таймер без нового удержания.
Ранний END или reset не завершают ещё выполняющийся async-участок/physical writer.

У каналов ожидание охватывает слоты, исходные retry и отложенный force restart.
Обработка ответа, перезапуск и финализация имеют независимые async-удержания.
Reconcile, image stamp и saveChannels остаются учтёнными до завершения исходных
Future, в том числе после reset/dispose. При нормальном окончании контактов
или каналов ожидающая очередь сообщений начинает свой учёт до снятия прежнего
ожидания. Завершение токена старой фазы не освобождает новый токен.

Это наблюдение за прежним алгоритмом: его гонки, ошибки и незавершённые фазы
не исправляются счётчиком. Не ожидаемые обработчиками записи, deferred replay,
непустой кэш/миграции и handshake ещё требуют отдельного охвата. Новых таймеров,
изменений протокола, CPU/Wi-Fi lock, heartbeat или пользовательских параметров нет.

Отдельные регрессии проверяют счётчики, исходный baseline остаётся прежним:

```powershell
$syncWorkTests = @(
  'test/helpers/sync_background_work_test.dart'
  'test/connector/contact_channel_sync_baseline_test.dart'
  'test/connector/contact_channel_sync_work_tracking_test.dart'
  'test/connector/contact_push_codes_test.dart'
  'test/connector/queued_message_request_work_tracking_test.dart'
  'test/connector/queued_message_notifications_test.dart'
)
flutter test @syncWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `syncWorkTests` после исправления ожидания
позднего dispatch: новый кадр после dispose по-прежнему вызывает StateError
закрытого RX stream. Продолжение уже начатой финализации — отдельный случай.

## Baseline подготовки исходящей отправки

Перед подключением общего учёта проверен участок до первой записи в транспорт
и до окончания `sendMessage`/`sendChannelMessage`. Ранее его видел только
существующий владелец `RadioStatsSendPolling`.

В `test/connector/radio_send_preparation_baseline_test.dart` подготовлены
12 сценариев с настоящими send-методами, sendFrame и владельцем polling.
Проверяются ожидание async-подготовки direct, пересечение двух операций,
ошибки подготовки/записи, внешний timeout, отключение и dispose во время
подготовки, пустые/offline вызовы и повтор при неготовой сессии. У каналов
проверяются обычные scope → text ACK → scope reset и ошибка первого scope.
Физическая запись синтетическая; ACK подаётся через настоящий входящий dispatch.

Готовность сессии подменена, node scope не привязан, SQLite не открывается.
Async preparer direct можно удержать; реальная подпись/контейнеры и аппаратная
доставка этим тестом не проверяются. Retry service, реакции, изображения,
отложенные отправки, последующие повторы и сохранение истории остаются отдельными
участками. На этапе baseline рабочий код не менялся; владелец подтвердил пакет
ниже, после чего подключён учёт активной отправки.

```powershell
$sendBaselineTests = @(
  'test/connector/radio_send_preparation_baseline_test.dart'
  'test/helpers/radio_stats_send_polling_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/channel_resend_warning_test.dart'
)
flutter test @sendBaselineTests --reporter expanded
flutter analyze
```

## Учёт активной исходящей отправки

`helpers/radio_send_background_work.dart` объединяет новый lease `radioSend`
с прежним `RadioStatsSendPolling.run`. Он подключён к двум существующим
точкам входа `sendMessage`/`sendChannelMessage`, без изменения их callback.
Удержание начинается до подготовки и живёт до завершения исходного send-Future:
успешного, с ошибкой или с предусмотренным алгоритмом ранним возвратом.

Несколько отправок получают отдельные leases. Смена состояния polling не
сбрасывает общий учёт. Внешний timeout вызывающего кода не завершает исходную
операцию. У каналов существующие ожидания scope/text ACK и scope reset входят
в активную отправку. Если исходный send уже завершился по write timeout,
продолжающийся физический I/O по-прежнему учитывается отдельным `transportWrite`.

Dispose не освобождает незавершённую отправку. После закрытия tracker поздний
вызов идёт прежним кодом/polling без новой регистрации. Tombstone ожидавшей
команды не продлевает `radioSend` после её исходного timeout.

Удержание описывает активный вызов send, а не всю последующую жизнь сообщения.
Ожидания повторов после возврата send, отдельные scheduled/deferred sends
и не ожидаемые записи требуют собственного учёта; direct retry подключён ниже.
Таймеры, протокол, служба/CPU/Wi-Fi/heartbeat и четырнадцать параметров прежние.

Принятый baseline сохранён, счётчики проверяются отдельными регрессиями:

```powershell
$sendWorkTests = @(
  'test/helpers/radio_send_background_work_test.dart'
  'test/connector/radio_send_preparation_baseline_test.dart'
  'test/connector/radio_send_work_tracking_test.dart'
  'test/helpers/radio_stats_send_polling_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/channel_resend_warning_test.dart'
)
flutter test @sendWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `sendWorkTests`.

## Baseline очереди direct ACK/retry

`radioSend` не описывает всю жизнь сообщения: `sendMessageWithRetry` ставит
его в очередь и возвращается, пока внутренний радио-callback ещё выполняется.
Далее отдельно существуют очередь, ожидание SENT/ACK и backoff повторной попытки.
После последней неудачи сообщение остаётся доступным для позднего ACK ещё
60 секунд. `pendingMessageCount` включает такие failed-записи, поэтому его
нельзя напрямую превращать в счётчик активных операций или разрешение сна.

В `test/services/retry_lifecycle_baseline_test.dart` подготовлены 13 сценариев
настоящего retry-сервиса с синтетическими callbacks и управляемыми таймерами:
перекрытие enqueue/radio-Future, последовательность по контакту и шесть общих
слотов, ACK/backoff, переиспользование failed-слота и поздний ACK, pause/resume,
отмена во время радио/смены маршрута, dispose и отсутствие SENT.
Отдельно фиксируется прежний крайний случай: pause отменяет cleanup failed grace,
а resume не восстанавливает этот таймер для уже разрешённого сообщения.

В фикстуре выбраны две попытки и configured delivery/SENT fallback 1/5 с;
это входные данные теста, а не новые defaults приложения. Первый backoff и
grace используют прежние значения сервиса. Пакет не проверяет физическую
доставку, сохранение истории, реальную подпись или канальные повторы. Виртуальное
время продвигает таймеры; это не аппаратное измерение wall-clock ACK-retention.
На этапе baseline рабочий код не менялся. Владелец подтвердил пакет ниже;
после этого подключён общий учёт direct retry.

```powershell
$retryBaselineTests = @(
  'test/services/retry_lifecycle_baseline_test.dart'
  'test/services/message_retry_failure_test.dart'
  'test/services/direct_route_attempts_test.dart'
  'test/connector/radio_send_work_tracking_test.dart'
)
flutter test @retryBaselineTests --reporter expanded
flutter analyze
```

## Учёт direct ACK/retry

`helpers/retry_background_work.dart` регистрирует два независимых вида удержаний
одного kind `retry`: логическое ожидание каждого неразрешённого сообщения
в очереди/SENT/ACK/backoff и фактическое выполнение `_attemptSend`.
Счётчик может быть больше числа сообщений. Коннектор передаёт свой реестр через
необязательный `RetryServiceConfig.backgroundWorkTracker`; без него сервис
сохраняет прежнее выполнение без регистрации.

Логические ожидания снимаются при resolve/cancel/cleanup и pause. При resume
восстанавливаются только неразрешённые сообщения, включая очередь за пределами
активных слотов. Failed/delivered и пассивный grace не создают ожидание.
Повторный initialize синхронизирует ожидания без дубликатов; смена реестра
переносит логические удержания, а начатые попытки завершаются в исходном реестре.

Отмена, pause или dispose не снимают удержание реально выполняющегося radio/path
Future. Оно освобождается через finally исходной попытки. Dispose сервиса
снимает только его логические ожидания и не закрывает общий реестр коннектора.
После close новые удержания не создаются, прежние callbacks идут своим путём.

Прежние таймеры, очереди, ACK hashes, backoff, grace и крайний случай pause/grace
сохранены. `pendingMessageCount` и владелец опроса радиостатистики тоже прежние:
новый учёт сам по себе не прекращает их удержание из-за failed-записей.
Канальные повторы, scheduled/deferred sends и не ожидаемые callback записи
или очистка маршрута ещё требуют отдельного охвата. CPU/Wi-Fi/heartbeat и
пользовательские параметры не изменены; пустой снимок по-прежнему не разрешает сон.

Принятый baseline сохранён, новые счётчики проверяются отдельно:

```powershell
$retryWorkTests = @(
  'test/helpers/retry_background_work_test.dart'
  'test/services/retry_lifecycle_baseline_test.dart'
  'test/services/retry_work_tracking_test.dart'
  'test/connector/retry_work_binding_test.dart'
  'test/services/message_retry_failure_test.dart'
  'test/services/direct_route_attempts_test.dart'
  'test/connector/radio_send_work_tracking_test.dart'
)
flutter test @retryWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `retryWorkTests`.

## Baseline канальных повторов и исходящей очереди

В `test/connector/outgoing_queue_lifecycle_baseline_test.dart` подготовлены
19 сценариев перед подключением самостоятельного учёта hop-loop, scheduled
commit и deferred flush. Используются настоящие очереди, таймеры и send-методы;
физический writer отвечает синтетическими OK и ответом default flood scope
через стандартный входящий dispatch.

После ошибок deferred-сценариев фикстура явно разделяет запрос default
scope и ответ ноды. До ответа проверяется наличие ровно одного запроса и
отсутствие TX. Два отдельных сценария проверяют обычный и ранний ответ внутри
writer; в повторном логе они тоже не завершились после одного `pump`.
В рабочем методе `finally` ждёт отмены broadcast-подписки, для которой Dart
возвращает общий Future из корневой Zone. Поэтому fixture теперь использует
`pump`, один проход реального event loop через `runAsync`, затем
`pump(Duration.zero)`. Отдельно проверяется, что виртуальное время не продвинулось
к command timeout. Проверки ответа, текста, статуса, порядка и отсутствия
повторного flush сохранены. Поправка ещё ожидает прогона владельцем;
рабочий метод и алгоритм очереди не менялись.

Канальные сценарии фиксируют deadline, ожидание resend-callback, ошибку повтора,
disconnect, failed/удалённое сообщение и независимость двух циклов. Disconnect
или удаление записи не отменяют уже запущенный resend-Future. После раннего
эхо исходный delayed Future из Future.any может оставаться до своего срока.

Scheduled-сценарии проверяют нулевую задержку до resume, положительный таймер,
неготовую сессию на его границе, возврат черновика при отмене, commit direct и
непрерываемый writer, отсутствие живого channel slot и coalescing повторного
resume во время channel commit. Deferred-сценарии проверяют END_OF_CONTACTS
как триггер, последовательную отправку двух сообщений, отсутствие дублей
при повторном END и сохранение очереди до connected-триггера.

Fixture использует mock preferences, запрет desktop support directory и
синтетическую готовность сессии; нода/SQLite/реальная подпись не подключены.
Пять секунд hop delay — выбранная настройка fixture. Виртуальные таймеры не
являются проверкой wall-clock перепланирования положительного sendAt после
сна/перезапуска. Ошибки deferred flush и reconnect replay требуют отдельного
покрытия. При подготовке baseline рабочий код и ранее принятые тесты не менялись.

```powershell
$outgoingBaselineTests = @(
  'test/connector/outgoing_queue_lifecycle_baseline_test.dart'
  'test/connector/channel_resend_warning_test.dart'
  'test/connector/radio_send_work_tracking_test.dart'
  'test/services/retry_work_tracking_test.dart'
)
flutter test @outgoingBaselineTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `outgoingBaselineTests` после поправки root Zone.

## Учёт канальных повторов и выполнения исходящей очереди

`lib/helpers/outgoing_queue_background_work.dart` удерживает исходные Future:

- `retry` — весь hop-loop, включая ожидание эхо/deadline и resend-callback.
  Раннее достаточное эхо завершает удержание вместе с loop, хотя проигравший
  delayed Future из `Future.any` ещё может ждать своего срока. Disconnect,
  удаление записи и отмена не завершают уже запущенный callback.
- `radioSend` — contact/channel commit, `resumePendingOutgoingMessages`,
  deferred flush, отдельная deferred отправка и replay retriable-очереди.
  Входят подготовка региона, ожидание command lock, scope/text ACK и reset,
  пока их ждёт исходный callback.

Вложенные Future учитываются отдельно: resume, commit, обычный send и writer
могут одновременно держать разные leases. Counts не равны числу сообщений.
После прежнего write timeout логическая операция может завершиться, тогда
незавершённый физический writer остаётся отдельным `transportWrite`.

Ожидание назначенного времени scheduled-сообщения и очередь до sync/connected
триггера сами удержаний не создают. Для сна в будущем понадобятся отдельные
гарантии пробуждения и deadlines. Закрытие реестра не сбрасывает активную работу;
поздние callbacks сохраняют прежнее поведение без новых удержаний.

Учёт наблюдательный при всех профилях. Тела семи операций, таймеры, отмена,
guard/order/ACK и polling сохранены; новых UI notify нет. Это ещё не подключение
CPU/Wi-Fi/service/heartbeat и не измеренная экономия.

Подготовлены 15 connector-регрессий и шесть helper-тестов. Проверяются удержания
hop-loop/параллельных повторов/ошибки/удаления, переключение профилей,
passive wait, timer commit/write timeout/dispose, вложенный channel resume,
missing-channel return и deferred scope/order/повторный END/connected trigger.
Принятый baseline не переписан. Реальные SQLite/подпись/доставка и отдельные
ошибки deferred/reconnect replay остаются вне этой фикстуры. Пакет проверки:

```powershell
$outgoingWorkTests = @(
  'test/helpers/outgoing_queue_background_work_test.dart'
  'test/connector/outgoing_queue_lifecycle_baseline_test.dart'
  'test/connector/outgoing_queue_work_tracking_test.dart'
  'test/connector/channel_resend_warning_test.dart'
  'test/connector/radio_send_work_tracking_test.dart'
  'test/services/retry_work_tracking_test.dart'
  'test/connector/contact_channel_sync_work_tracking_test.dart'
)
flutter test @outgoingWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `outgoingWorkTests`.

## Baseline передачи изображений

Следующая граница — исходный Future `sendImageChunks`: он включает ожидание
общего scope lock, приём команд нодой, паузы между чанками и reset scope.
Ранее подключённый `transportWrite` описывает отдельную запись, но не всю
операцию между записями. На baseline-этапе `imageTransfer` ещё не был подключён.

В `test/connector/image_send_lifecycle_baseline_test.dart` подготовлены
16 сценариев текущего поведения: пустой/неподдерживаемый/отключённый транспорт,
байты и порядок двух чанков, точная межчанковая пауза, отдельные scope/chunk/reset
ACK, ранний ACK при незавершённом writer, ошибки команды/записи, timeout и поздний
ответ, disconnect, сериализация двух изображений, ошибка progress-callback,
caller timeout и dispose.

Фикстура использует настоящий `sendImageChunks` и ACK dispatch; связь,
capability и writer синтетические. Межчанковые две секунды — входное значение
теста. Содержимое blobs синтетическое; кодирование, модель, реальная прошивка,
радиодоставка и RX reassembly этой фикстурой не проверяются. Код wire/кодеков
и ранее принятые тесты не редактировались.

По текущему коду проверка связи стоит до межчанковой задержки: разрыв до
следующей итерации возвращает false, а разрыв внутри задержки может привести
к исключению из `sendFrame`. Начальная scope-ошибка возникает до `try/finally`
action, поэтому reset не отправляется. Baseline сохраняет эти различия,
а также поглощение позднего ACK tombstone после timeout; изменения поведения
при подготовке baseline не вносились.

```powershell
$imageSendBaselineTests = @(
  'test/connector/image_send_lifecycle_baseline_test.dart'
  'test/image_chunk_transport_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/outgoing_queue_work_tracking_test.dart'
)
flutter test @imageSendBaselineTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `imageSendBaselineTests`.

## Учёт исходной передачи изображения

`lib/helpers/image_transfer_background_work.dart` оборачивает весь исходный
`sendImageChunks` как `imageTransfer`. Сюда входят ожидание общего scope lock,
передача чанков, паузы между ними и ожидаемые ACK/reset. Пока предыдущая картинка
занимает lock, следующая имеет отдельное удержание. Счётчик описывает
незавершённые вызовы, а не подтверждённую доставку изображения.

`imageTransfer`, `commandReply` и `transportWrite` учитываются независимо.
Внешний timeout вызывающего не завершает исходную передачу. После прежнего
write timeout она может завершиться с ошибкой после reset, а исходный writer
останется учтён до настоящего завершения. Dispose закрывает реестр без сброса
начатой работы; поздние callbacks сохраняют прежний путь без новых leases.

Тело `sendImageChunks` не редактировалось. Сохраняются байты, pacing/progress,
guard/ACK/reset и различия false/exception из принятого baseline. Учёт работает
наблюдательно при всех профилях; настройки, CPU/Wi-Fi/service/heartbeat и polling
не менялись. Это не замер энергии и не разрешение отпускать CPU по снимку.

В отдельных регрессиях подготовлены 16 connector-сценариев и шесть helper-тестов:
межчанковая пауза/Off, ACK/reset, held writer/ранний ACK, параллельные картинки
и caller timeout, write/ACK timeout и tombstone, dispose/late call, ошибки,
disconnect, смена профилей и early returns. Принятый baseline сохранён.
Фикстура без настоящей ноды/кодека/модели/диска; очередь `ImageChunkTransport`,
подготовка/декодирование и RX reassembly ещё требуют своих границ учёта.
Пакет ожидает проверки владельцем:

```powershell
$imageSendWorkTests = @(
  'test/helpers/image_transfer_background_work_test.dart'
  'test/connector/image_send_lifecycle_baseline_test.dart'
  'test/connector/image_send_work_tracking_test.dart'
  'test/image_chunk_transport_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/outgoing_queue_work_tracking_test.dart'
)
flutter test @imageSendWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `imageSendWorkTests`.

## Baseline сохранения истории

Следующий участок — фактический Future записи истории. Обработка RX и активная
отправка уже учитываются, но отдельная запись может продолжаться после возврата
их callback, особенно при `awaitPersistence: false` или `unawaited`. Для неё
нужна собственная граница; на baseline-этапе `persistence` ещё не был подключён.

В `test/storage/history_persistence_lifecycle_baseline_test.dart` подготовлены
13 сценариев. Проверяются direct/channel point writes, ожидание записи после
внешнего timeout, ошибка с сохранением identity и без преждевременных caches,
независимые записи, upsert одного сообщения без потери остальных, replace/delete/
remove, отделённый от вызывающего write, два model-store entrypoint и
некорректный/пустой ввод до DB writer.

Fixture подставляет через существующий `databaseFactory` подкласс БД с gates
перед четырьмя настоящими методами. После release выполняется обычный Drift/SQLite
в памяти; строки проверяются прямым SELECT, caches — через storage API.
Mock preferences и запрет support directory исключают реальные настройки.
Рабочие исходники, SQL, FULL/первый commit и принятые тесты не редактируются.

Это не проверка дисковой durability при обесточивании, web fallback, миграций,
alias cleanup после основной записи или всего потока RX. При отсутствии native
SQLite тесты пропускаются по принятому в storage-тестах способу; для baseline
нужен запуск этих сценариев без skip. Ожидается единый пакет:

```powershell
$historyPersistenceBaselineTests = @(
  'test/storage/history_persistence_lifecycle_baseline_test.dart'
  'test/storage/message_store_identity_test.dart'
  'test/storage/channel_message_store_identity_test.dart'
  'test/connector/queued_message_notifications_test.dart'
  'test/connector/image_send_work_tracking_test.dart'
)
flutter test @historyPersistenceBaselineTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `historyPersistenceBaselineTests`.

## Учёт записей истории

`lib/helpers/persistence_background_work.dart` учитывает исходные callbacks
`MessageHistoryStorage.setString`, `replaceString`, `deleteMessage` и `remove`
как `persistence`, до окончания DB Future и обновления caches. Это относится
также к записям через model stores и вызовам, которые никто больше не ждёт.
Внешний timeout и detach/dispose наблюдателя не завершают фактическую запись.

Storage общий для приложения, а коннектор может быть заменён. Поэтому helper
хранит выполняющиеся операции отдельно от наблюдателей. Конструктор коннектора
прикрепляет его реестр и принимает уже начатые записи; повторный attach одного
реестра не удваивает удержание. Dispose открепляет его от будущих операций,
но старые leases живут до конца своих записей. Новый коннектор видит эти записи
в своём реестре. Несколько снимков показывают одну общую работу; складывать их
counts как число независимых DB-записей нельзя.

Наблюдатель не нужен для выполнения записи: без него исходный callback
продолжается. Test-only reset storage открепляет наблюдателей, сохраняя текущие
leases до completion. Таймеров и UI notify нет. Тела четырёх операций, SQL,
FULL/первый commit, caches и прежние ошибки сохранены. Профили и управление
CPU/Wi-Fi/service/heartbeat/polling не менялись.

Подготовлены 15 SQLite-регрессий и 10 helper-тестов. Проверяются point writes,
ошибки/timeout/detached/parallel, replace/delete/remove, model stores и очистка
связанного direct-ключа после основной записи, принятие старого write новым
коннектором и завершение holds после dispose. Принятые тесты сохранены.
Другие операции БД, миграции/maintenance, чтения, web и disk durability этим
пакетом не проверяются. Реестр всё ещё неполон и не разрешает отпускать CPU.
Ожидается пакет, SQLite-часть — без skip:

```powershell
$persistenceWorkTests = @(
  'test/helpers/persistence_background_work_test.dart'
  'test/storage/history_persistence_lifecycle_baseline_test.dart'
  'test/storage/history_persistence_work_tracking_test.dart'
  'test/storage/message_store_identity_test.dart'
  'test/storage/channel_message_store_identity_test.dart'
  'test/connector/queued_message_notifications_test.dart'
  'test/connector/image_send_work_tracking_test.dart'
)
flutter test @persistenceWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `persistenceWorkTests`.

## Baseline уведомлений

Следующая граница — фактическая подготовка и показ уведомления. Public Future
у разных методов различается: direct/channel notification возвращается раньше
окончания показа, немедленный advert и activity summary ждут native show.
На этапе baseline самостоятельный `notification` hold ещё не подключался;
RX/очередь не менялись. Пакет ниже принят владельцем перед интеграцией учёта.

В `test/services/notification_lifecycle_baseline_test.dart` подготовлены
22 сценария: suppression, ранний возврат и awaited show, тихие обновления,
batch одного/двух adverts на границе пяти секунд, граница rate limit три секунды,
caught native errors, отказ разрешения, cancel/cancelAll/clear contact/channel,
own reply и failed reply. Фиксируется текущая особенность: suppression очищает
pending batch, а cancelAll его сохраняет до срабатывания прежнего таймера.

В сервис добавлен только тестовый setter часов rate limiter. По умолчанию
используется `DateTime.now`, reset восстанавливает его. Подменены два обращения
к часам; таймеры, порядок вызовов, ошибки и остальные тела методов сохранены.
Тесты используют настоящую логику сервиса и Android plugin через mock channel;
реального показа, сети, файлов изображений и разрешений ОС нет. Mock prefs и
запрет support directory исключают чтение настоящих настроек; portable identity
не используется. Headless Linux без D-Bus пропускает эту группу, поскольку
сам сервис блокирует initialization на таком host. Пропуск baseline не проверяет.

Это не проверка нативных Android/iOS/desktop уведомлений, URL/MCOimg подготовки,
background action isolate или badge API. Принятый пакет:

```powershell
$notificationBaselineTests = @(
  'test/services/notification_lifecycle_baseline_test.dart'
  'test/connector/queued_message_notifications_test.dart'
  'test/services/notification_reply_test.dart'
  'test/storage/history_persistence_work_tracking_test.dart'
)
flutter test @notificationBaselineTests --reporter expanded
flutter analyze
```

## Учёт фактической работы уведомлений

`NotificationBackgroundWork` оборачивает исходные callbacks подготовки и показа,
activity summary, own/failed reply и cancel/clear как `notification`. Начало
подготовки учитывается до разрешений, изображений и native show; окончание —
после завершения исходного callback. Detached direct/channel show удерживается
независимо от раннего возврата public Future. Прежние caught show errors и
пробрасываемые cancel errors сохраняются; внешний timeout не завершает работу.

Singleton-сервис хранит операции независимо от наблюдателей. Коннектор при
создании принимает уже начатые операции; detach/dispose снимает будущие
регистрации, сохраняя начатые удержания до фактического завершения. Новый
коннектор видит ещё выполняющуюся работу; повторный attach не удваивает lease.
Test reset снимает bindings без обнуления выполняющихся операций.

Пять секунд пассивного ожидания advert batch не создают удержания. Когда
таймер запускает show/summary, учитывается выполнение этого callback. Сохраняются
трёхсекундный rate limit, тихие обновления и различие suppression/cancelAll:
последний по-прежнему не убирает уже ожидающий advert batch.

Подготовлены 27 service-регрессий и 10 helper-тестов отдельно от принятого
baseline. Они используют mock native channels, управляемые Futures и виртуальные
часы. Покрываются preparation/permission, early return, show/error/cancel/reply,
batch, parallel, timeout, reset и late attach/dispose/replacement. Это состав
подготовленных сценариев, а не результат запуска.

Самостоятельный badge API, другие show entrypoints, background action isolate
и underlying URL/image I/O, продолжающийся после прежнего timeout, требуют
отдельного охвата. Тесты не проверяют фактические уведомления ОС/URL/MCOimg;
на headless Linux без D-Bus группы сервиса пропускаются. Snapshot по-прежнему
не разрешает отпускать CPU; измеренной экономии этот шаг не доказывает.

Пакет для проверки владельцем (notification-группы и SQLite-часть без skip):

```powershell
$notificationWorkTests = @(
  'test/helpers/notification_background_work_test.dart'
  'test/services/notification_lifecycle_baseline_test.dart'
  'test/services/notification_work_tracking_test.dart'
  'test/connector/queued_message_notifications_test.dart'
  'test/services/notification_reply_test.dart'
  'test/storage/history_persistence_work_tracking_test.dart'
)
flutter test @notificationWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `notificationWorkTests` 23.10.2026.
Отдельный итог `flutter analyze`, число выполненных сценариев и сведения о
пропусках не предоставлены. Это подтверждение тестового пакета; аппаратная
проверка и замер энергопотребления остаются отдельными этапами.

## Предварительные тесты приёма и обработки изображений

Следующая граница — `ReceivedImageStore`. `ImageStreamReassembler` передаёт
outcomes и failures без ожидания их обработки. Текущий hold обработки кадра
не покрывает всё продолжение: запись bitstream/sidecar может ещё выполняться,
а завершившийся intake запускает отдельную очередь декодирования.

В `test/services/image_receive_lifecycle_baseline_test.dart` подготовлен 21
сценарий для текущей реализации: порядок bitstream/sidecar/публикации состояния,
ранний возврат intake, ожидание PNG commit, manual/automatic режимы, отсутствие
автоматического разбора старого backlog, сериализация двух изображений,
пауза в фоне и при busy encoder, отмена/готовый результат, memory pressure,
ошибки и недоступный decoder, неполная сборка/failure, внешний timeout,
dispose, отказ записи и игнорируемые outcomes. Это состав тестов, не результат
запуска. Рабочий код, wire/кодеки/дедупликация и прежние тесты не менялись.

Проверки фиксируют важные границы для будущего учёта:

- `isDecoding` может быть true при пассивной очереди в фоне или при busy encoder.
- Запрос отмены native job не завершает его Future. Уже готовые pixels
  сохраняются даже после запроса отмены при уходе в фон.
- `dispose` очищает очередь, но не отменяет уже начатую декодировку; она может
  закончить сохранение. При подключении реестра это поведение сохраняется.
- Состояние публикуется в памяти до записи sidecar; ошибка записи ловится прежним
  кодом. Тесты фиксируют существующую семантику, не меняя её.

Новая фикстура использует обычный reassembler, in-memory blobs, управляемые
decoder Futures и виртуальное время. Модель, настоящий PNG decoder, native
isolate, сеть и файловая система в ней не используются. Startup/load, paging,
удаление, outgoing registration, бюджетные гонки, FR01 и реальная отмена backend
требуют отдельного покрытия. Реестр receive/decode пока не подключён;
CPU-политика и 14 параметров энергосбережения прежние.

Предварительный пакет владельца:

```powershell
$imageReceiveBaselineTests = @(
  'test/services/image_receive_lifecycle_baseline_test.dart'
  'test/services/received_image_store_test.dart'
  'test/image_wiring_test.dart'
  'test/image_chunk_transport_test.dart'
  'test/helpers/image_reassembly_maintenance_test.dart'
  'test/services/notification_work_tracking_test.dart'
)
flutter test @imageReceiveBaselineTests --reporter expanded
flutter analyze
```

## Учёт приёма и декодирования изображений

Владелец подтвердил предварительный пакет. `ImageReceiveBackgroundWork`
учитывает исходные callbacks `handleOutcome`, `handleFailure` и активный
`_decodeOne` как `receiveAssembly`. Последний включает чтение bitstream,
декодирование, запись PNG/sidecar и ожидаемый cleanup/eviction. Отдельно
учитывается запись `decoderUnavailable` в очереди, где native job не запускается.
Тела алгоритмов и принятые тесты сохранены.

Неполная сборка после sidecar, manual backlog, очередь в фоне и ожидание busy
encoder не создают постоянных удержаний. Intake и decode могут перекрываться:
тогда у одного изображения два lease. Счётчик отражает операции, не изображения.
Прежний ранний возврат intake и ожидание requestDecode/settle сохраняются.
Запрос cancel, внешний timeout и dispose не освобождают actual callback;
результат и его запись завершаются по прежним правилам.

Store хранит операции независимо от коннектора. Привязка принимает уже начатую
работу; повторная привязка не удваивает lease. Смена store, привязка null или
dispose коннектора снимают будущие регистрации и сохраняют начатые удержания.
Новый коннектор принимает pending operations, закрытый tracker новых не получает.
В приложении `initialize` получает store при доступной image feature.

Подготовлены 21 service-регрессия и 10 helper-тестов отдельно от baseline:
bitstream/sidecar/PNG boundaries, detached app reassembler, перекрытие intake
и decode, passive queue/resume, manual retry, cancellation/готовые pixels,
memory pressure, ошибки/недоступность decoder, timeout/dispose, late binding,
смена store и коннектора. Это состав подготовленных сценариев, не результат
запуска. Сеть, модель, настоящий PNG codec/native isolate и реальные файлы в
новой фикстуре не используются; prefs подменены, support directory запрещён.

Startup/load/paging/delete, outgoing registration, отдельные записи до начала
manual decode и при memory pressure/repeat metadata, budget races, encoding,
FR01 и backend всё ещё требуют охвата. Этот шаг не меняет CPU-политику,
параметры энергосбережения и не доказывает экономию на устройстве.

Пакет владельца:

```powershell
$imageReceiveWorkTests = @(
  'test/helpers/image_receive_background_work_test.dart'
  'test/services/image_receive_lifecycle_baseline_test.dart'
  'test/services/image_receive_work_tracking_test.dart'
  'test/services/received_image_store_test.dart'
  'test/image_wiring_test.dart'
  'test/image_chunk_transport_test.dart'
  'test/helpers/image_reassembly_maintenance_test.dart'
  'test/services/notification_work_tracking_test.dart'
)
flutter test @imageReceiveWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `imageReceiveWorkTests` 23.10.2026.
Учёт остаётся наблюдательным: решение об освобождении CPU к нему не подключено.

## Предварительные тесты общего handshake

Следующий участок — запрос информации об устройстве и ожидание `SELF_INFO`.
Завершение запроса означает окончание его записей, но handshake ещё может ждать
ответа и повторять `APP_START`. В `handshake_lifecycle_baseline_test.dart`
подготовлены 22 сценария для текущего порядка команд, duplicate guard, battery
request/refresh, non-web retry 3500 мс, SELF_INFO/reset/loss, listener timeout,
location refresh, отложенного APP_START при contact sync и незавершённого writer.

Фиксируются существующие особенности: ошибка writer оставляет pending guard
до reset; ранний SELF_INFO не прерывает оставшиеся записи, после которых может
появиться retry-таймер, отменяющийся на следующем тике без передачи. Malformed
SELF_INFO освобождает location waiter по прежним правилам. Эти тесты не меняют
и не объявляют исправленными перечисленные особенности.

В коннектор добавлены только тестовые adapters к настоящим методам. Native
connect не запускается; SELF_INFO проходит обычный dispatch с синтетическими
данными по cached-пути без привязки stores к ноде и первой загрузки БД. Mock
prefs и запрет support directory исключают реальные настройки. Cleanup вызывает
настоящий reset и завершает удержанные Futures до dispose, сохраняя проверки
Flutter на pending timers. Три transport label проверяют общую non-web ветвь,
не BLE/socket/USB interop. Cold load, native connect, Web handshake и связь
полного подключения с initial sync остаются отдельными участками.

На этапе baseline `transportSetup` ещё не подключался; CPU-политика и
четырнадцать параметров энергосбережения прежние. Пакет принят владельцем:

```powershell
$handshakeBaselineTests = @(
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/contact_channel_sync_baseline_test.dart'
  'test/connector/device_polling_baseline_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
  'test/connector/queued_message_request_baseline_test.dart'
  'test/connector/frame_command_baseline_test.dart'
)
flutter test @handshakeBaselineTests --reporter expanded
flutter analyze
```

## Учёт общего handshake

Используется прежний `SyncBackgroundWork` с видом `transportSetup`.
Прежний bool awaiting-флага сохранён в backing field; accessor связывает его
изменения с одним логическим удержанием. Повторное true не удваивает фазу,
false освобождает её. Самостоятельные callbacks requestDeviceInfo,
refreshDeviceInfo, refreshSelfLocation и waitForSelfInfo имеют независимые
удержания до завершения исходных Futures.

Поэтому завершившийся запрос может оставить одно логическое ожидание ответа;
два локальных waiter добавляют ещё два удержания. Count отражает операции,
не число соединений. Ранний SELF_INFO/reset не завершают request или writer,
а local timeout/известный ключ не сбрасывают ещё установленный awaiting-флаг.
При ошибке writer прежний pending guard и его hold остаются до reset.
Retry при обнаружении потери связи и dispose снимают logical hold; настоящая
запись и локальные waiters заканчиваются по прежним правилам. Закрытый tracker
новых удержаний не получает, существующие actual leases завершаются независимо.

Команды, guard, таймеры/deadlines, обработка malformed SELF_INFO и позднего
retry после раннего ответа сохранены. Физический writer по-прежнему имеет
отдельный `transportWrite`, включая работу после внешнего write timeout.
Dispose в этой интеграции не заменяет старую очистку таймеров или native teardown.

Подготовлены 23 connector-регрессии отдельно от принятого baseline:
logical/actual/writer, duplicate/refresh/known key, независимые waiters,
ранний ответ, ошибки/loss/reset/replacement, location/malformed/timeout,
dispose/closed и contact-sync deferral. Они используют прежнюю synthetic
cached SELF_INFO fixture. Принятые семь файлов, включая шесть helper-сценариев,
не переписывались. Это состав подготовленных тестов, не результат запуска.

Native open/connect, cold DB load и его async-продолжения, полный initial sync,
Web branch и остальные владельцы реестра требуют отдельного охвата. Этот шаг
не разрешает CPU sleep, не меняет профили и не доказывает экономию энергии.

Пакет владельца:

```powershell
$handshakeWorkTests = @(
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/helpers/sync_background_work_test.dart'
  'test/connector/contact_channel_sync_baseline_test.dart'
  'test/connector/device_polling_baseline_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
  'test/connector/queued_message_request_baseline_test.dart'
  'test/connector/frame_command_baseline_test.dart'
)
flutter test @handshakeWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `handshakeWorkTests`.

## Предварительные тесты полного TCP-подключения

Следующий участок — `connectTcp`: ожидание уже начатого teardown, stopScan,
отмена прежней подписки, открытие транспорта, пауза 200 мс, установка listener,
запрос устройства/два окна SELF_INFO и запись времени. State connected может
появиться раньше завершения handshake и самого connect-Future; завершившийся
handshake ещё не означает окончания initial sync.

Подготовлены 20 сценариев: held dial/cancel/scan/teardown, точная пауза перед
handshake, ранний и поздний SELF_INFO, refresh/два timeout, writer error,
ожидание time sync, guards occupied/offline, dial failure, late error/success
после ручной отмены, отмена в паузе и при смене транспорта, неподключившийся
manager и внешний timeout. Это состав тестов, не результат запуска.

Конструктор получил optional TCP manager; обычный вызов по-прежнему создаёт
стандартный MeshCoreTcpConnector. Алгоритм connect/teardown не менялся.
Фикстура выполняет настоящий connectTcp и teardown: TCP manager синтетический,
USB/BLE не открываются. StopScan и default-region query изолированы, prefs
подменены и support directory запрещён. SELF_INFO проходит dispatch через
зарегистрированный callback по прежнему cached-пути без первой загрузки БД.
Cleanup снимает synthetic offline-флаг без входа в настоящую историю и выполняет
manual teardown перед dispose. Нативное закрытие USB/BLE не изменено.

Сокеты, framing, overlay/native lifetime, Web, холодный storage и полный
initial pipeline остаются за пределами новой фикстуры; native transport tests
включены соседним файлом в пакет. На этапе baseline общий handshake/writer
уже учитывался, самостоятельного hold всего connectTcp ещё не было. CPU-политика и 14 параметров
энергосбережения прежние.

Предварительный пакет владельца:

```powershell
$tcpConnectBaselineTests = @(
  'test/connector/tcp_connect_lifecycle_baseline_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/connector/meshcore_connector_tcp_error_filter_test.dart'
  'test/screens/tcp_flow_test.dart'
  'test/services/tcp_transport_service_native_test.dart'
)
flutter test @tcpConnectBaselineTests --reporter expanded
flutter analyze
```

## Учёт полного TCP-подключения

Владелец подтвердил прохождение `tcpConnectBaselineTests`. Исходный baseline
сохранён. `connectTcp` обёрнут в прежний `SyncBackgroundWork` с видом
`transportSetup`; его исходное тело не изменено. Удержание начинается до
ожидания старого teardown и живёт до завершения connect-Future: stopScan,
отмена подписки, dial, пауза 200 мс, handshake, запись времени и ожидаемый
cleanup при ошибке или отмене входят в эту границу.

Логическое ожидание SELF_INFO и фактические request/wait/write остаются
самостоятельными операциями. Ручная отмена, reset, dispose или timeout
вызывающего кода не завершают ещё работающий connect. После write timeout
connect может закончиться, а фактический writer продолжит учитываться
отдельно. Закрытый реестр не принимает новые удержания; прежние освобождаются
по завершении своих операций. Guarded early return не оставляет удержания.

Подготовлены 22 отдельных регрессионных сценария: ожидания scan/subscription/
dial/старого teardown, задержка и handshake, held writer и time sync,
late success/error после отмены, cleanup, смена транспорта, внешний timeout,
guards/duplicate и dispose. Это состав тестов, не результат запуска.
Фикстура использует синтетический TCP manager и настоящий connect/teardown;
реальные sockets/overlay, Web, холодный storage и полный initial pipeline
требуют отдельного охвата. Unawaited default-region refresh не входит в
завершившийся connect-Future. Учёт остаётся наблюдательным при всех профилях;
CPU/Wi-Fi/service/heartbeat и 14 настроек не изменены. Пустой снимок пока
не разрешает отпускать CPU lock, аппаратная экономия не измерена.

Пакет владельца:

```powershell
$tcpConnectWorkTests = @(
  'test/connector/tcp_connect_lifecycle_baseline_test.dart'
  'test/connector/tcp_connect_work_tracking_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/connector/meshcore_connector_tcp_error_filter_test.dart'
  'test/screens/tcp_flow_test.dart'
  'test/services/tcp_transport_service_native_test.dart'
)
flutter test @tcpConnectWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `tcpConnectWorkTests`.

## Предварительные тесты полного USB-подключения

Общий handshake уже учитывается, но самостоятельное удержание всего
`connectUsb` пока не добавлено. Сначала подготовлены 20 baseline-сценариев:
ожидание stopScan/открытия/старого teardown, пауза 200 мс, connected до SELF_INFO,
refresh и два окна timeout, ошибки writer/открытия/потери порта, запись времени,
guards/duplicate/caller timeout, отмена в паузе, stream error/done и порядок
отмены подписки перед manager close. Это состав тестов, не результат запуска.

Конструктор получил optional `usbManager`; обычный вызов создаёт прежний
MeshCoreUsbManager. Алгоритмы connectUsb/disconnect и нативное закрытие USB
сохранены. В отличие от ограниченных cleanup-шагов, manager close продолжает
ожидаться без внешнего deadline: нативный код владеет FFI-callback. Два
сценария удерживают синтетическое закрытие восемь секунд, проверяя отсутствие
нового timeout на уровне коннектора. Это не замер настоящего native close.

Новый fake реализует интерфейс manager без создания UsbSerialService/flserial;
реальные порты и BLE не открываются. Настоящие connectUsb/dispatch/handshake/
teardown работают с synthetic SELF_INFO по cached-пути; prefs подменены,
support directory запрещён. StopScan и default-region query изолированы.
Реальные FFI/permission/framing/Web/cold storage, полный initial pipeline и
позднее успешное открытие после отмены остаются отдельными границами.
CPU-политика и четырнадцать параметров энергосбережения прежние.

Предварительный пакет владельца:

```powershell
$usbConnectBaselineTests = @(
  'test/connector/usb_connect_lifecycle_baseline_test.dart'
  'test/connector/tcp_connect_lifecycle_baseline_test.dart'
  'test/connector/tcp_connect_work_tracking_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/screens/usb_flow_test.dart'
  'test/services/usb_serial_frame_codec_test.dart'
)
flutter test @usbConnectBaselineTests --reporter expanded
flutter analyze
```

## Учёт полного USB-подключения

Владелец подтвердил прохождение `usbConnectBaselineTests`; принятый файл
сохранён. Весь `connectUsb` обёрнут в существующий `SyncBackgroundWork` с
видом `transportSetup`. Удержание живёт до завершения исходного connect-Future:
ожидание старого teardown/stopScan/открытия, пауза, handshake, запись времени
и ожидаемый cleanup при ошибке входят в эту границу. Тело алгоритма сохранено.

Логическое ожидание SELF_INFO, actual request/wait и transportWrite независимы.
Reset, ручной disconnect, dispose и внешний timeout вызывающего кода не
освобождают незавершённый connect. После write timeout connect может закончиться,
а фактический writer остаётся учтённым до своего завершения. Закрытый реестр
новых удержаний не принимает, прежние завершаются через finally.

Подготовлены 22 регрессионных сценария: scan/open/200 мс, handshake/reset,
оба окна SELF_INFO, time writer/error, held writer/cancel, потеря порта,
write/caller timeout, guards/duplicate/dispose/closed и длительное ожидание
USB close. Это состав новых тестов, не результат запуска. Фикстура не создаёт
UsbSerialService/flserial и не открывает реальные порты. Алгоритм native close
и ожидание FFI join без внешнего deadline не изменены.

Unawaited default-region refresh, полный initial pipeline и disconnect после
ошибки уже установленного соединения не входят в завершённый connect-Future.
Последний случай имеет отдельную регрессию: новый setup lease не появляется
во время позднего cleanup. На этапе USB учёт teardown ещё не был подключён; пустой
snapshot по-прежнему не разрешает отпускать CPU lock. Реальные FFI/Web/cold
storage, поздний USB open после отмены и другие владельцы требуют охвата.
CPU/Wi-Fi/service/heartbeat и четырнадцать параметров пока прежние.

Пакет владельца:

```powershell
$usbConnectWorkTests = @(
  'test/connector/usb_connect_lifecycle_baseline_test.dart'
  'test/connector/usb_connect_work_tracking_test.dart'
  'test/connector/tcp_connect_lifecycle_baseline_test.dart'
  'test/connector/tcp_connect_work_tracking_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/screens/usb_flow_test.dart'
  'test/services/usb_serial_frame_codec_test.dart'
)
flutter test @usbConnectWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `usbConnectWorkTests`.

## Предварительные тесты самостоятельного отключения

Следующий пробел — disconnect, выполняющийся после уже завершённого connect.
Подготовлены 20 baseline-сценариев в `disconnect_lifecycle_baseline_test.dart`.
Коннектор и ранее принятые тесты на этом шаге не менялись.

Проверяются объединение параллельных вызовов в один teardown, приоритет
ручного запроса над автоматическим, порядок USB → TCP → translation →
cancel/release image, reconnect tail для TCP и его отсутствие для USB,
ошибки close и повторная попытка после них, внешний caller timeout,
ожидания моделей и независимые трёхсекундные cleanup-deadlines. Поздний
результат старого release не должен продолжать прежний teardown или влиять
на следующий. Это состав подготовленных тестов, не результат запуска.

Синтетический USB close ожидается восемь секунд без внешнего timeout;
синтетический TCP manager также управляется gate, чтобы проверить ожидание
его Future коннектором. Это не проверка native FFI или реального socket close:
настоящий TCP manager сохраняет собственную ограниченную очистку, USB —
прежнее ожидание native join. BLE в новом файле проверяется только как
transport label с пустым device; настоящие BLE/iOS callbacks требуют
аппаратного охвата. Соседний disconnect_cleanup_test контролирует ответ
iOS MethodChannel. Review/offline storage не открываются. Preferences
подменены, support directory запрещён, модели заменены fake release.

На этапе baseline самостоятельный teardown и actual cleanup после timeout
ещё не были добавлены в реестр. Пустой snapshot не разрешает отпускать CPU lock; CPU/Wi-Fi/service/
heartbeat и четырнадцать параметров прежние.

Предварительный пакет владельца:

```powershell
$disconnectBaselineTests = @(
  'test/connector/disconnect_lifecycle_baseline_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/helpers/connection_cleanup_test.dart'
  'test/connector/usb_connect_work_tracking_test.dart'
  'test/connector/tcp_connect_work_tracking_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
)
flutter test @disconnectBaselineTests --reporter expanded
flutter analyze
```

## Учёт teardown и незавершённого cleanup

Владелец подтвердил прохождение `disconnectBaselineTests`. Новый
`ConnectionTeardownBackgroundWork` учитывает весь исходный Future
`_disconnectInternal` как `transportTeardown`. Параллельные вызовы по-прежнему
присоединяются к одному teardown, ручное отключение сохраняет приоритет.
Caller timeout не снимает удержание выполняющейся операции.

`ConnectionCleanup` получил optional `runAction`; без него выполняется прежний
код. Коннектор передаёт `work.cleanup`: action вызывается синхронно внутри
независимого удержания, null возвращается как прежде, синхронная ошибка
передаётся исходному обработчику. Возвращённый Future учитывается ниже timeout.
Если три секунды истекли, teardown может закончиться, а actual release/отмена
подписки/platform reply продолжит учитываться до своего завершения. Поздний
результат освобождает своё удержание и не возобновляет старый teardown.

`close` реестра запрещает новые удержания, сохраняя старые до завершения.
Порядок USB/TCP/models, deadlines и ожидание native USB join не изменены.
Manager close входит в полный teardown; внутренний I/O за пределами Future
manager этим не доказывается. Реальные FFI/streams, review/offline storage и
неохваченные владельцы остаются отдельными границами.

Подготовлены 16 connector-регрессий и восемь helper-тестов, включая coalescing,
errors/caller timeout, отдельные release после timeout, старую и новую операции,
dispose и задержанный ответ iOS MethodChannel. Это состав новых тестов,
не результат запуска. Принятый lifecycle baseline сохранён. В двух прежних
TCP/USB tracking-тестах уточнена сумма activeCount: новый teardown считается
отдельно; прежние setup/write ожидания сохранены. Поздний USB stream error
теперь явно ожидает один teardown и ноль setup.

Учёт наблюдательный при всех профилях. CPU/Wi-Fi/service/heartbeat и
четырнадцать настроек прежние; пустой snapshot пока не разрешает сон.

Пакет владельца:

```powershell
$disconnectWorkTests = @(
  'test/connector/disconnect_lifecycle_baseline_test.dart'
  'test/connector/disconnect_work_tracking_test.dart'
  'test/connector/disconnect_cleanup_test.dart'
  'test/helpers/connection_cleanup_test.dart'
  'test/helpers/connection_teardown_background_work_test.dart'
  'test/helpers/background_work_tracker_test.dart'
  'test/connector/usb_connect_work_tracking_test.dart'
  'test/connector/tcp_connect_work_tracking_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
)
flutter test @disconnectWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `disconnectWorkTests`.

## Предварительные тесты BLE connect: Windows-ветвь плагина

Подготовлены 20 сценариев в `ble_connect_lifecycle_baseline_test.dart`.
Выполняются настоящие connect/disconnect/handshake коннектора; Fake device,
GATT characteristics и bonded-ответ заменяют плагин/радио. StopScan и
default-region query изолированы, SELF_INFO идёт через поток characteristic
по cached-пути; prefs подменены, support directory запрещён. Полный cold
initial sync не запускается. Рабочий код и принятые тесты не изменены.

Для событий состояния и GATT используются управляемые fake Stream/Subscription
с синхронной доставкой одному слушателю. Их cancel/close завершаются в зоне
widget-теста. Обычный broadcast.cancel возвращает root-Zone Future._nullFuture;
ожидание его в FakeAsync может остановить cleanup до следующего pump.
Исправление ограничено фикстурой: assertions, интервалы и 30-секундный timeout
сценариев сохранены. Владелец подтвердил прохождение пакета после исправления.

Набор выполняется на Windows; на остальных платформах явно skipped, чтобы
не запускать Linux bluetoothctl/native iOS и не приписывать Windows-фикстуре
проверку других backend. Это не аппаратная приёмка BLE. Native iOS, Linux
pairing/recovery, Android MTU, Web и реальные stream/OS callbacks требуют
собственных проверок.

Фиксируются ожидания scan/open/discovery/CCCD, Windows-пауза 750 мс перед
CCCD, повторы CCCD через 1/2 с, очистка stale link и быстрый retry через
500 мс, timeout без немедленного retry, отсутствие NUS service/characteristic,
guards/ручная отмена/caller timeout, поздний SELF_INFO и запись времени.
Это состав подготовленных тестов, не результат запуска.

Исходное отличие BLE: после двух окон без SELF_INFO connect-Future может
завершиться без ошибки, сохранив connected и незавершённый handshake.
Новый baseline фиксирует это поведение; готовность сессии по нему не
объявляется. На этапе baseline общий handshake уже учитывался отдельно,
самостоятельного hold полного BLE connect ещё не было. CPU-политика и 14 настроек прежние.

Предварительный пакет владельца (Windows):

```powershell
$bleConnectBaselineTests = @(
  'test/connector/ble_connect_lifecycle_baseline_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/disconnect_work_tracking_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
  'test/services/linux_ble_error_classifier_test.dart'
  'test/services/ble_plugin_log_power_baseline_test.dart'
)
flutter test @bleConnectBaselineTests --reporter expanded
flutter analyze
```

## Учёт полного BLE connect

После подтверждения baseline весь `connect(BluetoothDevice)` обёрнут в
существующий `SyncBackgroundWork` как `transportSetup`. Исходное тело
алгоритма сохранено. Удержание охватывает ожидаемые scan/старый teardown,
открытие устройства, discovery, notify/retry, initial handshake, time sync
и error cleanup до завершения первоначального Future.

Логическое ожидание SELF_INFO, actual request/wait, transportWrite и
transportTeardown независимы. Manual cancel/reset/dispose/caller timeout
не освобождают незавершённый connect. Write timeout может завершить connect
раньше фактического writer; cleanup timeout — раньше фактического close,
который продолжит учитываться через teardown. После двух missing SELF_INFO
окон прежний connect может закончиться без ошибки: outer hold снимается,
logical handshake сохраняется до своего прежнего завершения/reset.

Подготовлен 21 регрессионный сценарий (16 testWidgets и циклы на четыре
boundary и три guards): scan/open/discovery/CCCD/settle delay, time writer,
independent SELF_INFO, missing SELF_INFO, caller timeout, duplicate/cancel,
retry delays, inline stale close, error cleanup/write timeout, dispose/closed.
Это состав новых тестов, не результат запуска. Принятый baseline не изменён.
Fake Stream/Subscription сохранены; native close gate добавлен только в новую
фикстуру. Она ограничена Windows и явно skipped на других платформах.

Обёртка охватывает общий entrypoint, включая ожидаемые платформенные участки;
Windows-фикстура не подтверждает native iOS/Linux pairing/recovery/Android
MTU/Web, cold initial sync или I/O за пределами ожидаемых Futures.
Unawaited default-region refresh также не становится частью connect-Future.
CPU/Wi-Fi/service/heartbeat и четырнадцать параметров прежние; snapshot пока
не разрешает отпускать CPU lock.

Пакет владельца (Windows):

```powershell
$bleConnectWorkTests = @(
  'test/connector/ble_connect_lifecycle_baseline_test.dart'
  'test/connector/ble_connect_work_tracking_test.dart'
  'test/connector/handshake_lifecycle_baseline_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/helpers/sync_background_work_test.dart'
  'test/connector/disconnect_work_tracking_test.dart'
  'test/connector/reconnect_power_baseline_test.dart'
  'test/services/linux_ble_error_classifier_test.dart'
  'test/services/ble_plugin_log_power_baseline_test.dart'
)
flutter test @bleConnectWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение `bleConnectWorkTests`.

## Baseline внешних packet/replay границ

Следующий пакет проверяет исходное поведение до добавления внешних удержаний:

- `send_frame_boundary_baseline_test.dart` — шесть сценариев: задержка перед
  writer, обработка без writer, синхронная/асинхронная ошибка, ожидание
  специфического ответа и потеря соединения перед отложенной отправкой.
- `packet_replay_lifecycle_baseline_test.dart` — одиннадцать сценариев:
  пустые очереди, выбор разрешимых отправителей, FIFO и исключения, защита
  deferred replay от повторного входа, передача управления синхронизации,
  асинхронный channel RX и direct echo, повреждённые/чужие кадры.

Это состав подготовленных тестов, а не результат запуска. Циклы replay и
RX parser/decrypt настоящие; задерживаются существующие Futures загрузки
истории и перевода. Stores не привязаны к ноде, записи пропускаются штатным
guard пустого scope. Сохранение в реальную БД эти новые сценарии не проверяют.
Все кадры и ключ direct echo синтетические. ACK этого direct echo не
отправляется: его RX проверяется при disconnected; соседние принятые тесты
сохраняются. Внешний сервис заменён Fake без вызова его конструктора.

В коннектор добавлены только `visibleForTesting` адаптеры. Рабочие sendFrame,
LOG_RX и replay пока не обёрнуты. Обычный receive использует messageSync,
но replay с `alreadyAdvancedQueueSync: true` вызывает process напрямую;
его полнота не следует из наличия общего wrapper.

Baseline также фиксирует прежние ограничения обработки ошибок: unknown
replay выбирает кадры из буфера до обработки; при ошибке загрузки оставшаяся
выбранная часть не возвращается. Deferred replay при ошибке сбрасывает флаги,
оставляет ещё не извлечённые кадры и не запускает pending sync. Здесь эти
правила не исправляются и не объявляются гарантией доставки.

Пакет владельца:

```powershell
$packetReplayBaselineTests = @(
  'test/connector/send_frame_boundary_baseline_test.dart'
  'test/connector/packet_replay_lifecycle_baseline_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/frame_work_tracking_test.dart'
  'test/connector/queued_message_processing_baseline_test.dart'
  'test/connector/queued_message_work_tracking_test.dart'
  'test/connector/channel_packet_copies_test.dart'
  'test/connector/own_message_echo_test.dart'
  'test/connector/south_frame_fragment_protocol_test.dart'
  'test/helpers/south_queued_fragment_ack_tracker_test.dart'
)
flutter test @packetReplayBaselineTests --reporter expanded
flutter analyze
```

Соседний `own_message_echo_test.dart` требует native sqlite3 и может быть
skipped при её отсутствии; это не подтверждает проверку persistence.
Владелец подтвердил прохождение `packetReplayBaselineTests` после исправления
импорта Endian и Fake. Отдельный чистый итог analyze и число выполненных/skip
сценариев в сообщении не указаны.

## Учёт внешних packet/replay границ

`PacketBackgroundWork` добавляет три вида удержаний:

| Вид | Граница |
|---|---|
| `frameDispatch` | `sendFrame` до вызова внешнего перехватчика и до конца возвращённого им Future; включая обработку без физического writer |
| `radioReceive` | полный async `LOG_RX`, включая awaited direct echo, verification, историю и перевод/уведомление, которые ожидает исходный обработчик |
| `messageReplay` | полный unknown-sender или deferred contact replay, включая последовательные сообщения и исходную передачу управления очереди |

Без перехватчика `sendFrame` идёт прежним путём: writer и ожидаемый reply уже
учитываются независимо. При перехватчике их удержания сосуществуют с
`frameDispatch`. Write timeout завершает внешний Future, но фактический writer
может остаться активным до собственного завершения. Не ожидаемые исходным
кодом операции не становятся частью внешнего Future автоматически.

Helper вызывает callback сразу и сохраняет синхронный throw перехватчика.
Каждый вызов имеет отдельное удержание; immutable snapshot, reset, dispose и
timeout вызывающего кода не освобождают чужую незавершённую работу. После
закрытия реестра поздний вызов сохраняет прежнее выполнение без регистрации
нового удержания. Существующие открытые удержания завершаются независимо.

Replay не меняет очереди и обработку ошибок, описанные в baseline. Кадры,
пассивно ожидающие контакта, FR01 TTL и пустые очереди не создают постоянный
busy. Пустой вызов replay/RX может кратко учитываться до завершения Future,
после чего сразу освобождается. Новых таймеров и timeout нет.

Подготовлены 37 отдельных регрессионных сценариев: 13 helper, восемь внешней
отправки и 16 RX/replay. Это состав тестов, не результаты запуска. Принятые
baseline сохранены. Ограничения синтетических fixture прежние: новые тесты
не подтверждают native доставку, реальную DB, коммерческий backend и фон ОС.

Пакет владельца:

```powershell
$packetReplayWorkTests = @(
  'test/helpers/background_work_tracker_test.dart'
  'test/helpers/packet_background_work_test.dart'
  'test/connector/send_frame_boundary_baseline_test.dart'
  'test/connector/send_frame_boundary_work_tracking_test.dart'
  'test/connector/packet_replay_lifecycle_baseline_test.dart'
  'test/connector/packet_replay_work_tracking_test.dart'
  'test/connector/frame_command_baseline_test.dart'
  'test/connector/frame_work_tracking_test.dart'
  'test/connector/queued_message_processing_baseline_test.dart'
  'test/connector/queued_message_work_tracking_test.dart'
  'test/connector/contact_channel_sync_work_tracking_test.dart'
  'test/connector/handshake_work_tracking_test.dart'
  'test/connector/channel_packet_copies_test.dart'
  'test/connector/own_message_echo_test.dart'
  'test/connector/south_frame_fragment_protocol_test.dart'
  'test/helpers/south_queued_fragment_ack_tracker_test.dart'
)
flutter test @packetReplayWorkTests --reporter expanded
flutter analyze
```

Владелец подтвердил прохождение регрессий R1. Native CPU lock, heartbeat,
транспорты и четырнадцать параметров прежние; аппаратной оценки экономии нет.
После пересмотра плана storage/disk owners (R2) и допуск режимов (R3) отложены
до аппаратных A/B. Продолжение реестра и native CPU/wake блока зависит от
измеренной пользы и проверки надёжности; сам snapshot сон пока не разрешает.
