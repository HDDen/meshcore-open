// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'MeshCore Open (Advanced mod)';

  @override
  String get nav_contacts => 'Контакты';

  @override
  String get nav_channels => 'Каналы';

  @override
  String get nav_map => 'Карта';

  @override
  String get common_cancel => 'Отмена';

  @override
  String get common_ok => 'OK';

  @override
  String get common_connect => 'Подключиться';

  @override
  String get common_unknownDevice => 'Неизвестное устройство';

  @override
  String get common_save => 'Сохранить';

  @override
  String get common_delete => 'Удалить';

  @override
  String get common_deleteAll => 'Удалить все';

  @override
  String get common_close => 'Закрыть';

  @override
  String get common_done => 'Готово';

  @override
  String get common_edit => 'Изменить';

  @override
  String get common_add => 'Добавить';

  @override
  String get common_settings => 'Настройки';

  @override
  String get common_disconnect => 'Отключить';

  @override
  String get common_connected => 'Подключено';

  @override
  String get common_disconnected => 'Отключено';

  @override
  String get common_create => 'Создать';

  @override
  String get common_continue => 'Продолжить';

  @override
  String get common_share => 'Поделиться';

  @override
  String get common_copy => 'Копировать';

  @override
  String get common_retry => 'Повторить';

  @override
  String get common_hide => 'Скрыть';

  @override
  String get common_remove => 'Убрать';

  @override
  String get common_enable => 'Включить';

  @override
  String get common_disable => 'Выключить';

  @override
  String get common_undo => 'Отменить';

  @override
  String get messageStatus_sent => 'Отправлено';

  @override
  String get messageStatus_delivered => 'Доставлено';

  @override
  String get messageStatus_pending => 'Отправка';

  @override
  String get messageStatus_failed => 'Не удалось отправить';

  @override
  String get messageStatus_repeated => 'Услышано повторение';

  @override
  String get common_reboot => 'Перезагрузить';

  @override
  String get common_loading => 'Загрузка...';

  @override
  String get common_notAvailable => '—';

  @override
  String common_voltageValue(String volts) {
    return '$volts В';
  }

  @override
  String common_percentValue(int percent) {
    return '$percent%';
  }

  @override
  String get common_autoRefresh => 'Автообновление';

  @override
  String get common_interval => 'Интервал';

  @override
  String get common_default => 'По умолчанию';

  @override
  String get common_clear => 'Очистить';

  @override
  String get common_send => 'Отправить';

  @override
  String get common_apply => 'Применить';

  @override
  String get scanner_title => 'MeshCore Open (Advanced mod)';

  @override
  String get connectionChoiceUsbLabel => 'USB';

  @override
  String get connectionChoiceBluetoothLabel => 'Bluetooth';

  @override
  String get connectionChoiceTcpLabel => 'TCP';

  @override
  String get tcpScreenTitle => 'Подключение по TCP';

  @override
  String get tcpHostLabel => 'IP-адрес';

  @override
  String get tcpHostHint => '192.168.40.10 / example.com';

  @override
  String get tcpPortLabel => 'Порт';

  @override
  String get tcpPortHint => '5000';

  @override
  String get tcpStatus_notConnected => 'Введите адрес и подключитесь';

  @override
  String tcpStatus_connectingTo(String endpoint) {
    return 'Подключение к $endpoint...';
  }

  @override
  String get tcpErrorHostRequired => 'Необходимо указать IP-адрес.';

  @override
  String get tcpErrorPortInvalid =>
      'Порт должен находиться в диапазоне от 1 до 65535.';

  @override
  String get tcpErrorUnsupported =>
      'Протокол TCP не поддерживается на этой платформе.';

  @override
  String get tcpErrorTimedOut => 'Истекло время ожидания TCP-соединения.';

  @override
  String tcpConnectionFailed(String error) {
    return 'Не удалось установить соединение TCP: $error';
  }

  @override
  String get tcpBookmarksLabel => 'Последние подключения';

  @override
  String get tcpBookmarksSetName => 'Назначить имя закладке';

  @override
  String get tcpBookmarksFavouritesSubtitle =>
      'Когда отмечена, как избранное, не удаляется из истории подключений';

  @override
  String get usbScreenTitle => 'Подключение через USB';

  @override
  String get usbScreenSubtitle =>
      'Выберите обнаруженное устройство с последовательным интерфейсом и подключите его напрямую к вашему узлу MeshCore.';

  @override
  String get usbScreenStatus => 'Выберите USB-устройство';

  @override
  String get usbScreenNote =>
      'USB-серийный порт активен на поддерживаемых устройствах Android и настольных платформах.';

  @override
  String get usbScreenEmptyState =>
      'Не обнаружено устройств USB. Подключите одно из них и обновите список.';

  @override
  String get usbErrorPermissionDenied =>
      'Запрос на доступ через USB был отклонен.';

  @override
  String get usbErrorDeviceMissing =>
      'Выбранное USB-устройство больше недоступно.';

  @override
  String get usbErrorInvalidPort => 'Выберите действительное USB-устройство.';

  @override
  String get usbErrorBusy =>
      'Другой запрос на USB-подключение уже выполняется.';

  @override
  String get usbErrorNotConnected => 'Ни одно USB-устройство не подключено.';

  @override
  String get usbErrorOpenFailed =>
      'Не удалось открыть выбранное USB-устройство.';

  @override
  String get usbErrorConnectFailed =>
      'Не удалось установить соединение с выбранным USB-устройством.';

  @override
  String get usbErrorUnsupported =>
      'Поддержка последовательного USB отсутствует на данной платформе.';

  @override
  String get usbErrorAlreadyActive => 'USB-соединение уже установлено.';

  @override
  String get usbErrorNoDeviceSelected =>
      'Не было выбрано ни одно устройство USB.';

  @override
  String get usbErrorPortClosed => 'USB-соединение не установлено.';

  @override
  String get usbErrorConnectTimedOut =>
      'Истекло время ожидания подключения. Убедитесь, что на устройстве установлена прошивка USB Companion.';

  @override
  String get usbFallbackDeviceName => 'Устройство Web Serial';

  @override
  String get usbStatus_notConnected => 'Выберите USB-устройство';

  @override
  String get usbStatus_connecting => 'Подключение к USB-устройству...';

  @override
  String get usbStatus_searching => 'Поиск USB-устройств...';

  @override
  String usbConnectionFailed(String error) {
    return 'Не удалось установить соединение через USB: $error';
  }

  @override
  String get scanner_scanning => 'Поиск устройств...';

  @override
  String get scanner_connecting => 'Подключение...';

  @override
  String get scanner_disconnecting => 'Отключение...';

  @override
  String get scanner_notConnected => 'Не подключено';

  @override
  String scanner_connectedTo(String deviceName) {
    return 'Подключено к $deviceName';
  }

  @override
  String get scanner_searchingDevices => 'Поиск устройств MeshCore...';

  @override
  String get scanner_tapToScan =>
      'Нажмите «Сканирование», чтобы найти устройства MeshCore';

  @override
  String scanner_connectionFailed(String error) {
    return 'Подключение не удалось: $error';
  }

  @override
  String get scanner_stop => 'Стоп';

  @override
  String get scanner_scan => 'Сканирование';

  @override
  String get scanner_bluetoothOff => 'Bluetooth выключен';

  @override
  String get scanner_bluetoothOffMessage =>
      'Пожалуйста, включите Bluetooth, чтобы найти устройства.';

  @override
  String get scanner_chromeRequired => 'Требуется браузер Chrome';

  @override
  String get scanner_chromeRequiredMessage =>
      'Для поддержки Bluetooth в этом веб-приложении требуется Google Chrome или браузер на базе Chromium.';

  @override
  String get scanner_enableBluetooth => 'Включите Bluetooth';

  @override
  String get scanner_bluetoothWebUnsupported =>
      'Bluetooth недоступен в браузере. Подключитесь через USB.';

  @override
  String get device_quickSwitch => 'Быстрое переключение';

  @override
  String get device_meshcore => 'MeshCore';

  @override
  String get settings_title => 'Настройки';

  @override
  String get settings_deviceInfo => 'Информация об устройстве';

  @override
  String get settings_appSettings => 'Настройки приложения';

  @override
  String get settings_appSettingsSubtitle =>
      'Уведомления, сообщения и настройки карты';

  @override
  String get settings_nodeSettings => 'Настройки ноды';

  @override
  String get settings_nodeName => 'Имя ноды';

  @override
  String get settings_nodeNameNotSet => 'Не установлено';

  @override
  String get settings_nodeNameHint => 'Введите имя ноды';

  @override
  String get settings_nodeNameUpdated => 'Имя обновлено';

  @override
  String get settings_radioSettings => 'Настройки радио';

  @override
  String get settings_radioSettingsSubtitle =>
      'Частота, мощность и коэффициент распространения';

  @override
  String get settings_radioSettingsUpdated => 'Настройки радио обновлены';

  @override
  String get settings_regionSettings => 'Регионы';

  @override
  String get settings_regionSettingsSubtitle =>
      'Управление хранилищем регионов';

  @override
  String get settings_regionManagement_screenTitle => 'Управление регионами';

  @override
  String get settings_regionNameHint => 'Введите имя региона';

  @override
  String get settings_regionAddRegion => 'Добавить регион';

  @override
  String get settings_regionFetchRegions => 'Запросить регионы у репитеров';

  @override
  String get settings_regionFetchRegionsFail => 'Регионы не обнаружены';

  @override
  String get settings_regionFetchRegionsAlreadyExists =>
      'Этот регион уже добавлен';

  @override
  String get settings_regionName => 'Имя региона';

  @override
  String get settings_regionDeleted => 'Регион удалён';

  @override
  String get settings_deleteRegion => 'Удалить регион';

  @override
  String settings_deleteRegionConfirm(String region) {
    return 'Удалить \"$region\" из списка регионов?';
  }

  @override
  String get settings_location => 'Позиция';

  @override
  String get settings_locationSubtitle => 'Координаты GPS';

  @override
  String get settings_locationUpdated => 'Позиция и настройки GPS обновлены';

  @override
  String get settings_locationBothRequired => 'Введите широту и долготу.';

  @override
  String get settings_locationInvalid => 'Неверная широта или долгота.';

  @override
  String get settings_locationGPSEnable => 'Включить GPS';

  @override
  String get settings_locationGPSEnableSubtitle =>
      'Включение GPS для автоматического обновления позиции.';

  @override
  String get settings_locationIntervalSec =>
      'Интервал для позиционирования GPS (секунды)';

  @override
  String get settings_locationIntervalInvalid =>
      'Интервал должен составлять не менее 60 секунд и не более 86400 секунд.';

  @override
  String get settings_latitude => 'Широта';

  @override
  String get settings_longitude => 'Долгота';

  @override
  String get settings_contactSettings => 'Настройки контактов';

  @override
  String get settings_contactSettingsSubtitle =>
      'Настройки добавления контактов';

  @override
  String get settings_privacyMode => 'Режим конфиденциальности';

  @override
  String get settings_privacyModeSubtitle =>
      'Скрыть имя/местоположение в анонсах';

  @override
  String get settings_privacyModeToggle =>
      'Включить режим конфиденциальности, чтобы скрыть ваше имя и местоположение в анонсах.';

  @override
  String get settings_privacyModeEnabled => 'Режим конфиденциальности включен';

  @override
  String get settings_privacyModeDisabled =>
      'Режим конфиденциальности выключен';

  @override
  String get settings_privacy => 'Настройки конфиденциальности';

  @override
  String get settings_privacySubtitle =>
      'Контролируйте, какую информацию делиться.';

  @override
  String get settings_privacySettingsDescription =>
      'Выберите, какую информацию ваше устройство будет делиться с другими.';

  @override
  String get settings_denyAll => 'Отклонить все';

  @override
  String get settings_allowByContact => 'Разрешить по флагам контактов';

  @override
  String get settings_allowAll => 'Разрешить все';

  @override
  String get settings_telemetryBaseMode => 'Базовый режим телеметрии';

  @override
  String get settings_telemetryLocationMode =>
      'Режим местоположения телеметрии';

  @override
  String get settings_telemetryEnvironmentMode => 'Режим среды телеметрии';

  @override
  String get settings_advertLocation => 'Местоположение в анонсе';

  @override
  String get settings_advertLocationSubtitle =>
      'Добавлять местоположение в анонс.';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdate =>
      'Авто-объявление без хопов при обновлении GPS';

  @override
  String get settings_autoZeroHopAdvertOnGpsUpdateSubtitle =>
      'Когда GPS-местоположение меняется, отправлять объявление без хопов (требуется геопозиция в объявлении).';

  @override
  String get settings_multiAck => 'Несколько подтверждений';

  @override
  String get settings_telemetryModeUpdated => 'Режим телеметрии обновлен';

  @override
  String get settings_actions => 'Действия';

  @override
  String get settings_deleteAllPaths => 'Удалить все маршруты';

  @override
  String get settings_deleteAllPathsSubtitle =>
      'Очистить все локальные данные о маршрутах в контактах. Маршруты на ноде затронуты не будут.';

  @override
  String get settings_sendAdvertisement => 'Отправить анонс';

  @override
  String get settings_sendAdvertisementSubtitle =>
      'Анонсировать присутствие сейчас';

  @override
  String get settings_advertisementSent => 'Анонс отправлен';

  @override
  String get settings_syncTime => 'Синхронизация времени';

  @override
  String get settings_syncTimeSubtitle => 'Синхронизировать время с телефоном';

  @override
  String get settings_timeSynchronized => 'Время синхронизировано';

  @override
  String get settings_refreshContacts => 'Обновить контакты';

  @override
  String get settings_refreshContactsSubtitle =>
      'Перезагрузить список контактов с устройства';

  @override
  String get settings_rebootDevice => 'Перезагрузить устройство';

  @override
  String get settings_rebootDeviceSubtitle =>
      'Перезапустить устройство MeshCore';

  @override
  String get settings_rebootDeviceConfirm =>
      'Вы уверены, что хотите перезагрузить устройство? Вы будете отключены.';

  @override
  String get settings_debug => 'Отладка';

  @override
  String get settings_companionDebugLog =>
      'Журнал отладки (для сопутствующего приложения)';

  @override
  String get settings_companionDebugLogSubtitle =>
      'Команды, ответы и необработанные данные, используемые для протоколов BLE, TCP и USB.';

  @override
  String get settings_appDebugLog => 'Журнал отладки приложения';

  @override
  String get settings_appDebugLogSubtitle => 'Сообщения отладки приложения';

  @override
  String get settings_about => 'О программе';

  @override
  String settings_aboutVersion(String version) {
    return 'MeshCore Open (Advanced mod) v$version';
  }

  @override
  String get settings_aboutLegalese => '2026 MeshCore Open Source Project';

  @override
  String get settings_aboutDescription =>
      'Открытое клиентское приложение на Flutter для устройств MeshCore в LoRa-сетях.';

  @override
  String get settings_aboutModDescription =>
      'Модификация «Advanced» базируется на оригинальном meshcore_open и предоставляет изменения, предложенные в репозиторий оригинального приложения или специфичные для территории использования, и поэтому не оформленные в виде PR.';

  @override
  String get settings_aboutModLink =>
      'Группа модификации в TG: https://t.me/mcoadvanced';

  @override
  String get settings_aboutOpenMeteoAttribution =>
      'Данные о высоте LOS: Open-Meteo (CC BY 4.0)';

  @override
  String get settings_infoName => 'Имя';

  @override
  String get settings_infoId => 'ID';

  @override
  String get settings_infoStatus => 'Статус';

  @override
  String get settings_infoBattery => 'Батарея';

  @override
  String get settings_infoPublicKey => 'Публичный ключ';

  @override
  String get settings_infoContactsCount => 'Количество контактов';

  @override
  String get settings_infoChannelCount => 'Количество каналов';

  @override
  String get settings_infoFirmware => 'Версия прошивки';

  @override
  String get settings_presets => 'Пресеты';

  @override
  String get settings_frequency => 'Частота (МГц)';

  @override
  String get settings_frequencyHelper => '300.0 – 2500.0';

  @override
  String get settings_frequencyInvalid => 'Недопустимая частота (300–2500 МГц)';

  @override
  String get settings_bandwidth => 'Полоса пропускания';

  @override
  String get settings_spreadingFactor => 'Коэффициент расширения';

  @override
  String get settings_codingRate => 'Коэффициент кодирования';

  @override
  String get settings_txPower => 'Мощность передачи (дБм)';

  @override
  String get settings_txPowerHelper => '0 – 22';

  @override
  String get settings_txPowerInvalid =>
      'Недопустимая мощность передачи (0–22 дБм)';

  @override
  String get settings_clientRepeat => 'Повторение \"вне сети\"';

  @override
  String get settings_clientRepeatSubtitle =>
      'Позвольте этому устройству повторять пакеты данных для других устройств.';

  @override
  String get settings_clientRepeatFreqWarning =>
      'Для работы в режиме \"без подключения к сети\" требуется частота 433, 869 или 918 МГц.';

  @override
  String settings_error(String message) {
    return 'Ошибка: $message';
  }

  @override
  String get settings_channelResendTimeoutTitle =>
      'Задержка для ручной переотправки';

  @override
  String get settings_channelResendTimeoutSubtitle =>
      'Также влияет на внутренний механизм устранения отрисовки дублей исходящих сообщений';

  @override
  String get settings_channelMaxbytesOutgoingTitle =>
      'Ограничить payload исходящих канальных сообщений, байт';

  @override
  String get settings_channelMaxbytesOutgoingSubtitle =>
      'Лимит учитывает текст сообщения + имя отправителя. Замечено, что при превышении некоторого количества байт в сообщении перестают проходить отметки о репитах пакета. Особенно сильно это выражается при подключениях по BLE. Примерная граница, где подтверждения работают - 139 байт. Для usb этот лимит ~155 байт.';

  @override
  String get settings_quickAnswersTitle => 'Быстрые ответы';

  @override
  String get settings_quickAnswersSubtitle =>
      'Список строк, доступных для выбора в качестве быстрого ответа. Назначаются для контактов/каналов в их настройках.';

  @override
  String get settings_quickAnswersAddText => 'Введите текст ответа';

  @override
  String get settings_quickAnswersEditText => 'Редактирование ответа';

  @override
  String get settings_quickAnswersSelect => 'Включить эти ответы';

  @override
  String get settings_quickAnswersExists => 'Уже существует';

  @override
  String get settings_quickAnswersNotAdded =>
      'Вы еще не добавили быстрые ответы для этого чата!';

  @override
  String get settings_quickAnswersSendAtSelect => 'Отправлять при выборе';

  @override
  String get appSettings_title => 'Настройки приложения';

  @override
  String get appSettings_appearance => 'Внешний вид';

  @override
  String get appSettings_theme => 'Тема';

  @override
  String get appSettings_themeSystem => 'Как в системе';

  @override
  String get appSettings_themeLight => 'Светлая';

  @override
  String get appSettings_themeDark => 'Тёмная';

  @override
  String get appSettings_language => 'Язык';

  @override
  String get appSettings_languageSystem => 'Как в системе';

  @override
  String get appSettings_languageEn => 'Английский';

  @override
  String get appSettings_languageFr => 'Французский';

  @override
  String get appSettings_languageEs => 'Испанский';

  @override
  String get appSettings_languageDe => 'Немецкий';

  @override
  String get appSettings_languagePl => 'Польский';

  @override
  String get appSettings_languageSl => 'Словенский';

  @override
  String get appSettings_languagePt => 'Португальский';

  @override
  String get appSettings_languageIt => 'Итальянский';

  @override
  String get appSettings_languageZh => 'Китайский';

  @override
  String get appSettings_languageSv => 'Шведский';

  @override
  String get appSettings_languageNl => 'Нидерландский';

  @override
  String get appSettings_languageSk => 'Словацкий';

  @override
  String get appSettings_languageBg => 'Болгарский';

  @override
  String get appSettings_languageRu => 'Русский';

  @override
  String get appSettings_languageUk => 'Українська';

  @override
  String get repeater_pathHashModeOption0 => '0 — 1 байт';

  @override
  String get repeater_pathHashModeOption1 => '1 — 2 байта';

  @override
  String get repeater_pathHashModeOption2 => '2 — 3 байта';

  @override
  String get repeater_pathHashModeOption3 => '3 — 4 байта';

  @override
  String get appSettings_enableMessageTracing =>
      'Включить трассировку сообщений';

  @override
  String get appSettings_enableMessageTracingSubtitle =>
      'Показывать подробные метаданные о маршрутизации и времени для сообщений';

  @override
  String get appSettings_enableTimeSeconds =>
      'Отображать секунды в информации о сообщении';

  @override
  String get appSettings_showKeyboardHidingButton =>
      'Показывать кнопку скрытия клавиатуры';

  @override
  String get appSettings_notifications => 'Уведомления';

  @override
  String get appSettings_enableNotifications => 'Включить уведомления';

  @override
  String get appSettings_enableNotificationsSubtitle =>
      'Получать уведомления о сообщениях и анонсах';

  @override
  String get appSettings_notificationPermissionDenied =>
      'Разрешение на уведомления отклонено';

  @override
  String get appSettings_notificationsEnabled => 'Уведомления включены';

  @override
  String get appSettings_notificationsDisabled => 'Уведомления отключены';

  @override
  String get appSettings_messageNotifications => 'Уведомления о сообщениях';

  @override
  String get appSettings_messageNotificationsSubtitle =>
      'Показывать уведомление при получении новых сообщений';

  @override
  String get appSettings_channelMessageNotifications =>
      'Уведомления о сообщениях в каналах';

  @override
  String get appSettings_channelMessageNotificationsSubtitle =>
      'Показывать уведомление при получении сообщений в каналах';

  @override
  String get appSettings_advertisementNotifications => 'Уведомления об анонсах';

  @override
  String get appSettings_advertisementNotificationsSubtitle =>
      'Показывать уведомление при обнаружении новых нод';

  @override
  String get appSettings_messaging => 'Обмен сообщениями';

  @override
  String get appSettings_clearPathOnMaxRetry =>
      'Сбросить маршрут после максимального числа попыток';

  @override
  String get appSettings_clearPathOnMaxRetrySubtitle =>
      'Сбросить маршрут контакта после 5 неудачных попыток отправки';

  @override
  String get appSettings_pathsWillBeCleared =>
      'Маршруты будут сброшены после 5 неудачных попыток';

  @override
  String get appSettings_pathsWillNotBeCleared =>
      'Маршруты не будут автоматически сбрасываться';

  @override
  String get appSettings_autoRouteRotation =>
      'Автоматическое переключение маршрутов';

  @override
  String get appSettings_autoRouteRotationSubtitle =>
      'Циклически переключаться между лучшими маршрутами и режимом flood';

  @override
  String get appSettings_autoRouteRotationEnabled =>
      'Автоматическое переключение маршрутов включено';

  @override
  String get appSettings_autoRouteRotationDisabled =>
      'Автоматическое переключение маршрутов отключено';

  @override
  String get appSettings_maxRouteWeight =>
      'Максимальный допустимый вес маршрута';

  @override
  String get appSettings_maxRouteWeightSubtitle =>
      'Максимальный вес, который может быть перевезён по определённому маршруту при успешных доставках.';

  @override
  String get appSettings_initialRouteWeight => 'Начальный вес маршрута';

  @override
  String get appSettings_initialRouteWeightSubtitle =>
      'Начальный вес для новых, только что открытых маршрутов';

  @override
  String get appSettings_routeWeightSuccessIncrement =>
      'Увеличение веса успеха';

  @override
  String get appSettings_routeWeightSuccessIncrementSubtitle =>
      'Вес, добавленный к маршруту после успешной доставки.';

  @override
  String get appSettings_routeWeightFailureDecrement =>
      'Уменьшение веса неудачи';

  @override
  String get appSettings_routeWeightFailureDecrementSubtitle =>
      'Вес, который был удален с пути после неудачной доставки.';

  @override
  String get appSettings_maxMessageRetries =>
      'Максимальное количество повторных попыток отправки сообщения';

  @override
  String get appSettings_maxMessageRetriesSubtitle =>
      'Количество попыток повторной отправки сообщения перед тем, как пометить его как неудачное.';

  @override
  String get appSettings_battery => 'Батарея';

  @override
  String get appSettings_batteryChemistry => 'Химия батареи';

  @override
  String appSettings_batteryChemistryPerDevice(String deviceName) {
    return 'Установить для устройства ($deviceName)';
  }

  @override
  String get appSettings_batteryChemistryConnectFirst =>
      'Подключитесь к устройству, чтобы выбрать';

  @override
  String get appSettings_batteryNmc => '18650 NMC (3.0–4.2 В)';

  @override
  String get appSettings_batteryLifepo4 => 'LiFePO4 (2.6–3.65 В)';

  @override
  String get appSettings_batteryLipo => 'LiPo (3.0–4.2 В)';

  @override
  String get appSettings_mapDisplay => 'Отображение карты';

  @override
  String get appSettings_showRepeaters => 'Показывать репитеры';

  @override
  String get appSettings_showRepeatersSubtitle =>
      'Отображать репитеры на карте';

  @override
  String get appSettings_showChatNodes => 'Показывать чат-ноды';

  @override
  String get appSettings_showChatNodesSubtitle =>
      'Отображать чат-ноды на карте';

  @override
  String get appSettings_showOtherNodes => 'Показывать другие ноды';

  @override
  String get appSettings_showOtherNodesSubtitle =>
      'Отображать другие типы нод на карте';

  @override
  String get appSettings_timeFilter => 'Фильтр по времени';

  @override
  String get appSettings_timeFilterShowAll => 'Показывать все ноды';

  @override
  String appSettings_timeFilterShowLast(int hours) {
    return 'Показывать ноды за последние $hours ч';
  }

  @override
  String get appSettings_mapTimeFilter => 'Временной фильтр карты';

  @override
  String get appSettings_showNodesDiscoveredWithin =>
      'Показывать ноды, обнаруженные за:';

  @override
  String get appSettings_allTime => 'Всё время';

  @override
  String get appSettings_lastHour => 'Последний час';

  @override
  String get appSettings_last6Hours => 'Последние 6 часов';

  @override
  String get appSettings_last24Hours => 'Последние 24 часа';

  @override
  String get appSettings_lastWeek => 'Последнюю неделю';

  @override
  String get appSettings_rasterTileSource => 'Источник растровых тайлов';

  @override
  String get appSettings_stadiaEndpoint => 'Конечная точка Stadia';

  @override
  String get appSettings_stadiaApiKey => 'Ключ API Stadia';

  @override
  String get appSettings_stadiaApiKeyRequired =>
      'Требуется для использования Stadia Maps';

  @override
  String appSettings_stadiaApiKeyConfigured(String maskedKey) {
    return 'Настроено: $maskedKey';
  }

  @override
  String get appSettings_stadiaApiKeyDialogDescription =>
      'Введите свой ключ API Stadia Maps. Приложение использует его для запросов растровых тайлов.';

  @override
  String get appSettings_offlineMapCache => 'Кэш офлайн-карты';

  @override
  String get appSettings_unitsTitle => 'Единицы';

  @override
  String get appSettings_unitsMetric => 'Метрическая (м/км)';

  @override
  String get appSettings_unitsImperial => 'Имперская (ft / mi)';

  @override
  String get appSettings_noAreaSelected => 'Область не выбрана';

  @override
  String appSettings_areaSelectedZoom(int minZoom, int maxZoom) {
    return 'Область выбрана (масштаб $minZoom–$maxZoom)';
  }

  @override
  String get appSettings_debugCard => 'Отладка';

  @override
  String get appSettings_appDebugLogging => 'Журнал отладки приложения';

  @override
  String get appSettings_appDebugLoggingSubtitle =>
      'Записывать отладочные сообщения приложения для диагностики';

  @override
  String get appSettings_appDebugLoggingEnabled =>
      'Журнал отладки приложения включён';

  @override
  String get appSettings_appDebugLoggingDisabled =>
      'Журнал отладки приложения отключён';

  @override
  String get contacts_title => 'Контакты';

  @override
  String get contacts_noContacts => 'Контактов пока нет';

  @override
  String get contacts_contactsWillAppear =>
      'Контакты появятся, когда устройства начнут анонсировать себя';

  @override
  String get contacts_unread => 'Непрочитанное';

  @override
  String get contacts_searchContactsNoNumber => 'Поиск контактов...';

  @override
  String contacts_searchContacts(int number, String str) {
    return 'Поиск $number$str контактов...';
  }

  @override
  String contacts_searchFavorites(int number, String str) {
    return 'Поиск $number$str избранного...';
  }

  @override
  String contacts_searchUsers(int number, String str) {
    return 'Поиск $number$str пользователей...';
  }

  @override
  String contacts_searchRepeaters(int number, String str) {
    return 'Поиск $number$str репитеров...';
  }

  @override
  String contacts_searchRoomServers(int number, String str) {
    return 'Поиск $number$str серверов комнат...';
  }

  @override
  String get contacts_noUnreadContacts => 'Нет непрочитанных контактов';

  @override
  String get contacts_noContactsFound => 'Контакты или группы не найдены';

  @override
  String get contacts_deleteContact => 'Удалить контакт';

  @override
  String contacts_removeConfirm(String contactName) {
    return 'Удалить $contactName из контактов?';
  }

  @override
  String get contacts_manageRepeater => 'Управление репитером';

  @override
  String get contacts_manageRoom => 'Управление сервером комнат';

  @override
  String get contacts_roomLogin => 'Вход на сервер комнат';

  @override
  String get contacts_openChat => 'Открыть чат';

  @override
  String get contacts_editGroup => 'Изменить группу';

  @override
  String get contacts_deleteGroup => 'Удалить группу';

  @override
  String contacts_deleteGroupConfirm(String groupName) {
    return 'Удалить \"$groupName\"?';
  }

  @override
  String get contacts_newGroup => 'Новая группа';

  @override
  String get contacts_newGroupDescription =>
      'Объединяет каналы/контакты в папку';

  @override
  String get contacts_moreOptions => 'Больше вариантов';

  @override
  String get contacts_searchOpen => 'Найти контакты';

  @override
  String get contacts_searchClose => 'Закрыть поиск';

  @override
  String get contacts_groupName => 'Имя группы';

  @override
  String get contacts_groupNameRequired => 'Имя группы обязательно';

  @override
  String get contacts_groupNameReserved => 'Это имя группы зарезервировано';

  @override
  String contacts_groupAlreadyExists(String name) {
    return 'Группа \"$name\" уже существует';
  }

  @override
  String get contacts_filterContacts => 'Фильтр контактов...';

  @override
  String get contacts_noContactsMatchFilter =>
      'Нет контактов, соответствующих фильтру';

  @override
  String get contacts_noMembers => 'Нет участников';

  @override
  String get contacts_lastSeenNow => 'Только что';

  @override
  String contacts_lastSeenMinsAgo(int minutes) {
    return '$minutes мин назад';
  }

  @override
  String get contacts_lastSeenHourAgo => '1 час назад';

  @override
  String contacts_lastSeenHoursAgo(int hours) {
    return '$hours ч назад';
  }

  @override
  String get contacts_lastSeenDayAgo => '1 день назад';

  @override
  String contacts_lastSeenDaysAgo(int days) {
    return '$days дн. назад';
  }

  @override
  String get contact_info => 'Контактная информация';

  @override
  String get contact_settings => 'Настройки контактов';

  @override
  String get contact_telemetry => 'Телеметрия';

  @override
  String get contact_lastSeen => 'Последний раз видели';

  @override
  String get contact_clearChat => 'Очистить чат';

  @override
  String get contact_clearChatConfirm => 'Удалить сообщения из чата?';

  @override
  String get contact_teleBase => 'База телеметрии';

  @override
  String get contact_teleBaseSubtitle =>
      'Разрешить обмен уровнем заряда батареи и базовой телеметрией';

  @override
  String get contact_teleLoc => 'Местоположение телеметрии';

  @override
  String get contact_teleLocSubtitle =>
      'Разрешить обмен данными о местоположении';

  @override
  String get contact_teleEnv => 'Среда телеметрии';

  @override
  String get contact_teleEnvSubtitle =>
      'Разрешить обмен данными датчиков окружающей среды';

  @override
  String get channels_title => 'Каналы';

  @override
  String get channels_noChannelsConfigured => 'Каналы не настроены';

  @override
  String get channels_addPublicChannel => 'Добавить публичный канал';

  @override
  String get channels_searchChannels => 'Поиск каналов...';

  @override
  String get channels_noChannelsFound => 'Каналы не найдены';

  @override
  String channels_channelIndex(int index) {
    return 'Канал $index';
  }

  @override
  String get channels_public => 'Публичный';

  @override
  String channels_via(String path) {
    return 'через $path';
  }

  @override
  String get channels_private => 'Приватный';

  @override
  String get channels_editChannel => 'Изменить канал';

  @override
  String get channels_muteChannel => 'Отключить уведомления канала';

  @override
  String get channels_unmuteChannel => 'Включить уведомления канала';

  @override
  String get channels_deleteChannel => 'Удалить канал';

  @override
  String channels_deleteChannelConfirm(String name) {
    return 'Удалить \"$name\"? Это действие нельзя отменить.';
  }

  @override
  String channels_channelDeleteFailed(String name) {
    return 'Не удалось удалить канал $name.';
  }

  @override
  String channels_channelDeleted(String name) {
    return 'Канал \"$name\" удалён';
  }

  @override
  String get channels_addChannel => 'Добавить канал';

  @override
  String get channels_channelIndexLabel => 'Индекс канала';

  @override
  String get channels_channelName => 'Имя канала';

  @override
  String get channels_usePublicChannel => 'Использовать публичный канал';

  @override
  String get channels_standardPublicPsk => 'Стандартный публичный PSK';

  @override
  String get channels_pskHex => 'PSK (Hex)';

  @override
  String get channels_generateRandomPsk => 'Сгенерировать случайный PSK';

  @override
  String get channels_enterChannelName => 'Введите имя канала';

  @override
  String get channels_pskMustBe32Hex =>
      'PSK должен содержать 32 шестнадцатеричных символа';

  @override
  String channels_channelAdded(String name) {
    return 'Канал \"$name\" добавлен';
  }

  @override
  String channels_editChannelTitle(int index) {
    return 'Изменить канал $index';
  }

  @override
  String get channels_smazCompression => 'Сжатие SMAZ';

  @override
  String get channels_cyr2latCompression => 'Сжатие Cyr2Lat';

  @override
  String get channels_cyr2latCompressionDscr =>
      'Заменяет некоторые кириллические символы на латиницу при отправке.';

  @override
  String get channels_cyr2latSettingsHeading => 'Настройка Cyr2Lat';

  @override
  String get channels_cyr2latSettingsSubheading => 'Список замен';

  @override
  String get channels_cyr2latSettingsDscr =>
      'Редактировать JSON-конфигурацию замены символов';

  @override
  String get channels_cyr2latSettingsDialogHint => 'JSON-карта замен';

  @override
  String channels_cyr2latSettingsDialogWrongJSON(Object error) {
    return 'Некорректный JSON: $error';
  }

  @override
  String channels_channelUpdated(String name) {
    return 'Канал \"$name\" обновлён';
  }

  @override
  String get channels_changeWidgetColor => 'Цвет виджета';

  @override
  String get channels_changeWidgetTextColor => 'Цвет текста виджета';

  @override
  String get channels_changeGroupEmpty => 'Здесь пока пусто';

  @override
  String get channels_allowOrderingInGroup =>
      'Сортировка каналов внутри группы';

  @override
  String get settings_cyr2latProfileAdd => 'Добавить профиль Cyr2Lat';

  @override
  String get settings_cyr2latProfileName => 'Название профиля';

  @override
  String get settings_cyr2latProfileNameEmpty =>
      'Название профиля не может быть пустым';

  @override
  String get settings_cyr2latProfileAdded => 'Профиль добавлен';

  @override
  String get settings_cyr2latProfileUpdated => 'Профиль успешно обновлен';

  @override
  String get settings_cyr2latProfileEdit => 'Редактировать профиль Cyr2Lat';

  @override
  String get settings_cyr2latProfileDelete => 'Удалить профиль Cyr2Lat';

  @override
  String get settings_cyr2latProfileDeleted => 'Профиль успешно удален';

  @override
  String settings_cyr2latProfileDeleteDscr(String name) {
    return 'Вы действительно хотите удалить профиль \"$name\"?';
  }

  @override
  String get settings_mcmpTextLimit => 'MCMP: лимит символов для вставки';

  @override
  String get settings_sendingDelayForCancellation =>
      'Задержка отправки для её отмены';

  @override
  String get settings_useSendingDelay => 'Отправлять с задержкой';

  @override
  String get chat_cancelSend => 'отменить отправку';

  @override
  String get settings_doNotFilterMessagesOnChannels =>
      'Не фильтровать собственные пакеты сообщений на этих каналах и считать сообщения безусловно доставленными';

  @override
  String get settings_doNotFilterMessagesOnChannelsSubtitle =>
      'По умолчанию, сообщения от своей же ноды игнорируются. Это делает невозможным работу встроенного терминала (TerminalCLI) на некоторых прошивках';

  @override
  String get channels_publicChannelAdded => 'Публичный канал добавлен';

  @override
  String get channels_sortBy => 'Сортировка';

  @override
  String get channels_sortManual => 'Вручную';

  @override
  String get channels_sortAZ => 'По алфавиту';

  @override
  String get channels_sortLatestMessages => 'По последним сообщениям';

  @override
  String get channels_sortUnread => 'По непрочитанным';

  @override
  String get channels_createPrivateChannel => 'Создать приватный канал';

  @override
  String get channels_createPrivateChannelDesc => 'Защищён секретным ключом.';

  @override
  String get channels_joinPrivateChannel =>
      'Присоединиться к приватному каналу';

  @override
  String get channels_joinPrivateChannelDesc =>
      'Введите секретный ключ вручную.';

  @override
  String get channels_joinPublicChannel => 'Присоединиться к публичному каналу';

  @override
  String get channels_joinPublicChannelDesc =>
      'К этому каналу может присоединиться любой.';

  @override
  String get channels_joinHashtagChannel => 'Присоединиться к хэштег-каналу';

  @override
  String get channels_joinHashtagChannelDesc =>
      'К хэштег-каналам может присоединиться любой.';

  @override
  String get channels_scanQrCode => 'Сканировать QR-код';

  @override
  String get channels_scanQrCodeComingSoon => 'Скоро будет';

  @override
  String get channels_enterHashtag => 'Введите хэштег';

  @override
  String get channels_hashtagHint => 'например, #команда';

  @override
  String channels_regionSetTo(String region) {
    return 'Регион: $region';
  }

  @override
  String get channels_regionNotSet => 'Регион: отсутствует';

  @override
  String get channels_regionSelect_Title => 'Назначить регион';

  @override
  String get channels_clearRegion => 'Очистить региональность';

  @override
  String get chat_noMessages => 'Сообщений пока нет';

  @override
  String get chat_sendMessage => 'Отправить сообщение';

  @override
  String chat_sendMessageTo(String contactName) {
    return 'Отправить сообщение $contactName';
  }

  @override
  String get chat_sendMessageToStart => 'Отправьте сообщение, чтобы начать';

  @override
  String get chat_originalMessageNotFound => 'Исходное сообщение не найдено';

  @override
  String chat_replyingTo(String name) {
    return 'Ответ для $name';
  }

  @override
  String chat_replyTo(String name) {
    return 'Ответить $name';
  }

  @override
  String get chat_location => 'Местоположение';

  @override
  String get chat_typeMessage => 'Напишите сообщение...';

  @override
  String chat_messageTooLong(int maxBytes) {
    return 'Сообщение слишком длинное (макс. $maxBytes байт).';
  }

  @override
  String get chat_messageCopied => 'Сообщение скопировано';

  @override
  String get chat_messageDeleted => 'Сообщение удалено';

  @override
  String get chat_retryingMessage => 'Повтор отправки сообщения';

  @override
  String chat_retryingMessageWait(Object seconds) {
    return 'Пожалуйста, подождите ещё $seconds сек. перед переотправкой';
  }

  @override
  String chat_retryCount(int current, int max) {
    return 'Попытка $current/$max';
  }

  @override
  String get chat_sendGif => 'Отправить GIF';

  @override
  String get chat_receivedGif => 'Получен GIF';

  @override
  String get chat_reply => 'Ответить';

  @override
  String get chat_addReaction => 'Добавить реакцию';

  @override
  String get chat_me => 'Я';

  @override
  String get emojiCategorySmileys => 'Смайлы';

  @override
  String get emojiCategoryGestures => 'Жесты';

  @override
  String get emojiCategoryHearts => 'Сердечки';

  @override
  String get emojiCategoryObjects => 'Предметы';

  @override
  String get gifPicker_title => 'Выберите GIF';

  @override
  String get gifPicker_searchHint => 'Поиск GIF...';

  @override
  String get gifPicker_poweredBy => 'Работает на GIPHY';

  @override
  String get gifPicker_noGifsFound => 'GIF не найдены';

  @override
  String get gifPicker_failedLoad => 'Не удалось загрузить GIF';

  @override
  String get gifPicker_failedSearch => 'Не удалось выполнить поиск GIF';

  @override
  String get gifPicker_noInternet => 'Нет подключения к интернету';

  @override
  String get debugLog_appTitle => 'Журнал отладки приложения';

  @override
  String get debugLog_bleTitle => 'Журнал отладки BLE';

  @override
  String get debugLog_copyLog => 'Копировать журнал';

  @override
  String get debugLog_clearLog => 'Очистить журнал';

  @override
  String get debugLog_copied => 'Журнал отладки скопирован';

  @override
  String get debugLog_bleCopied => 'Журнал BLE скопирован';

  @override
  String get debugLog_noEntries => 'Журнал отладки пока пуст';

  @override
  String get debugLog_enableInSettings =>
      'Включите запись журнала отладки в настройках';

  @override
  String get debugLog_frames => 'Фреймы';

  @override
  String get debugLog_rawLogRx => 'Сырой журнал приёма';

  @override
  String get debugLog_noBleActivity => 'Активность BLE пока отсутствует';

  @override
  String debugFrame_length(int count) {
    return 'Длина фрейма: $count байт';
  }

  @override
  String debugFrame_command(String value) {
    return 'Команда: 0x$value';
  }

  @override
  String get debugFrame_textMessageHeader => 'Фрейм текстового сообщения:';

  @override
  String debugFrame_destinationPubKey(String pubKey) {
    return '- Публичный ключ получателя: $pubKey';
  }

  @override
  String debugFrame_timestamp(int timestamp) {
    return '- Временная метка: $timestamp';
  }

  @override
  String debugFrame_flags(String value) {
    return '- Флаги: 0x$value';
  }

  @override
  String debugFrame_textType(int type, String label) {
    return '- Тип текста: $type ($label)';
  }

  @override
  String get debugFrame_textTypeCli => 'CLI';

  @override
  String get debugFrame_textTypePlain => 'Обычный';

  @override
  String debugFrame_text(String text) {
    return '- Текст: \"$text\"';
  }

  @override
  String get debugFrame_hexDump => 'Шестнадцатеричный дамп:';

  @override
  String chat_hopsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'хопов',
      many: 'хопов',
      few: 'хопа',
      one: 'хоп',
    );
    return '$count $_temp0';
  }

  @override
  String get chat_removePath => 'Удалить маршрут';

  @override
  String get chat_noPathHistoryYet =>
      'История маршрутов пока пуста.\nОтправьте сообщение, чтобы обнаружить маршруты.';

  @override
  String get chat_pathCleared =>
      'Маршрут очищен. Следующее сообщение обновит маршрут.';

  @override
  String get chat_fullPath => 'Полный маршрут';

  @override
  String get routing_title => 'Маршрутизация';

  @override
  String get routing_modeAuto => 'Авто';

  @override
  String get routing_modeFlood => 'Flood';

  @override
  String get routing_modeManual => 'Вручную';

  @override
  String get routing_modeAutoHint =>
      'Автоматически выбирает лучший известный маршрут; если маршрут неизвестен, использует flood.';

  @override
  String get routing_modeFloodHint =>
      'Передача пакета через все репитеры. Самый надёжный способ, но требует больше airtime.';

  @override
  String get routing_modeManualHint =>
      'Всегда следует точно по указанному вами маршруту.';

  @override
  String get routing_currentRoute => 'Текущий маршрут';

  @override
  String get routing_directNoHops => 'Прямое соединение – без ретрансляторов';

  @override
  String get routing_noPathYet =>
      'Пока нет маршрута. Следующее сообщение будет отправлено через flood, пока маршрут не будет обнаружен.';

  @override
  String get routing_floodBroadcast => 'Транслируется через все репитеры';

  @override
  String get routing_editPath => 'Изменить путь';

  @override
  String get routing_forgetPath => 'Забыть маршрут';

  @override
  String get routing_knownPaths => 'Известные маршруты';

  @override
  String get routing_knownPathsHint =>
      'Нажмите на маршрут для переключения на него.';

  @override
  String get routing_inUse => 'В эксплуатации';

  @override
  String get routing_qualityStrong => 'Сильный первый хоп';

  @override
  String get routing_qualityGood => 'Хороший первый хоп';

  @override
  String get routing_qualityFair => 'Средний первый хоп';

  @override
  String get routing_qualityWorked => 'Осуществлено';

  @override
  String get routing_qualityFlood => 'Услышан через flood';

  @override
  String get routing_qualityUntested => 'Непроверенный';

  @override
  String routing_lastWorked(String when) {
    return 'сработало $when';
  }

  @override
  String get routing_neverWorked => 'неподтверждённый';

  @override
  String routing_deliveryCounts(int successes, int failures) {
    return 'доставлено: $successes, не доставлено: $failures';
  }

  @override
  String get routing_floodDelivery => 'Доставка флудом';

  @override
  String get pathEditor_title => 'Создать маршрут';

  @override
  String pathEditor_hopCounter(int count) {
    return '$count из 64 хопов';
  }

  @override
  String get pathEditor_noHops =>
      'Хопы пока не добавлены. Нажмите на репитеры ниже, чтобы добавить их по порядку, или сохраните без хопов для прямой отправки.';

  @override
  String get pathEditor_addHops => 'Добавьте хопы по порядку';

  @override
  String get pathEditor_searchRepeaters => 'Поиск репитеров';

  @override
  String get pathEditor_advancedHex =>
      'Продвинутый уровень: прямой путь в шестнадцатеричном формате';

  @override
  String get pathEditor_hexLabel => 'Префиксы шестнадцатеричной системы';

  @override
  String get pathEditor_hexHelper =>
      'Два шестнадцатеричных символа на хоп, разделённые запятыми';

  @override
  String pathEditor_invalidTokens(String tokens) {
    return 'Неверно: $tokens';
  }

  @override
  String get pathEditor_tooManyHops => 'Максимум 64 хопа';

  @override
  String get pathEditor_usePath => 'Используйте этот путь';

  @override
  String get pathEditor_removeHop => 'Удалить хоп';

  @override
  String get pathEditor_unknownHop => 'Неизвестный репитер';

  @override
  String get chat_pathSavedLocally =>
      'Сохранено локально. Подключитесь для синхронизации.';

  @override
  String get chat_pathDeviceConfirmed => 'Подтверждено устройством.';

  @override
  String get chat_pathDeviceNotConfirmed => 'Ещё не подтверждено устройством.';

  @override
  String get chat_type => 'Тип';

  @override
  String get chat_path => 'Маршрут';

  @override
  String get chat_publicKey => 'Публичный ключ';

  @override
  String get chat_compressOutgoingMessages => 'Сжимать исходящие сообщения';

  @override
  String get chat_floodForced => 'Flood (принудительно)';

  @override
  String get chat_directForced => 'Прямой (принудительно)';

  @override
  String chat_hopsForced(int count) {
    return '$count хоп(ов) (принудительно)';
  }

  @override
  String get chat_floodAuto => 'Flood (авто)';

  @override
  String get chat_direct => 'Прямой';

  @override
  String get chat_poiShared => 'Точка интереса отправлена';

  @override
  String chat_unread(int count) {
    return 'Непрочитанных: $count';
  }

  @override
  String get chat_markAsUnread => 'Пометить как непрочитанные';

  @override
  String get chat_newMessages => 'Новые сообщения';

  @override
  String get chat_openLink => 'Открыть ссылку?';

  @override
  String get chat_openLinkConfirmation =>
      'Хотите открыть эту ссылку в вашем браузере?';

  @override
  String get chat_open => 'Открыть';

  @override
  String chat_couldNotOpenLink(String url) {
    return 'Не удалось открыть ссылку: $url';
  }

  @override
  String get chat_invalidLink => 'Неправильный формат ссылки';

  @override
  String get map_title => 'Карта нод';

  @override
  String get map_searchHint => 'Поиск по имени или ID узла';

  @override
  String get map_activity => 'Активность';

  @override
  String get map_online => 'Онлайн';

  @override
  String get map_recent => 'Недавно';

  @override
  String get map_stale => 'Устаревший';

  @override
  String get map_visible => 'Видимый';

  @override
  String get map_hidden => 'Скрытый';

  @override
  String get map_centerOnNode => 'Центрировать на узле';

  @override
  String get map_details => 'Детали';

  @override
  String get map_noGps => 'Без GPS';

  @override
  String get map_noResults => 'Не найдено соответствующих узлов';

  @override
  String get map_lineOfSight => 'Линия видимости';

  @override
  String get map_losScreenTitle => 'Линия видимости';

  @override
  String get map_noNodesWithLocation => 'Нет нод с данными о местоположении';

  @override
  String get map_nodesNeedGps =>
      'Ноды должны передавать свои GPS-координаты, чтобы отображаться на карте';

  @override
  String map_nodesCount(int count) {
    return 'Нод: $count';
  }

  @override
  String map_pinsCount(int count) {
    return 'Меток: $count';
  }

  @override
  String get map_chat => 'Чат';

  @override
  String get map_repeater => 'Репитер';

  @override
  String get map_room => 'Комната';

  @override
  String get map_sensor => 'Сенсор';

  @override
  String get map_pinDm => 'Метка (ЛС)';

  @override
  String get map_pinPrivate => 'Метка (Приватная)';

  @override
  String get map_pinPublic => 'Метка (Публичная)';

  @override
  String get map_lastSeen => 'Последнее появление';

  @override
  String get map_disconnectConfirm =>
      'Вы уверены, что хотите отключиться от этого устройства?';

  @override
  String get map_from => 'От';

  @override
  String get map_source => 'Источник';

  @override
  String get map_flags => 'Флаги';

  @override
  String get map_type => 'Тип';

  @override
  String get map_path => 'Путь';

  @override
  String get map_location => 'Местоположение';

  @override
  String get map_estLocation => 'Прибл. местоположение';

  @override
  String get map_publicKey => 'Публичный ключ';

  @override
  String get map_publicKeyPrefixHint => 'напр. ab12';

  @override
  String get map_shareMarkerHere => 'Поделиться меткой здесь';

  @override
  String get map_setAsMyLocation => 'Установить мое местоположение';

  @override
  String get map_pinLabel => 'Метка';

  @override
  String get map_label => 'Подпись';

  @override
  String get map_pointOfInterest => 'Точка интереса';

  @override
  String get map_sendToContact => 'Отправить контакту';

  @override
  String get map_sendToChannel => 'Отправить в канал';

  @override
  String get map_noChannelsAvailable => 'Нет доступных каналов';

  @override
  String get map_publicLocationShare => 'Публичная передача местоположения';

  @override
  String map_publicLocationShareConfirm(String channelLabel) {
    return 'Вы собираетесь поделиться местоположением в $channelLabel. Этот канал публичный, и любой, у кого есть PSK, сможет его увидеть.';
  }

  @override
  String get map_connectToShareMarkers =>
      'Подключитесь к устройству, чтобы делиться метками';

  @override
  String get map_filterNodes => 'Фильтр нод';

  @override
  String get map_nodeTypes => 'Типы нод';

  @override
  String get map_chatNodes => 'Чат-ноды';

  @override
  String get map_repeaters => 'Репитеры';

  @override
  String get map_otherNodes => 'Другие ноды';

  @override
  String get map_showOverlaps => 'Перекрытия ключей репитеров';

  @override
  String get map_keyPrefix => 'Префикс ключа';

  @override
  String get map_filterByKeyPrefix => 'Фильтр по префиксу ключа';

  @override
  String get map_publicKeyPrefix => 'Префикс публичного ключа';

  @override
  String get map_markers => 'Метки';

  @override
  String get map_showSharedMarkers => 'Показывать общие метки';

  @override
  String get map_showGuessedLocations =>
      'Отобразить предполагаемые места расположения узлов';

  @override
  String get map_showDiscoveryContacts => 'Показывать Discovery-контакты';

  @override
  String get map_guessedLocation => 'Угаданное место';

  @override
  String get map_lastSeenTime => 'Время последнего появления';

  @override
  String get map_sharedPin => 'Общая метка';

  @override
  String get map_sharedAt => 'Поделено';

  @override
  String get map_joinRoom => 'Присоединиться к комнате';

  @override
  String get map_manageRepeater => 'Управление репитером';

  @override
  String get map_tapToAdd => 'Нажимайте на узлы, чтобы добавить их в путь.';

  @override
  String get map_runTrace => 'Запустить трассировку пути';

  @override
  String get map_runTraceWithReturnPath => 'Вернуться обратно по тому же пути';

  @override
  String get map_removeLast => 'Удалить последний';

  @override
  String get map_pathTraceCancelled => 'Отмена трассировки пути';

  @override
  String get map_wardrive => 'Wardrive';

  @override
  String get map_wardriveStart => 'Старт';

  @override
  String get map_wardriveStop => 'Стоп';

  @override
  String get map_wardriveZeroHopDiscovery => 'Zero-hop discovery';

  @override
  String get map_wardriveDiscoverySent =>
      'Запрос wardrive discovery отправлен.';

  @override
  String get map_wardriveUploadCancelled => 'Выгрузка wardrive отменена.';

  @override
  String map_wardriveDiscoveryFailed(String error) {
    return 'Wardrive discovery не удалось: $error';
  }

  @override
  String map_wardriveRequests(int requests, int responses) {
    return 'Запросы: $requests  Ответы: $responses';
  }

  @override
  String map_wardriveLastRequest(String time) {
    return 'Последний запрос: $time';
  }

  @override
  String get map_wardrivePhoneGpsNotUpdated =>
      'GPS телефона: ещё не обновлялся';

  @override
  String map_wardrivePhoneGpsError(String error) {
    return 'GPS телефона: $error';
  }

  @override
  String map_wardrivePhoneGps(String latitude, String longitude) {
    return 'GPS телефона: $latitude, $longitude';
  }

  @override
  String get map_wardriveNoResponses => 'Ответов discovery пока нет.';

  @override
  String get map_wardriveDataTooltip => 'Данные wardrive';

  @override
  String get map_wardriveUploadData => 'Выгрузить данные';

  @override
  String get map_wardriveManageUploadSites => 'Управление сайтами выгрузки';

  @override
  String get map_wardriveAutoUpload => 'Автовыгрузка';

  @override
  String get map_wardriveReUpload => 'Перевыгрузить';

  @override
  String get map_wardriveScreenWakelock => 'Не гасить экран';

  @override
  String get map_wardriveExport => 'Экспорт';

  @override
  String get map_wardriveImport => 'Импорт';

  @override
  String get map_wardriveAutoDiscovery => 'Авто discovery';

  @override
  String get map_wardriveSecondsSuffix => 'с';

  @override
  String get map_wardriveSamplesNoNew => 'Нет новых сэмплов для выгрузки';

  @override
  String map_wardriveSamplesSaved(int count) {
    return 'Сэмплов сохранено: $count';
  }

  @override
  String map_wardriveAutoDiscoveryError(String error) {
    return 'Авто discovery: $error';
  }

  @override
  String map_wardriveSampleSaveError(String error) {
    return 'Сохранение сэмпла: $error';
  }

  @override
  String map_wardriveCoverageCells(int count) {
    return 'Ячеек покрытия: $count';
  }

  @override
  String get map_wardriveCoverageResolution => 'Детализация покрытия';

  @override
  String get map_wardriveCoverageResolutionPrompt =>
      'Выберите размер блоков покрытия (размер = сторона блока):';

  @override
  String get map_wardriveCoverageRegional => 'Региональный';

  @override
  String get map_wardriveCoverageRegionalSubtitle => '~20 км (точность 4)';

  @override
  String get map_wardriveCoverageCity => 'На уровне города';

  @override
  String get map_wardriveCoverageCitySubtitle => '~5 км (точность 5)';

  @override
  String get map_wardriveCoverageNeighborhood => 'Район';

  @override
  String get map_wardriveCoverageNeighborhoodSubtitle => '~1,2 км (точность 6)';

  @override
  String get map_wardriveCoverageStreet => 'Уровень улицы';

  @override
  String get map_wardriveCoverageStreetSubtitle => '~153 м (точность 7)';

  @override
  String get map_wardriveCoverageBuilding => 'Уровень здания';

  @override
  String get map_wardriveCoverageBuildingSubtitle => '~38 м (точность 8)';

  @override
  String get map_wardriveAutoUploadEnabled => 'Автовыгрузка включена.';

  @override
  String get map_wardriveAutoUploadDisabled => 'Автовыгрузка выключена.';

  @override
  String get map_wardriveNoSamplesToUpload =>
      'Нет wardrive-сэмплов для выгрузки.';

  @override
  String get map_wardriveUploadingSamples => 'Выгрузка сэмплов...';

  @override
  String map_wardriveUploadingTo(String site) {
    return 'Выгрузка на $site...';
  }

  @override
  String map_wardriveUploadBatch(int current, int total) {
    return 'Пакет $current из $total';
  }

  @override
  String map_wardriveUploadSamplesProgress(int sent, int total) {
    return 'Отправка $sent из $total';
  }

  @override
  String map_wardriveUploadTarget(String site) {
    return 'Цель: $site';
  }

  @override
  String get map_wardriveUploadWaitingConnection => 'Ожидание соединения';

  @override
  String get map_wardriveUploadConnectionEstablished =>
      'Соединение установлено, выгрузка';

  @override
  String get map_wardriveUploadProcessingServer =>
      'Данные выгружены, сервер обрабатывает';

  @override
  String map_wardriveUploadServerResponse(int statusCode) {
    return 'Сервер обработал данные, ответ $statusCode';
  }

  @override
  String get map_wardriveUploadTimeoutTreatedAsSuccess =>
      'Выгрузка превысила таймаут; отмечено как отправленное для этого сайта';

  @override
  String map_wardriveUploadServerError(int statusCode) {
    return 'Ошибка сервера $statusCode';
  }

  @override
  String map_wardriveUploadRequestError(String error) {
    return 'Ошибка выгрузки: $error';
  }

  @override
  String map_wardriveUploadFailed(String error) {
    return 'Выгрузка wardrive не удалась: $error';
  }

  @override
  String get map_wardriveUploadComplete => 'Выгрузка завершена';

  @override
  String get map_wardriveUploadResults => 'Результаты выгрузки';

  @override
  String map_wardriveSamplesUploaded(int count) {
    return 'Выгружено сэмплов: $count';
  }

  @override
  String get map_wardriveSelectUploadSites => 'Выберите сайты для выгрузки:';

  @override
  String get map_wardriveNoUploadSitesConfigured =>
      'Сайты выгрузки не настроены';

  @override
  String get map_wardriveAddSite => 'Добавить сайт';

  @override
  String get map_wardriveUploadSitesUpdated => 'Сайты выгрузки обновлены.';

  @override
  String get map_wardriveAddUploadSite => 'Добавить сайт выгрузки';

  @override
  String get map_wardriveEditUploadSite => 'Изменить сайт выгрузки';

  @override
  String get map_wardriveNameLabel => 'Название';

  @override
  String get map_wardriveUrlLabel => 'URL';

  @override
  String get map_wardriveUploadBatchSize => 'Размер пакета выгрузки';

  @override
  String map_wardriveUploadBatchSizeInvalid(int min, int max) {
    return 'Используйте значение от $min до $max';
  }

  @override
  String get map_wardriveTreatTimeoutAsSuccess => 'Считать таймаут успехом';

  @override
  String get map_wardriveNameRequired => 'Название обязательно';

  @override
  String get map_wardriveNameExists => 'Название уже существует';

  @override
  String get map_wardriveValidUrlRequired => 'Требуется корректный URL';

  @override
  String get map_wardriveDeleteSite => 'Удалить сайт';

  @override
  String map_wardriveDeleteSiteConfirm(String name) {
    return 'Удалить «$name»?';
  }

  @override
  String get map_wardriveNoSamplesToExport =>
      'Нет wardrive-сэмплов для экспорта.';

  @override
  String get map_wardriveExportShareText => 'wardrive-сэмплы meshcore-open';

  @override
  String get map_wardriveSamplesExported =>
      'Wardrive-сэмплы экспортированы в JSON-файл.';

  @override
  String map_wardriveExportFailed(String error) {
    return 'Экспорт wardrive не удался: $error';
  }

  @override
  String get map_wardriveImportSamples => 'Импорт wardrive-сэмплов';

  @override
  String get map_wardriveImportHint =>
      'Вставьте экспортированный wardrive JSON сюда';

  @override
  String get map_wardriveNoNewSamplesImported =>
      'Новых wardrive-сэмплов не импортировано.';

  @override
  String map_wardriveSamplesImported(int count) {
    return 'Импортировано wardrive-сэмплов: $count.';
  }

  @override
  String map_wardriveImportFailed(String error) {
    return 'Импорт wardrive не удался: $error';
  }

  @override
  String get map_wardriveNoSamplesToClear =>
      'Нет wardrive-сэмплов для очистки.';

  @override
  String get map_wardriveClearSamplesTitle => 'Очистить wardrive-сэмплы?';

  @override
  String map_wardriveClearSamplesConfirm(int count) {
    return 'Это удалит $count сохранённых сэмплов с этого устройства.';
  }

  @override
  String get map_wardriveSamplesCleared => 'Wardrive-сэмплы очищены.';

  @override
  String get map_wardriveRepNoLocation =>
      'Местоположение репитера не предоставлено';

  @override
  String map_wardriveDiscoveryWait(Object seconds) {
    return 'Подождите $seconds секунд перед повтором';
  }

  @override
  String get map_wardriveFollowMe => 'Следовать за мной';

  @override
  String get map_wardriveDeleteBlock => 'Удалить блок';

  @override
  String get map_wardriveInBackground => 'Работать в фоне';

  @override
  String get map_wardriveContinuousGPS => 'Непрерывный GPS-location';

  @override
  String get map_wardriveShowRepeaterCoverage => 'Отобразить блоки покрытия';

  @override
  String get map_wardriveHideRepeaterCoverage => 'Скрыть блоки покрытия';

  @override
  String get mapCache_title => 'Кэш офлайн-карты';

  @override
  String get mapCache_selectAreaFirst =>
      'Сначала выберите область для кэширования';

  @override
  String get mapCache_noTilesToDownload =>
      'Нет плиток для загрузки в этой области';

  @override
  String get mapCache_downloadTilesTitle => 'Загрузить плитки';

  @override
  String mapCache_downloadTilesPrompt(int count) {
    return 'Загрузить $count плиток для офлайн-использования?';
  }

  @override
  String get mapCache_downloadAction => 'Загрузить';

  @override
  String mapCache_cachedTiles(int count) {
    return 'Закэшировано $count плиток';
  }

  @override
  String mapCache_cachedTilesWithFailed(int downloaded, int failed) {
    return 'Закэшировано $downloaded плиток ($failed не загружено)';
  }

  @override
  String get mapCache_clearOfflineCacheTitle => 'Очистить офлайн-кэш';

  @override
  String get mapCache_clearOfflineCachePrompt =>
      'Удалить все закэшированные плитки карты?';

  @override
  String get mapCache_offlineCacheCleared => 'Офлайн-кэш очищен';

  @override
  String get mapCache_noAreaSelected => 'Область не выбрана';

  @override
  String get mapCache_cacheArea => 'Область кэширования';

  @override
  String get mapCache_useCurrentView => 'Использовать текущий вид';

  @override
  String get mapCache_zoomRange => 'Диапазон масштаба';

  @override
  String mapCache_estimatedTiles(int count) {
    return 'Оценочное количество плиток: $count';
  }

  @override
  String mapCache_downloadedTiles(int completed, int total) {
    return 'Загружено $completed из $total';
  }

  @override
  String get mapCache_downloadTilesButton => 'Загрузить плитки';

  @override
  String get mapCache_clearCacheButton => 'Очистить кэш';

  @override
  String mapCache_failedDownloads(int count) {
    return 'Неудачных загрузок: $count';
  }

  @override
  String get mapCache_cachedTilesLabel => 'Cached tiles';

  @override
  String get mapCache_cachedTileSummaryLabel => 'Cached tile summary';

  @override
  String mapCache_bulkDownloadDisabledForSource(String source) {
    return 'Offline bulk downloads are disabled for $source.';
  }

  @override
  String mapCache_bulkDownloadDisabledInConfig(String source) {
    return 'Offline bulk downloads are disabled for $source in this app configuration.';
  }

  @override
  String mapCache_summarySource(String source) {
    return 'Source: $source';
  }

  @override
  String mapCache_summaryCachedTilesForSource(int count) {
    return 'Cached tiles for source: $count';
  }

  @override
  String mapCache_summaryCachedInSelection(int count) {
    return 'Cached in selected area/zoom: $count';
  }

  @override
  String mapCache_summaryApproxCacheSize(String size) {
    return 'Approx cache size: $size';
  }

  @override
  String mapCache_boundsLabel(
    String north,
    String south,
    String east,
    String west,
  ) {
    return 'С $north, Ю $south, В $east, З $west';
  }

  @override
  String get time_justNow => 'Только что';

  @override
  String time_minutesAgo(int minutes) {
    return '$minutes мин назад';
  }

  @override
  String time_hoursAgo(int hours) {
    return '$hours ч назад';
  }

  @override
  String time_daysAgo(int days) {
    return '$days дн. назад';
  }

  @override
  String get time_hour => 'час';

  @override
  String get time_hours => 'часов';

  @override
  String get time_day => 'день';

  @override
  String get time_days => 'дней';

  @override
  String get time_week => 'неделя';

  @override
  String get time_weeks => 'недель';

  @override
  String get time_month => 'месяц';

  @override
  String get time_months => 'месяцев';

  @override
  String get time_minutes => 'минут';

  @override
  String get time_allTime => 'Всё время';

  @override
  String get dialog_disconnect => 'Отключиться';

  @override
  String get dialog_disconnectConfirm =>
      'Вы уверены, что хотите отключиться от этого устройства?';

  @override
  String get login_repeaterLogin => 'Вход в репитер';

  @override
  String get login_roomLogin => 'Вход на сервер комнат';

  @override
  String get login_password => 'Пароль';

  @override
  String get login_enterPassword => 'Введите пароль';

  @override
  String get login_savePassword => 'Сохранить пароль';

  @override
  String get login_savePasswordSubtitle =>
      'Пароль будет надёжно сохранён на этом устройстве';

  @override
  String get login_repeaterDescription =>
      'Введите пароль репитера для доступа к настройкам и статусу.';

  @override
  String get login_roomDescription =>
      'Введите пароль комнаты для доступа к настройкам и статусу.';

  @override
  String get login_routing => 'Маршрутизация';

  @override
  String get login_routingMode => 'Режим маршрутизации';

  @override
  String get login_autoUseSavedPath =>
      'Авто (использовать сохранённый маршрут)';

  @override
  String get login_forceFloodMode => 'Принудительный режим flood';

  @override
  String get login_managePaths => 'Управление маршрутами';

  @override
  String get login_login => 'Войти';

  @override
  String login_attempt(int current, int max) {
    return 'Попытка $current/$max';
  }

  @override
  String login_failed(String error) {
    return 'Ошибка входа: $error';
  }

  @override
  String get login_failedMessage =>
      'Не удалось войти. Либо пароль неверен, либо репитер недоступен.';

  @override
  String get common_reload => 'Обновить';

  @override
  String get path_currentPathLabel => 'Текущий маршрут';

  @override
  String get path_noRepeatersFound => 'Репитеры или серверы комнат не найдены.';

  @override
  String get repeater_management => 'Управление репитером';

  @override
  String get room_management => 'Управление сервером комнат';

  @override
  String get repeater_guest => 'Информация о репитере';

  @override
  String get room_guest => 'Информация о сервере';

  @override
  String get repeater_managementTools => 'Инструменты управления';

  @override
  String get repeater_guestTools => 'Инструменты для гостей';

  @override
  String get repeater_status => 'Статус';

  @override
  String get repeater_statusSubtitle =>
      'Просмотр статуса, статистики и соседей репитера';

  @override
  String get repeater_telemetry => 'Телеметрия';

  @override
  String get repeater_telemetrySubtitle =>
      'Просмотр телеметрии датчиков и системной статистики';

  @override
  String get repeater_cli => 'CLI';

  @override
  String get repeater_cliSubtitle => 'Отправка команд репитеру';

  @override
  String get repeater_neighbors => 'Соседи';

  @override
  String get repeater_neighborsSubtitle => 'Просмотр соседей на нулевом хопе.';

  @override
  String get repeater_settings => 'Настройки';

  @override
  String get repeater_settingsSubtitle => 'Настройка параметров репитера';

  @override
  String get repeater_clockSyncAfterLogin =>
      'Синхронизация часов после входа в систему';

  @override
  String get repeater_clockSyncAfterLoginSubtitle =>
      'Автоматически отправлять сообщение \"синхронизация времени\" после успешной авторизации.';

  @override
  String get repeater_statusTitle => 'Статус репитера';

  @override
  String get repeater_routingMode => 'Режим маршрутизации';

  @override
  String get repeater_refresh => 'Обновить';

  @override
  String get repeater_statusRequestTimeout => 'Время ожидания статуса истекло.';

  @override
  String repeater_errorLoadingStatus(String error) {
    return 'Ошибка загрузки статуса: $error';
  }

  @override
  String get repeater_systemInformation => 'Системная информация';

  @override
  String get repeater_battery => 'Батарея';

  @override
  String get repeater_clockAtLogin => 'Время (при входе)';

  @override
  String get repeater_uptime => 'Время работы';

  @override
  String get repeater_queueLength => 'Длина очереди';

  @override
  String get repeater_debugFlags => 'Флаги отладки';

  @override
  String get repeater_radioStatistics => 'Радиостатистика';

  @override
  String get repeater_lastRssi => 'Последний RSSI';

  @override
  String get repeater_lastSnr => 'Последний SNR';

  @override
  String get repeater_noiseFloor => 'Уровень шума';

  @override
  String get repeater_txAirtime => 'Время эфира (передача)';

  @override
  String get repeater_rxAirtime => 'Время эфира (приём)';

  @override
  String get repeater_chanUtil => 'Использование канала';

  @override
  String get repeater_packetStatistics => 'Статистика пакетов';

  @override
  String get repeater_sent => 'Отправлено';

  @override
  String get repeater_received => 'Получено';

  @override
  String get repeater_duplicates => 'Дубликаты';

  @override
  String repeater_daysHoursMinsSecs(
    int days,
    int hours,
    int minutes,
    int seconds,
  ) {
    return '$days дн. $hoursч $minutesм $secondsс';
  }

  @override
  String repeater_packetTxTotal(int total, String flood, String direct) {
    return 'Всего: $total, flood: $flood, прямые: $direct';
  }

  @override
  String repeater_packetRxTotal(int total, String flood, String direct) {
    return 'Всего: $total, flood: $flood, прямые: $direct';
  }

  @override
  String repeater_duplicatesFloodDirect(String flood, String direct) {
    return 'Flood: $flood, прямые: $direct';
  }

  @override
  String repeater_duplicatesTotal(int total) {
    return 'Всего: $total';
  }

  @override
  String get repeater_settingsTitle => 'Настройки репитера';

  @override
  String get repeater_basicSettings => 'Основные настройки';

  @override
  String get repeater_repeaterName => 'Имя репитера';

  @override
  String get repeater_repeaterNameHelper => 'Отображаемое имя этого репитера';

  @override
  String get repeater_adminPassword => 'Пароль администратора';

  @override
  String get repeater_adminPasswordHelper => 'Пароль с полным доступом';

  @override
  String get repeater_guestPassword => 'Гостевой пароль';

  @override
  String get repeater_guestPasswordHelper =>
      'Пароль для доступа только для чтения';

  @override
  String get repeater_radioSettings => 'Настройки радио';

  @override
  String get repeater_frequencyMhz => 'Частота (МГц)';

  @override
  String get repeater_frequencyHelper => '300–2500 МГц';

  @override
  String get repeater_txPower => 'Мощность передачи';

  @override
  String get repeater_txPowerHelper => '1–30 дБм';

  @override
  String get repeater_bandwidth => 'Полоса пропускания';

  @override
  String get repeater_spreadingFactor => 'Коэффициент расширения';

  @override
  String get repeater_codingRate => 'Коэффициент кодирования';

  @override
  String get repeater_locationSettings => 'Настройки местоположения';

  @override
  String get repeater_latitude => 'Широта';

  @override
  String get repeater_latitudeHelper =>
      'В десятичных градусах (напр., 37.7749)';

  @override
  String get repeater_longitude => 'Долгота';

  @override
  String get repeater_longitudeHelper =>
      'В десятичных градусах (напр., -122.4194)';

  @override
  String get repeater_features => 'Функции';

  @override
  String get repeater_packetForwarding => 'Пересылка пакетов';

  @override
  String get repeater_packetForwardingSubtitle =>
      'Разрешить репитеру пересылать пакеты';

  @override
  String get repeater_guestAccess => 'Гостевой доступ';

  @override
  String get repeater_guestAccessSubtitle =>
      'Разрешить гостевой доступ только для чтения';

  @override
  String get repeater_privacyMode => 'Режим конфиденциальности';

  @override
  String get repeater_privacyModeSubtitle =>
      'Скрывать имя/местоположение в анонсах';

  @override
  String get repeater_advertisementSettings => 'Настройки анонсов';

  @override
  String get repeater_localAdvertInterval => 'Интервал локальных анонсов';

  @override
  String repeater_localAdvertIntervalMinutes(int minutes) {
    return '$minutes минут';
  }

  @override
  String get repeater_floodAdvertInterval => 'Интервал flood-анонсов';

  @override
  String repeater_floodAdvertIntervalHours(int hours) {
    return '$hours часов';
  }

  @override
  String get repeater_encryptedAdvertInterval =>
      'Интервал зашифрованных анонсов';

  @override
  String get repeater_dangerZone => 'Опасная зона';

  @override
  String get repeater_rebootRepeater => 'Перезагрузить репитер';

  @override
  String get repeater_rebootRepeaterSubtitle =>
      'Перезапустить устройство репитера';

  @override
  String get repeater_rebootRepeaterConfirm =>
      'Вы уверены, что хотите перезагрузить этот репитер?';

  @override
  String get repeater_regenerateIdentityKey => 'Пересоздать ключ идентификации';

  @override
  String get repeater_regenerateIdentityKeySubtitle =>
      'Сгенерировать новую пару публичного/приватного ключей';

  @override
  String get repeater_regenerateIdentityKeyConfirm =>
      'Это создаст новую идентичность для репитера. Продолжить?';

  @override
  String get repeater_eraseFileSystem => 'Стереть файловую систему';

  @override
  String get repeater_eraseFileSystemSubtitle =>
      'Отформатировать файловую систему репитера';

  @override
  String get repeater_eraseFileSystemConfirm =>
      'ВНИМАНИЕ: это удалит все данные на репитере. Действие нельзя отменить!';

  @override
  String get repeater_eraseSerialOnly =>
      'Очистка доступна только через последовательную консоль.';

  @override
  String repeater_commandSent(String command) {
    return 'Команда отправлена: $command';
  }

  @override
  String repeater_errorSendingCommand(String error) {
    return 'Ошибка отправки команды: $error';
  }

  @override
  String get repeater_confirm => 'Подтвердить';

  @override
  String get repeater_settingsSaved => 'Настройки успешно сохранены';

  @override
  String get repeater_rxGain => 'Увеличенная эффективность RX';

  @override
  String get repeater_rxGainHelper =>
      'Более высокая чувствительность, больший ток потребления (только для SX1262/SX1268)';

  @override
  String get repeater_refreshRxGain => 'Обновите усиление RX';

  @override
  String get repeater_multiAcks => 'Несколько подтверждений';

  @override
  String get repeater_multiAcksSubtitle =>
      'Обеспечьте доставку сообщений по нескольким каналам для повышения эффективности.';

  @override
  String get repeater_refreshMultiAcks => 'Обновление нескольких подтверждений';

  @override
  String get repeater_networkHealth => 'Состояние сети';

  @override
  String get repeater_loopDetect => 'Обнаружение циклов';

  @override
  String get repeater_loopDetectHelper =>
      'Отбрасывать flood-пакеты, похожие на петли маршрутизации';

  @override
  String get repeater_loopDetectOff => 'Отключено';

  @override
  String get repeater_loopDetectMinimal => 'Минимальный';

  @override
  String get repeater_loopDetectModerate => 'Умеренный';

  @override
  String get repeater_loopDetectStrict => 'Строгий';

  @override
  String get repeater_dutyCycle => 'Цикл работы';

  @override
  String get repeater_dutyCycleHelper =>
      'Максимальный процент времени, выделенного на трансляцию.';

  @override
  String repeater_dutyCyclePercent(int percent) {
    return '$percent%';
  }

  @override
  String get repeater_ownerInfo => 'Информация о операторе';

  @override
  String get repeater_ownerInfoHelper => 'Публичные метаданные этого репитера';

  @override
  String get repeater_refreshOwnerInfo => 'Обновить информацию о операторе';

  @override
  String get repeater_floodMax => 'Максимум хопов flood';

  @override
  String get repeater_floodMaxHelper =>
      'Максимальное число хопов, которое может пройти flood-пакет (0–64)';

  @override
  String get repeater_advancedSettings => 'Продвинутый';

  @override
  String get repeater_advancedSettingsSubtitle =>
      'Регуляторы для опытных операторов';

  @override
  String get repeater_pathHashMode => 'Режим хеширования пути';

  @override
  String get repeater_pathHashModeHelper =>
      'Байты, используемые для кодирования идентификатора этого ретранслятора в тегах flood-маршрута/обнаружения циклов. 0 = 1 байт (256 идентификаторов, до 64 переходов), 1 = 2 байта (65 000 идентификаторов, до 32 переходов), 2 = 3 байта (16 миллионов идентификаторов, до 21 перехода). Прошивки до v1.14 всегда использовали 1-байтовые маршруты; v1.14 и новее можно настроить на 2- или 3-байтовые маршруты.';

  @override
  String get repeater_keySettings => 'Смена ключей узла';

  @override
  String get repeater_keySettingsSubtitle =>
      'Изменить пару публичного и приватного ключей';

  @override
  String get repeater_prvKey => 'Приватный ключ';

  @override
  String get repeater_prvKeyHelper =>
      'Новый приватный ключ ретранслятора — hex-строка из 128 символов.';

  @override
  String get repeater_generatePrvKey => 'Сгенерировать случайную пару ключей';

  @override
  String get repeater_stopGeneratingPrvKey => 'Прервать поиск пары ключей';

  @override
  String get repeater_pubKey => 'Публичный ключ';

  @override
  String get repeater_pubKeyHelper =>
      'Это публичный ключ, соответствующий сгенерированному приватному. Задать его напрямую нельзя.';

  @override
  String get repeater_pubKeyPrefix => 'Желаемый префикс';

  @override
  String repeater_pubKeyPrefixHelper(int tries) {
    return 'Поиск публичного ключа, начинающегося с этих hex-символов. Ожидаемое число попыток: $tries.';
  }

  @override
  String get repeater_txDelay => 'Задержка в работе системы Flood TX';

  @override
  String get repeater_txDelayHelper =>
      'Интервал ретрансляции для flood-трафика как множитель времени пакета в эфире (0–2, по умолчанию 0,5). Чем выше значение, тем меньше коллизий, но тем медленнее доставка.';

  @override
  String get repeater_directTxDelay => 'Прямая задержка сигнала TX';

  @override
  String get repeater_directTxDelayHelper =>
      'Интервал ретрансляции для прямого (не flood) трафика как множитель времени пакета в эфире (0–2, по умолчанию 0,3).';

  @override
  String get repeater_intThresh => 'Пороговое значение помех';

  @override
  String get repeater_intThreshHelper =>
      'Порог устанавливается для калибровки уровня шума радио, чтобы оно отсеивало помехи, превышающие этот уровень. Значение \"0\" означает отключение – используйте только в случае, если вы наблюдаете ошибки при приеме сигнала в шумном диапазоне.';

  @override
  String get repeater_agcResetInterval => 'Интервал сброса AGC';

  @override
  String get repeater_agcResetIntervalHelper =>
      'Как часто следует сбрасывать автоматическую регулировку усиления радио, чтобы вернуться к нормальному состоянию после заклинивания? Интервал сброса составляет несколько секунд, кратный 4. Отключение периодического сброса осуществляется с помощью параметра 0.';

  @override
  String get repeater_actionsTitle => 'Действия';

  @override
  String get repeater_sendAdvert => 'Отправить flood-анонс';

  @override
  String get repeater_sendAdvertSubtitle => 'Передать flood-анонс через сеть';

  @override
  String get repeater_sendAdvertZeroHop => 'Отправить анонс нулевого хопа';

  @override
  String get repeater_sendAdvertZeroHopSubtitle =>
      'Передать анонс в один хоп (без репитеров)';

  @override
  String get repeater_clockSync => 'Синхронизировать время сейчас';

  @override
  String get repeater_clockSyncSubtitle =>
      'Отправить время телефона на репитер';

  @override
  String repeater_actionSucceeded(String action) {
    return '$action: выполнено';
  }

  @override
  String repeater_actionFailed(String action, String error) {
    return '$action: ошибка: $error';
  }

  @override
  String get repeater_settingsSavedRebootNeeded =>
      'Настройки сохранены — перезагрузите ретранслятор, чтобы применить их.';

  @override
  String repeater_settingsPartialFailure(String failures) {
    return 'Некоторые настройки не удалось применить: $failures';
  }

  @override
  String repeater_errorSavingSettings(String error) {
    return 'Ошибка сохранения настроек: $error';
  }

  @override
  String get repeater_refreshBasicSettings => 'Обновить основные настройки';

  @override
  String get repeater_refreshRadioSettings => 'Обновить настройки радио';

  @override
  String get repeater_refreshTxPower => 'Обновить мощность передачи';

  @override
  String get repeater_refreshPacketForwarding => 'Обновить пересылку пакетов';

  @override
  String get repeater_refreshGuestAccess => 'Обновить гостевой доступ';

  @override
  String get repeater_refreshPrivacyMode => 'Обновить режим конфиденциальности';

  @override
  String repeater_refreshed(String label) {
    return '$label обновлён';
  }

  @override
  String repeater_errorRefreshing(String label) {
    return 'Ошибка обновления $label';
  }

  @override
  String get repeater_cliTitle => 'CLI репитера';

  @override
  String get repeater_debugNextCommand => 'Отладка следующей команды';

  @override
  String get repeater_commandHelp => 'Справка по командам';

  @override
  String get repeater_clearHistory => 'Очистить историю';

  @override
  String get repeater_noCommandsSent => 'Команды ещё не отправлялись';

  @override
  String get repeater_typeCommandOrUseQuick =>
      'Введите команду ниже или используйте быстрые команды';

  @override
  String get repeater_enterCommandHint => 'Введите команду...';

  @override
  String get repeater_previousCommand => 'Предыдущая команда';

  @override
  String get repeater_nextCommand => 'Следующая команда';

  @override
  String get repeater_enterCommandFirst => 'Сначала введите команду';

  @override
  String get repeater_cliCommandFrameTitle => 'Фрейм CLI-команды';

  @override
  String repeater_cliCommandError(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get repeater_cliQuickGetName => 'Получить имя';

  @override
  String get repeater_cliQuickGetRadio => 'Получить радио';

  @override
  String get repeater_cliQuickGetTx => 'Получить TX';

  @override
  String get repeater_cliQuickNeighbors => 'Соседи';

  @override
  String get repeater_cliQuickVersion => 'Версия';

  @override
  String get repeater_cliQuickAdvertise => 'Анонсировать';

  @override
  String get repeater_cliQuickClock => 'Время';

  @override
  String get repeater_cliQuickClockSync => 'Синхронизация часов';

  @override
  String get repeater_cliQuickDiscovery => 'Обнаружить Соседей';

  @override
  String get repeater_cliHelpAdvert => 'Отправляет пакет анонса';

  @override
  String get repeater_cliHelpReboot =>
      'Перезагружает устройство. (обычно вы получите «Тайм-аут» — это нормально)';

  @override
  String get repeater_cliHelpClock =>
      'Показывает текущее время по часам устройства.';

  @override
  String get repeater_cliHelpPassword =>
      'Устанавливает новый пароль администратора для устройства.';

  @override
  String get repeater_cliHelpVersion =>
      'Показывает версию устройства и дату сборки прошивки.';

  @override
  String get repeater_cliHelpClearStats =>
      'Сбрасывает различные счётчики статистики в ноль.';

  @override
  String get repeater_cliHelpSetAf =>
      'Устанавливает коэффициент времени в эфире.';

  @override
  String get repeater_cliHelpSetTx =>
      'Устанавливает мощность передачи LoRa в дБм. (требуется перезагрузка)';

  @override
  String get repeater_cliHelpSetRepeat =>
      'Включает или отключает роль репитера для этой ноды.';

  @override
  String get repeater_cliHelpSetAllowReadOnly =>
      '(Сервер комнат) Если «on», то вход без пароля разрешён, но публиковать в комнату нельзя (только чтение)';

  @override
  String get repeater_cliHelpSetFloodMax =>
      'Устанавливает максимальное число хопов для входящего flood-пакета (если >= максимум, пакет не пересылается).';

  @override
  String get repeater_cliHelpSetIntThresh =>
      'Устанавливает порог интерференции (в дБ). По умолчанию 14. Установите 0, чтобы отключить обнаружение помех.';

  @override
  String get repeater_cliHelpSetAgcResetInterval =>
      'Устанавливает интервал сброса автоматической регулировки усиления. Установите 0, чтобы отключить.';

  @override
  String get repeater_cliHelpSetMultiAcks =>
      'Включает или отключает функцию «двойных ACK».';

  @override
  String get repeater_cliHelpSetAdvertInterval =>
      'Устанавливает интервал (в минутах) отправки локального анонса (нулевой хоп). Установите 0, чтобы отключить.';

  @override
  String get repeater_cliHelpSetFloodAdvertInterval =>
      'Устанавливает интервал (в часах) отправки flood-анонса. Установите 0, чтобы отключить.';

  @override
  String get repeater_cliHelpSetGuestPassword =>
      'Устанавливает/обновляет гостевой пароль. (для репитеров гости могут отправлять запрос «Get Stats»)';

  @override
  String get repeater_cliHelpSetName => 'Устанавливает имя в оповещениях.';

  @override
  String get repeater_cliHelpSetLat =>
      'Устанавливает широту для карты в анонсе (десятичные градусы).';

  @override
  String get repeater_cliHelpSetLon =>
      'Устанавливает долготу для карты в анонсе (десятичные градусы).';

  @override
  String get repeater_cliHelpSetRadio =>
      'Устанавливает полностью новые параметры радио и сохраняет их в настройки. Требуется команда «reboot» для применения.';

  @override
  String get repeater_cliHelpSetRxDelay =>
      'Устанавливает (экспериментально) базовую задержку (>1 для эффекта) для принятых пакетов на основе качества сигнала. Установите 0, чтобы отключить.';

  @override
  String get repeater_cliHelpSetTxDelay =>
      'Устанавливает множитель времени в эфире для пакета в режиме flood и применяет случайную задержку перед пересылкой (чтобы уменьшить коллизии).';

  @override
  String get repeater_cliHelpSetDirectTxDelay =>
      'То же, что txdelay, но для случайной задержки пересылки пакетов в прямом режиме.';

  @override
  String get repeater_cliHelpSetBridgeEnabled => 'Включить/выключить мост.';

  @override
  String get repeater_cliHelpSetBridgeDelay =>
      'Установить задержку перед ретрансляцией пакетов.';

  @override
  String get repeater_cliHelpSetBridgeSource =>
      'Выбрать, будет ли мост ретранслировать полученные или отправленные пакеты.';

  @override
  String get repeater_cliHelpSetBridgeBaud =>
      'Установить скорость последовательного соединения для мостов RS232.';

  @override
  String get repeater_cliHelpSetBridgeSecret =>
      'Установить секрет моста для мостов ESP-NOW.';

  @override
  String get repeater_cliHelpSetAdcMultiplier =>
      'Устанавливает пользовательский коэффициент коррекции напряжения батареи (поддерживается только на некоторых платах).';

  @override
  String get repeater_cliHelpTempRadio =>
      'Устанавливает временные параметры радио на заданное число минут, затем возвращает исходные. (НЕ сохраняется в настройки).';

  @override
  String get repeater_cliHelpSetPerm =>
      'Изменяет ACL. Удаляет запись (по префиксу публичного ключа), если «permissions» равен нулю. Добавляет новую запись, если указан полный ключ и он отсутствует в ACL. Обновляет запись по совпадению префикса. Биты прав зависят от роли прошивки, но младшие 2 бита: 0 (Гость), 1 (Только чтение), 2 (Чтение/запись), 3 (Админ)';

  @override
  String get repeater_cliHelpGetBridgeType =>
      'Получает тип моста: none, rs232, espnow';

  @override
  String get repeater_cliHelpLogStart =>
      'Начинает запись пакетов в файловую систему.';

  @override
  String get repeater_cliHelpLogStop =>
      'Останавливает запись пакетов в файловую систему.';

  @override
  String get repeater_cliHelpLogErase =>
      'Удаляет журналы пакетов из файловой системы.';

  @override
  String get repeater_cliHelpNeighbors =>
      'Показывает список других репитеров, услышанных через анонсы нулевого хопа. Каждая строка: id-префикс-hex:временная-метка:snr×4';

  @override
  String get repeater_cliHelpNeighborRemove =>
      'Удаляет первую подходящую запись (по префиксу публичного ключа в hex) из списка соседей.';

  @override
  String get repeater_cliHelpRegion =>
      '(только через последовательный порт) Показывает все заданные регионы и текущие разрешения flood.';

  @override
  String get repeater_cliHelpRegionLoad =>
      'ПРИМЕЧАНИЕ: это специальная многострочная команда. Каждая следующая строка — имя региона (с отступом пробелами для указания иерархии, минимум один пробел). Завершается пустой строкой.';

  @override
  String get repeater_cliHelpRegionGet =>
      'Ищет регион по префиксу имени (или «*» для глобальной области). Отвечает: «-> имя-региона (родитель) \'F\'»';

  @override
  String get repeater_cliHelpRegionPut =>
      'Добавляет или обновляет определение региона с заданным именем.';

  @override
  String get repeater_cliHelpRegionRemove =>
      'Удаляет определение региона с заданным именем. (должно точно совпадать и не иметь дочерних регионов)';

  @override
  String get repeater_cliHelpRegionAllowf =>
      'Разрешает рассылку («F»lood) для заданного региона. («*» для глобальной/устаревшей области)';

  @override
  String get repeater_cliHelpRegionDenyf =>
      'Запрещает рассылку («F»lood) для заданного региона. (НЕ рекомендуется для глобальной/устаревшей области!)';

  @override
  String get repeater_cliHelpRegionHome =>
      'Показывает текущий «домашний» регион. (Пока не используется, зарезервировано на будущее)';

  @override
  String get repeater_cliHelpRegionHomeSet =>
      'Устанавливает «домашний» регион.';

  @override
  String get repeater_cliHelpRegionSave =>
      'Сохраняет список/карту регионов в память.';

  @override
  String get repeater_cliHelpGps =>
      'Показывает статус GPS. Если GPS выключен, отвечает только «off»; если включён — возвращает on, status, fix и количество спутников.';

  @override
  String get repeater_cliHelpGpsOnOff => 'Переключает состояние питания GPS.';

  @override
  String get repeater_cliHelpGpsSync =>
      'Синхронизирует время ноды с часами GPS.';

  @override
  String get repeater_cliHelpGpsSetLoc =>
      'Устанавливает позицию ноды по координатам GPS и сохраняет в настройки.';

  @override
  String get repeater_cliHelpGpsAdvert =>
      'Показывает конфигурацию передачи местоположения в анонсах этой ноды:\n- none: не включать местоположение в анонсы\n- share: передавать GPS-координаты (из SensorManager)\n- prefs: передавать координаты из настроек';

  @override
  String get repeater_cliHelpGpsAdvertSet =>
      'Устанавливает конфигурацию местоположения в анонсах.';

  @override
  String get repeater_commandsListTitle => 'Список команд';

  @override
  String get repeater_commandsListNote =>
      'ПРИМЕЧАНИЕ: для большинства команд «set ...» существуют соответствующие команды «get ...».';

  @override
  String get repeater_general => 'Общие';

  @override
  String get repeater_settingsCategory => 'Настройки';

  @override
  String get repeater_bridge => 'Мост';

  @override
  String get repeater_logging => 'Журналирование';

  @override
  String get repeater_neighborsRepeaterOnly => 'Соседи (только для репитеров)';

  @override
  String get repeater_regionManagementRepeaterOnly =>
      'Управление регионами (только для репитеров)';

  @override
  String get repeater_regionNote =>
      'Команды регионов введены для управления определениями регионов и правами доступа.';

  @override
  String get repeater_gpsManagement => 'Управление GPS';

  @override
  String get repeater_gpsNote =>
      'Команда gps введена для управления параметрами, связанными с местоположением.';

  @override
  String get repeater_getCategory => 'Получить значения';

  @override
  String get repeater_powerMgmt => 'Управление энергопотреблением';

  @override
  String get repeater_sensors => 'Датчики';

  @override
  String get repeater_cliHelpPowerOff =>
      'Отключает устройство. (ожидается отсутствие ответа).';

  @override
  String get repeater_cliHelpClkReboot =>
      'Сбрасывает часы до известной эпохи и перезапускает устройство.';

  @override
  String get repeater_cliHelpAdvertZeroHop =>
      'Отправляет zero-hop анонс (только ближайшим соседям).';

  @override
  String get repeater_cliHelpStartOta =>
      'Запускает обновление прошивки по воздуху на поддерживаемых устройствах.';

  @override
  String get repeater_cliHelpTime =>
      'Устанавливает время устройства в соответствии с заданными секундами от начала эпохи Unix. Время не может сброситься назад.';

  @override
  String get repeater_cliHelpBoard =>
      'Отображает информацию о производителе платы / идентификатор аппаратного обеспечения.';

  @override
  String get repeater_cliHelpDiscoverNeighbors =>
      'Отправляет запрос на обнаружение соседних узлов. (Только для ретранслятора)';

  @override
  String get repeater_cliHelpPowersaving =>
      'Показывает, включен ли режим экономии энергии.';

  @override
  String get repeater_cliHelpPowersavingOnOff =>
      'Включает или выключает режим экономии энергии (если он поддерживается).';

  @override
  String get repeater_cliHelpErase =>
      '(Только через последовательный порт) Форматирует файловую систему устройства. Удаляет все настройки и контакты.';

  @override
  String get repeater_cliHelpSetDutyCycle =>
      'Устанавливает максимальный допустимый цикл передачи данных в процентах (от 1 до 100). Внутренне корректирует коэффициент времени передачи.';

  @override
  String get repeater_cliHelpSetPrvKey =>
      '(Только через последовательный порт) Заменяет приватный ключ, идентифицирующий устройство. Требуется перезагрузка для применения. Генерирует новый публичный ключ.';

  @override
  String get repeater_cliHelpSetRadioRxGain =>
      '(Только для SX126x) Переключает усиление RX для повышения чувствительности при больших токах потребления.';

  @override
  String get repeater_cliHelpSetOwnerInfo =>
      'Устанавливает строку с контактной информацией владельца, включаемую в анонсы. Используйте \'|\' для переносов строк.';

  @override
  String get repeater_cliHelpSetPathHashMode =>
      'Устанавливает режим хеширования пути. 0 = устаревший, 1 = стандартный, 2 = строгий. Влияет на то, как определяются маршруты.';

  @override
  String get repeater_cliHelpSetLoopDetect =>
      'Устанавливает чувствительность обнаружения циклов маршрутизации: \"выключено\", \"минимальная\", \"умеренная\" или \"строгая\".';

  @override
  String get repeater_cliHelpSetFreq =>
      '(Только для настройки) Быстро устанавливает только частоту. Требуется перезагрузка. Рекомендуется использовать функцию \"настройка радио\" для полного набора параметров.';

  @override
  String get repeater_cliHelpSetBridgeChannel =>
      '(Только для моста ESPNow) Устанавливает канал Wi-Fi (от 1 до 14), используемый мостом.';

  @override
  String get repeater_cliHelpGetName => 'Отображает имя настроенного узла.';

  @override
  String get repeater_cliHelpGetRole =>
      'Отображает роль прошивки (ретранслятор, сервер комнаты и т.д.).';

  @override
  String get repeater_cliHelpGetPublicKey =>
      'Отображает открытый ключ устройства.';

  @override
  String get repeater_cliHelpGetPrvKey =>
      '(Только через последовательный порт) Показывает приватный ключ устройства. Считайте его секретной информацией.';

  @override
  String get repeater_cliHelpGetRepeat =>
      'Показывает, включена ли пересылка пакетов (роль репитера).';

  @override
  String get repeater_cliHelpGetTx =>
      'Отображает текущую мощность передатчика в дБм.';

  @override
  String get repeater_cliHelpGetFreq =>
      'Отображает настроенную частоту радиосигнала в мегагерцах.';

  @override
  String get repeater_cliHelpGetRadio =>
      'Отображает все параметры радиосигнала: частоту, полосу пропускания, коэффициент модуляции, скорость кодирования.';

  @override
  String get repeater_cliHelpGetRadioRxGain =>
      '(Только для SX126x) Отображает состояние усиления сигнала на входе RX.';

  @override
  String get repeater_cliHelpGetAf =>
      'Отображает текущий коэффициент времени эфира.';

  @override
  String get repeater_cliHelpGetDutyCycle =>
      'Отображает текущий допустимый цикл работы в процентах.';

  @override
  String get repeater_cliHelpGetIntThresh =>
      'Отображает порог помех в децибелах.';

  @override
  String get repeater_cliHelpGetAgcResetInterval =>
      'Отображает интервал сброса автоматической регулировки усиления в секундах.';

  @override
  String get repeater_cliHelpGetMultiAcks =>
      'Показывает, включен ли режим двойной подтверждения (1) или выключен (0).';

  @override
  String get repeater_cliHelpGetAllowReadOnly =>
      'Отображает, разрешен ли доступ для чтения только для гостей.';

  @override
  String get repeater_cliHelpGetAdvertInterval =>
      'Показывает интервал локальных анонсов в минутах.';

  @override
  String get repeater_cliHelpGetFloodAdvertInterval =>
      'Показывает интервал flood-анонсов в часах.';

  @override
  String get repeater_cliHelpGetGuestPassword =>
      'Отображает установленный пароль для гостя.';

  @override
  String get repeater_cliHelpGetLat => 'Отображает заданную широту.';

  @override
  String get repeater_cliHelpGetLon => 'Отображает заданную долготу.';

  @override
  String get repeater_cliHelpGetRxDelay =>
      'Отображает базовое значение задержки.';

  @override
  String get repeater_cliHelpGetTxDelay =>
      'Показывает коэффициент txdelay в режиме flood.';

  @override
  String get repeater_cliHelpGetDirectTxDelay =>
      'Отображает коэффициент задержки в режиме прямого подключения.';

  @override
  String get repeater_cliHelpGetFloodMax =>
      'Показывает максимальное количество хопов в режиме flood.';

  @override
  String get repeater_cliHelpGetOwnerInfo =>
      'Отображает строку с контактной информацией владельца.';

  @override
  String get repeater_cliHelpGetPathHashMode =>
      'Отображает режим работы с хэшем пути (0/1/2).';

  @override
  String get repeater_cliHelpGetLoopDetect =>
      'Отображает чувствительность к обнаружению циклов.';

  @override
  String get repeater_cliHelpGetAcl =>
      '(Только через последовательный порт) Перечисляет записи управления доступом на репитере.';

  @override
  String get repeater_cliHelpGetBridgeEnabled =>
      'Показывает, включена ли функция моста.';

  @override
  String get repeater_cliHelpGetBridgeDelay =>
      'Отображает задержку в миллисекундах.';

  @override
  String get repeater_cliHelpGetBridgeSource =>
      'Отображает, какие пакеты RX или TX передаются через мост.';

  @override
  String get repeater_cliHelpGetBridgeBaud =>
      '(Только для интерфейса RS232) Отображает скорость передачи данных на интерфейсе RS232.';

  @override
  String get repeater_cliHelpGetBridgeChannel =>
      '(Только для моста ESPNow) Отображает канал WiFi, используемый мостом.';

  @override
  String get repeater_cliHelpGetBridgeSecret =>
      '(Только для моста ESPNow) Отображает общий секрет, используемый мостом.';

  @override
  String get repeater_cliHelpGetBootloaderVer =>
      '(Только для NRF52) Отображает версию загрузчика.';

  @override
  String get repeater_cliHelpGetAdcMultiplier =>
      'Отображает коэффициент умножения аналого-цифрового преобразователя (масштабирование напряжения от батареи).';

  @override
  String get repeater_cliHelpGetPwrMgtSupport =>
      'Сообщает, поддерживает ли плата управление питанием.';

  @override
  String get repeater_cliHelpGetPwrMgtSource =>
      'Отображает текущий источник питания: внешний или аккумулятор.';

  @override
  String get repeater_cliHelpGetPwrMgtBootReason =>
      'Отображает последние причины сброса и выключения.';

  @override
  String get repeater_cliHelpGetPwrMgtBootMv =>
      'Отображает напряжение батареи при запуске системы в милливольтах (мВ).';

  @override
  String get repeater_cliHelpSensorGet =>
      'Считывает пользовательское значение для датчика по указанному ключу.';

  @override
  String get repeater_cliHelpSensorSet =>
      'Создает пользовательские настройки для датчика.';

  @override
  String get repeater_cliHelpSensorList =>
      'Перечисляет все пользовательские настройки датчиков, разбитые на страницы с возможностью указания начального индекса.';

  @override
  String get repeater_cliHelpRegionDefault =>
      'Показывает текущую область региона по умолчанию.';

  @override
  String get repeater_cliHelpRegionDefaultSet =>
      'Устанавливает значение региона по умолчанию. Используйте \"<null>\", чтобы сбросить значение.';

  @override
  String get repeater_cliHelpRegionListAllowed =>
      'Перечисляет регионы, где разрешён flood-трафик.';

  @override
  String get repeater_cliHelpRegionListDenied =>
      'Перечисляет регионы, где запрещён flood-трафик.';

  @override
  String get repeater_cliHelpStatsPackets =>
      '(Только через последовательный порт) Показывает статистику на уровне пакетов.';

  @override
  String get repeater_cliHelpStatsRadio =>
      '(Только через последовательный порт) Показывает радиостатистику.';

  @override
  String get repeater_cliHelpStatsCore =>
      '(Только через последовательный порт) Показывает статистику ядра прошивки.';

  @override
  String get telemetry_receivedData => 'Полученные телеметрические данные';

  @override
  String get telemetry_requestTimeout => 'Время ожидания телеметрии истекло.';

  @override
  String telemetry_errorLoading(String error) {
    return 'Ошибка загрузки телеметрии: $error';
  }

  @override
  String get telemetry_noData => 'Данные телеметрии недоступны.';

  @override
  String telemetry_channelTitle(int channel) {
    return 'Канал $channel';
  }

  @override
  String get telemetry_batteryLabel => 'Батарея';

  @override
  String get telemetry_voltageLabel => 'Напряжение';

  @override
  String get telemetry_mcuTemperatureLabel => 'Температура МК';

  @override
  String get telemetry_temperatureLabel => 'Температура';

  @override
  String get telemetry_currentLabel => 'Ток';

  @override
  String telemetry_batteryValue(int percent, String volts) {
    return '$percent% / $voltsВ';
  }

  @override
  String telemetry_voltageValue(String volts) {
    return '$voltsВ';
  }

  @override
  String telemetry_currentValue(String amps) {
    return '$ampsА';
  }

  @override
  String telemetry_temperatureValue(String celsius, String fahrenheit) {
    return '$celsius°C / $fahrenheit°F';
  }

  @override
  String get telemetry_digitalInputLabel => 'Цифровой вход';

  @override
  String get telemetry_digitalOutputLabel => 'Цифровой выход';

  @override
  String get telemetry_analogInputLabel => 'Аналоговый вход';

  @override
  String get telemetry_analogOutputLabel => 'Аналоговый выход';

  @override
  String get telemetry_genericLabel => 'Общий датчик';

  @override
  String get telemetry_luminosityLabel => 'Освещённость';

  @override
  String get telemetry_presenceLabel => 'Присутствие';

  @override
  String get telemetry_humidityLabel => 'Влажность';

  @override
  String get telemetry_accelerometerLabel => 'Акселерометр';

  @override
  String get telemetry_pressureLabel => 'Давление';

  @override
  String get telemetry_altitudeLabel => 'Высота';

  @override
  String get telemetry_frequencyLabel => 'Частота';

  @override
  String get telemetry_percentageLabel => 'Процент';

  @override
  String get telemetry_concentrationLabel => 'Концентрация';

  @override
  String get telemetry_powerLabel => 'Мощность';

  @override
  String get telemetry_distanceLabel => 'Расстояние';

  @override
  String get telemetry_energyLabel => 'Энергия';

  @override
  String get telemetry_directionLabel => 'Направление';

  @override
  String get telemetry_timeLabel => 'Время';

  @override
  String get telemetry_gyrometerLabel => 'Гирометр';

  @override
  String get telemetry_colourLabel => 'Цвет';

  @override
  String get telemetry_gpsLabel => 'GPS';

  @override
  String get telemetry_switchLabel => 'Переключатель';

  @override
  String get telemetry_polylineLabel => 'Полилиния';

  @override
  String telemetry_altitudeValue(String meters) {
    return '$meters м';
  }

  @override
  String telemetry_frequencyValue(String hertz) {
    return '$hertz Гц';
  }

  @override
  String telemetry_pressureValue(String hpa) {
    return '$hpa гПа';
  }

  @override
  String telemetry_luminosityValue(String lux) {
    return '$lux лк';
  }

  @override
  String telemetry_powerValue(String watts) {
    return '$watts Вт';
  }

  @override
  String telemetry_distanceValue(String meters) {
    return '$meters м';
  }

  @override
  String telemetry_energyValue(String kilowattHours) {
    return '$kilowattHours кВт⋅ч';
  }

  @override
  String telemetry_directionValue(String degrees) {
    return '$degrees°';
  }

  @override
  String telemetry_concentrationValue(String ppm) {
    return '$ppm ppm';
  }

  @override
  String telemetry_percentageValue(String percent) {
    return '$percent%';
  }

  @override
  String telemetry_analogValue(String value) {
    return '$value';
  }

  @override
  String get telemetry_autoFetchQuantity => 'Количество запросов';

  @override
  String get telemetry_error => 'Не удалось получить данные';

  @override
  String get neighbors_receivedData => 'Полученные данные о соседях';

  @override
  String get neighbors_requestTimedOut =>
      'Время ожидания данных о соседях истекло.';

  @override
  String neighbors_errorLoading(String error) {
    return 'Ошибка загрузки соседей: $error';
  }

  @override
  String get neighbors_repeatersNeighbors => 'Соседи репитера';

  @override
  String get neighbors_noData => 'Данные о соседях недоступны.';

  @override
  String neighbors_unknownContact(String pubkey) {
    return 'Неизвестный $pubkey';
  }

  @override
  String neighbors_heardAgo(String time) {
    return 'Слушал(а): $time назад';
  }

  @override
  String get channelPath_title => 'Путь пакета';

  @override
  String get channelPath_viewMap => 'Посмотреть на карте';

  @override
  String get channelPath_otherObservedPaths => 'Другие наблюдаемые пути';

  @override
  String get channelPath_repeaterHops => 'Хопы через репитеры';

  @override
  String get channelPath_repeaterHopsHighTimeout =>
      'Увеличенный таймаут трассировки пути (10 сек*хопы)';

  @override
  String get channelPath_noHopDetails =>
      'Детали хопов для этого пакета не предоставлены.';

  @override
  String get channelPath_messageDetails => 'Детали сообщения';

  @override
  String get channelPath_senderLabel => 'Отправитель';

  @override
  String get channelPath_timeLabel => 'Время получения/создания';

  @override
  String get channelPath_repeatsLabel => 'Повторы';

  @override
  String channelPath_pathLabel(int index) {
    return 'Путь $index';
  }

  @override
  String get channelPath_observedLabel => 'Наблюдаемый';

  @override
  String channelPath_observedPathTitle(int index, String hops) {
    return 'Наблюдаемый путь $index • $hops';
  }

  @override
  String get channelPath_noLocationData => 'Нет данных о местоположении';

  @override
  String channelPath_timeWithDate(int day, int month, String time) {
    return '$day/$month $time';
  }

  @override
  String channelPath_timeOnly(String time) {
    return '$time';
  }

  @override
  String get channelPath_unknownPath => 'Неизвестный';

  @override
  String get channelPath_floodPath => 'Flood';

  @override
  String get channelPath_directPath => 'Прямой';

  @override
  String channelPath_observedZeroOf(int total) {
    return '0 из $total хопов';
  }

  @override
  String channelPath_observedSomeOf(int observed, int total) {
    return '$observed из $total хопов';
  }

  @override
  String get channelPath_mapTitle => 'Карта пути';

  @override
  String get channelPath_noRepeaterLocations =>
      'Нет данных о местоположении репитеров для этого пути.';

  @override
  String channelPath_primaryPath(int index) {
    return 'Путь $index (Основной)';
  }

  @override
  String get channelPath_pathLabelTitle => 'Путь';

  @override
  String get channelPath_observedPathHeader => 'Наблюдаемый путь';

  @override
  String channelPath_selectedPathLabel(String label, String prefixes) {
    return '$label • $prefixes';
  }

  @override
  String get channelPath_noHopDetailsAvailable =>
      'Детали хопов для этого пакета недоступны.';

  @override
  String get channelPath_unknownRepeater => 'Неизвестный репитер';

  @override
  String get channelPath_outgoingSentByRadioAt =>
      'Ожидало отправки через радио, сек';

  @override
  String get community_title => 'Сообщество';

  @override
  String get community_create => 'Создать сообщество';

  @override
  String get community_createDesc =>
      'Создать новое сообщество и поделиться через QR-код.';

  @override
  String get community_join => 'Присоединиться';

  @override
  String get community_joinTitle => 'Присоединиться к сообществу';

  @override
  String community_joinConfirmation(String name) {
    return 'Вы хотите присоединиться к сообществу  \"$name\"?';
  }

  @override
  String get community_scanQr => 'Сканировать QR-код сообщества';

  @override
  String get community_scanInstructions =>
      'Наведите камеру на QR-код сообщества';

  @override
  String get community_showQr => 'Показать QR-код';

  @override
  String get community_publicChannel => 'Публичный канал сообщества';

  @override
  String get community_hashtagChannel => 'Хэштег-канал сообщества';

  @override
  String get community_name => 'Имя сообщества';

  @override
  String get community_enterName => 'Введите имя сообщества';

  @override
  String community_created(String name) {
    return 'Сообщество \"$name\" создано';
  }

  @override
  String community_joined(String name) {
    return 'Присоединились к сообществу \"$name\"';
  }

  @override
  String get community_qrTitle => 'Поделиться сообществом';

  @override
  String community_qrInstructions(String name) {
    return 'Отсканируйте этот QR-код, чтобы присоединиться к \"$name\"';
  }

  @override
  String get community_hashtagPrivacyHint =>
      'Хэштег-каналы сообщества доступны только его участникам';

  @override
  String get community_invalidQrCode => 'Недопустимый QR-код сообщества';

  @override
  String get community_alreadyMember => 'Уже участник';

  @override
  String community_alreadyMemberMessage(String name) {
    return 'Вы уже участник сообщества \"$name\".';
  }

  @override
  String get community_addPublicChannel =>
      'Добавить публичный канал сообщества';

  @override
  String get community_addPublicChannelHint =>
      'Автоматически добавить публичный канал для этого сообщества';

  @override
  String get community_noCommunities =>
      'Вы ещё не присоединились ни к одному сообществу';

  @override
  String get community_scanOrCreate =>
      'Отсканируйте QR-код или создайте сообщество, чтобы начать';

  @override
  String get community_manageCommunities => 'Управление сообществами';

  @override
  String get community_delete => 'Покинуть сообщество';

  @override
  String community_deleteConfirm(String name) {
    return 'Покинуть \"$name\"?';
  }

  @override
  String community_deleteChannelsWarning(int count) {
    return 'Это также удалит $count канал(ов) и их сообщения.';
  }

  @override
  String community_deleted(String name) {
    return 'Покинули сообщество \"$name\"';
  }

  @override
  String get community_regenerateSecret => 'Пересоздать секрет';

  @override
  String community_regenerateSecretConfirm(String name) {
    return 'Пересоздать секретный ключ для \"$name\"? Все участники должны будут отсканировать новый QR-код для продолжения общения.';
  }

  @override
  String get community_regenerate => 'Пересоздать';

  @override
  String community_secretRegenerated(String name) {
    return 'Секрет пересоздан для \"$name\"';
  }

  @override
  String get community_updateSecret => 'Обновить секрет';

  @override
  String community_secretUpdated(String name) {
    return 'Секрет обновлён для \"$name\"';
  }

  @override
  String community_scanToUpdateSecret(String name) {
    return 'Отсканируйте новый QR-код, чтобы обновить секрет для \"$name\"';
  }

  @override
  String get community_addHashtagChannel => 'Добавить хэштег-канал сообщества';

  @override
  String get community_addHashtagChannelDesc =>
      'Добавить хэштег-канал для этого сообщества';

  @override
  String get community_selectCommunity => 'Выбрать сообщество';

  @override
  String get community_regularHashtag => 'Обычный хэштег';

  @override
  String get community_regularHashtagDesc =>
      'Публичный хэштег (любой может присоединиться)';

  @override
  String get community_communityHashtag => 'Хэштег сообщества';

  @override
  String get community_communityHashtagDesc =>
      'Доступен только участникам сообщества';

  @override
  String community_forCommunity(String name) {
    return 'Для $name';
  }

  @override
  String get listFilter_tooltip => 'Фильтр и сортировка';

  @override
  String get listFilter_sortBy => 'Сортировка по';

  @override
  String get listFilter_latestMessages => 'Последние сообщения';

  @override
  String get listFilter_heardRecently => 'Слышали недавно';

  @override
  String get listFilter_az => 'По алфавиту';

  @override
  String get listFilter_filters => 'Фильтры';

  @override
  String get listFilter_all => 'Все';

  @override
  String get listFilter_favorites => 'Избранное';

  @override
  String get listFilter_addToFavorites => 'Добавить в избранное';

  @override
  String get listFilter_removeFromFavorites => 'Удалить из избранного';

  @override
  String get listFilter_removeFromWardrive => 'Игнорировать в Wardrive';

  @override
  String get listFilter_returnToWardrive => 'Учитывать в Wardrive';

  @override
  String get listFilter_users => 'Пользователи';

  @override
  String get listFilter_repeaters => 'Репитеры';

  @override
  String get listFilter_roomServers => 'Серверы комнат';

  @override
  String get listFilter_unreadOnly => 'Только непрочитанные';

  @override
  String get listFilter_newGroup => 'Новая группа';

  @override
  String get pathTrace_you => 'Вы';

  @override
  String get pathTrace_failed => 'Путь трассировки не выполнен.';

  @override
  String get pathTrace_notAvailable => 'Трассировка пути недоступна.';

  @override
  String get pathTrace_refreshTooltip => 'Обновить трассировку пути.';

  @override
  String get pathTrace_someHopsNoLocation =>
      'У одного или нескольких хопов не указано местоположение!';

  @override
  String get pathTrace_clearTooltip => 'Очистить путь';

  @override
  String get losSelectStartEnd => 'Выберите начальную и конечную ноду для LOS.';

  @override
  String losRunFailed(String error) {
    return 'Проверка прямой видимости не удалась: $error';
  }

  @override
  String get losClearAllPoints => 'Очистить все точки';

  @override
  String get losRunToViewElevationProfile =>
      'Запустите LOS, чтобы просмотреть профиль высот.';

  @override
  String get losMenuTitle => 'ЛОС Меню';

  @override
  String get losMenuSubtitle =>
      'Коснитесь узлов или нажмите и удерживайте карту для выбора пользовательских точек.';

  @override
  String get losShowDisplayNodes => 'Показать узлы отображения';

  @override
  String get losCustomPoints => 'Пользовательские точки';

  @override
  String losCustomPointLabel(int index) {
    return 'Пользовательский $index';
  }

  @override
  String get losPointA => 'Точка А';

  @override
  String get losPointB => 'Точка Б';

  @override
  String losAntennaA(String value, String unit) {
    return 'Антенна А: $value $unit';
  }

  @override
  String losAntennaB(String value, String unit) {
    return 'Антенна Б: $value $unit';
  }

  @override
  String get losRun => 'Запустить ЛОС';

  @override
  String get losNoElevationData => 'Нет данных о высоте';

  @override
  String losProfileClear(
    String distance,
    String distanceUnit,
    String clearance,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, свободная зона видимости, минимальный зазор $clearance $heightUnit';
  }

  @override
  String losProfileBlocked(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit, заблокирован $obstruction $heightUnit';
  }

  @override
  String get losStatusChecking => 'ЛОС: проверяю...';

  @override
  String get losStatusNoData => 'ЛОС: нет данных';

  @override
  String losStatusSummary(int clear, int total, int blocked, int unknown) {
    return 'LOS: $clear/$total без препятствий, $blocked заблокировано, $unknown неизвестно';
  }

  @override
  String get losErrorElevationUnavailable =>
      'Данные о высоте недоступны для одного или нескольких образцов.';

  @override
  String get losErrorInvalidInput =>
      'Неверные данные о точках/высоте для расчета LOS.';

  @override
  String get losRenameCustomPoint => 'Переименовать пользовательскую точку';

  @override
  String get losPointName => 'Имя точки';

  @override
  String get losShowPanelTooltip => 'Показать панель LOS';

  @override
  String get losHidePanelTooltip => 'Скрыть панель LOS';

  @override
  String get losElevationAttribution =>
      'Данные о высоте: Open-Meteo (CC BY 4.0)';

  @override
  String get losLegendRadioHorizon => 'Радиогоризонт';

  @override
  String get losLegendLosBeam => 'Линия прямой видимости';

  @override
  String get losLegendTerrain => 'Рельеф';

  @override
  String get losBlockedSpotsTitle => 'Зарезервированные места';

  @override
  String get losBlockedSpotsHint =>
      'Щелкните по заблокированной области, чтобы выделить ее на карте.';

  @override
  String losBlockedSpotChip(
    String distance,
    String distanceUnit,
    String obstruction,
    String heightUnit,
  ) {
    return '$distance $distanceUnit • $obstruction $heightUnit';
  }

  @override
  String get losSelectedObstructionTitle =>
      'Выбранный объект, препятствующий движению';

  @override
  String losSelectedObstructionDetails(
    String obstruction,
    String heightUnit,
    String distanceFromA,
    String distanceUnit,
    String distanceFromB,
  ) {
    return 'Заблокировано препятствием $obstruction $heightUnit: $distanceFromA от A и $distanceFromB от B ($distanceUnit).';
  }

  @override
  String get losFrequencyLabel => 'Частота';

  @override
  String get losFrequencyInfoTooltip => 'Просмотреть детали расчёта';

  @override
  String get losFrequencyDialogTitle => 'Расчёт радиогоризонта';

  @override
  String losFrequencyDialogDescription(
    double baselineK,
    double baselineFreq,
    double frequencyMHz,
    double kFactor,
  ) {
    return 'Начиная с k=$baselineK на частоте $baselineFreq МГц, расчёт корректирует k-фактор до $kFactor для текущего диапазона $frequencyMHz МГц; он определяет изогнутую границу радиогоризонта.';
  }

  @override
  String get contacts_pathTrace => 'Трассировка пути';

  @override
  String get contacts_ping => 'Пинговать';

  @override
  String get contacts_repeaterPathTrace => 'Отследить путь к ретранслятору';

  @override
  String get contacts_repeaterPing => 'Пинговать репитер';

  @override
  String get contacts_roomPathTrace => 'Трассировка пути к серверу комнаты';

  @override
  String get contacts_roomPing => 'Пинговать сервер комнаты';

  @override
  String get contacts_chatTraceRoute => 'Трассировка маршрута';

  @override
  String contacts_pathTraceTo(String name) {
    return 'Показать маршрут к $name';
  }

  @override
  String get contacts_clipboardEmpty => 'Буфер обмена пуст.';

  @override
  String get contacts_invalidAdvertFormat =>
      'Недействительные контактные данные';

  @override
  String get contacts_contactImported => 'Контакт был импортирован';

  @override
  String get contacts_contactImportFailed => 'Контакт не удалось импортировать';

  @override
  String get contacts_zeroHopAdvert => 'Анонс Zero Hop';

  @override
  String get contacts_floodAdvert => 'Flood-анонс';

  @override
  String get contacts_copyAdvertToClipboard =>
      'Копировать self-ссылку «meshcore://»';

  @override
  String get contacts_addContactFromClipboard =>
      'Добавить контакт из ссылки «meshcore://» из буфера обмена';

  @override
  String get contacts_ShareContact => 'Копировать контакт в буфер обмена';

  @override
  String get contacts_ShareContactZeroHop => 'Поделиться контактом через анонс';

  @override
  String get contacts_zeroHopContactAdvertSent =>
      'Контакт отправлен через анонс.';

  @override
  String get contacts_zeroHopContactAdvertFailed =>
      'Не удалось отправить контакт.';

  @override
  String get contacts_contactAdvertCopied => 'Анонс скопирован в буфер обмена.';

  @override
  String get contacts_contactAdvertCopyFailed =>
      'Не удалось скопировать анонс в буфер обмена.';

  @override
  String get notification_activityTitle => 'Активность MeshCore';

  @override
  String notification_messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'сообщений',
      many: 'сообщений',
      few: 'сообщения',
      one: 'сообщение',
    );
    return '$count $_temp0';
  }

  @override
  String notification_channelMessagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'сообщений канала',
      many: 'сообщений канала',
      few: 'сообщения канала',
      one: 'сообщение канала',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newNodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'новых узлов',
      many: 'новых узлов',
      few: 'новых узла',
      one: 'новый узел',
    );
    return '$count $_temp0';
  }

  @override
  String notification_newTypeDiscovered(String contactType) {
    return 'Обнаружен новый $contactType';
  }

  @override
  String get notification_receivedNewMessage => 'Получено новое сообщение';

  @override
  String get settings_gpxExportRepeaters =>
      'Экспортировать репитеры / сервер комнаты в GPX';

  @override
  String get settings_gpxExportRepeatersSubtitle =>
      'Экспортирует ретрансляторы / серверы комнат с местоположением в файл GPX.';

  @override
  String get settings_gpxExportContacts =>
      'Экспортировать companion-устройства в GPX';

  @override
  String get settings_gpxExportContactsSubtitle =>
      'Экспортирует companion-устройства с местоположением в файл GPX.';

  @override
  String get settings_gpxExportAll => 'Экспортировать все контакты в GPX';

  @override
  String get settings_gpxExportAllSubtitle =>
      'Экспортирует все контакты с местоположением в файл GPX.';

  @override
  String get settings_gpxExportSuccess => 'Успешно экспортирован файл GPX.';

  @override
  String get settings_gpxExportNoContacts => 'Нет контактов для экспорта.';

  @override
  String get settings_gpxExportNotAvailable =>
      'Не поддерживается на вашем устройстве/ОС';

  @override
  String get settings_gpxExportError => 'Произошла ошибка при экспорте.';

  @override
  String get settings_gpxExportRepeatersRoom =>
      'Местоположения повторителей и серверов комнат';

  @override
  String get settings_gpxExportChat => 'Местоположения спутников';

  @override
  String get settings_gpxExportAllContacts => 'Все местоположения контактов';

  @override
  String get settings_gpxExportShareText =>
      'Данные карты экспортированы из meshcore-open';

  @override
  String get settings_gpxExportShareSubject =>
      'meshcore-open экспорт данных карты GPX';

  @override
  String get snrIndicator_nearByRepeaters => 'Ближайшие репитеры';

  @override
  String get snrIndicator_lastSeen => 'Последний раз видели';

  @override
  String get contactsSettings_title => 'Настройки контактов';

  @override
  String get contactsSettings_autoAddTitle => 'Автоматическое обнаружение';

  @override
  String get contactsSettings_otherTitle =>
      'Другие настройки, связанные с контактами';

  @override
  String get contactsSettings_autoAddUsersTitle =>
      'Автоматически добавлять пользователей';

  @override
  String get contactsSettings_autoAddUsersSubtitle =>
      'Разрешить компаньону автоматически добавлять обнаруженных пользователей';

  @override
  String get contactsSettings_autoAddRepeatersTitle =>
      'Автоматически добавлять репитеры';

  @override
  String get contactsSettings_autoAddRepeatersSubtitle =>
      'Разрешить приложению-компаньону автоматически добавлять обнаруженные репитеры';

  @override
  String get contactsSettings_autoAddRoomServersTitle =>
      'Автоматически добавлять серверы комнат';

  @override
  String get contactsSettings_autoAddRoomServersSubtitle =>
      'Разрешить компаньону автоматически добавлять обнаруженные сервера комнат.';

  @override
  String get contactsSettings_autoAddSensorsTitle =>
      'Автоматически добавлять датчики';

  @override
  String get contactsSettings_autoAddSensorsSubtitle =>
      'Разрешить компаньону автоматически добавлять обнаруженные датчики';

  @override
  String get contactsSettings_overwriteOldestTitle =>
      'Перезаписать самое старое';

  @override
  String get contactsSettings_overwriteOldestSubtitle =>
      'Когда список контактов заполнен, будет заменен самый старый контакт, который не находится в избранном.';

  @override
  String get discoveredContacts_Title => 'Добавить обнаруженные контакты';

  @override
  String get discoveredContacts_noMatching => 'Нет совпадающих контактов';

  @override
  String get discoveredContacts_searchHint => 'Найденные контакты поиска';

  @override
  String get discoveredContacts_contactAdded => 'Контакт добавлен';

  @override
  String get discoveredContacts_addContact => 'Добавить контакт';

  @override
  String get discoveredContacts_copyContact =>
      'Копировать контакт в буфер обмена';

  @override
  String get discoveredContacts_deleteContact => 'Удалить контакт';

  @override
  String get discoveredContacts_deleteContactAll =>
      'Удалить Все Обнаруженные Контакты';

  @override
  String get discoveredContacts_deleteContactAllContent =>
      'Вы уверены, что хотите удалить все обнаруженные контакты?';

  @override
  String get chat_sendCooldown =>
      'Пожалуйста, подождите немного, прежде чем отправлять сообщение снова.';

  @override
  String get appSettings_jumpToOldestUnread =>
      'Перейти к самому старому непрочитанному сообщению';

  @override
  String get appSettings_jumpToOldestUnreadSubtitle =>
      'При открытии чата с непрочитанными сообщениями, прокрутите страницу, чтобы увидеть первое непрочитанное сообщение, а не последнее.';

  @override
  String get appSettings_languageHu => 'Венгерский';

  @override
  String get appSettings_languageJa => 'Японский';

  @override
  String get appSettings_languageKo => 'Корейский';

  @override
  String get radioStats_tooltip => 'Статистика радио и беспроводной сети';

  @override
  String get radioStats_screenTitle => 'Статистика радиовещания';

  @override
  String get radioStats_notConnected =>
      'Подключитесь к устройству, чтобы просмотреть статистику радио.';

  @override
  String get radioStats_firmwareTooOld =>
      'Для работы радиостатистики требуется установленная версия прошивки v8 или более новая.';

  @override
  String get radioStats_waiting => 'Ожидаем данных…';

  @override
  String radioStats_noiseFloor(int noiseDbm) {
    return 'Уровень шума: $noiseDbm дБм';
  }

  @override
  String radioStats_lastRssi(int rssiDbm) {
    return 'Последнее значение RSSI: $rssiDbm дБм';
  }

  @override
  String radioStats_lastSnr(String snr) {
    return 'Последнее значение SNR: $snr дБ';
  }

  @override
  String radioStats_txAir(int seconds) {
    return 'Время эфира на телеканале TX (общее): $seconds секунд';
  }

  @override
  String radioStats_rxAir(int seconds) {
    return 'Общее время использования RX (в секундах): $seconds с';
  }

  @override
  String get radioStats_chartCaption =>
      'Уровень шума (дБм) на основе последних измерений.';

  @override
  String radioStats_stripNoise(int noiseDbm) {
    return 'Уровень шума: $noiseDbm дБм';
  }

  @override
  String get radioStats_stripWaiting => 'Получение данных о радио…';

  @override
  String get radioStats_settingsTile => 'Статистика радиовещания';

  @override
  String get radioStats_settingsSubtitle =>
      'Уровень шума, RSSI, SNR и время передачи';

  @override
  String get translation_title => 'Перевод';

  @override
  String get translation_enableTitle => 'Включить перевод';

  @override
  String get translation_enableSubtitle =>
      'Переводить входящие сообщения и позволять предварительный перевод перед отправкой.';

  @override
  String get translation_composerTitle => 'Переводить перед отправкой';

  @override
  String get translation_composerSubtitle =>
      'Управляет исходным состоянием значка перевода, предоставляемого редактором.';

  @override
  String get translation_autoIncomingTitle =>
      'Автоматически переводить сообщения';

  @override
  String get translation_autoIncomingSubtitle =>
      'Автоматически переводит сообщения для уведомлений, а также для чатов и каналов.';

  @override
  String get translation_translateMessage => 'Перевести сообщение';

  @override
  String get translation_targetLanguage => 'Целевой язык';

  @override
  String get translation_useAppLanguage => 'Используйте язык приложения';

  @override
  String get translation_downloadedModelLabel => 'Загруженная модель';

  @override
  String get translation_presetModelLabel =>
      'Предопределенная модель от Hugging Face';

  @override
  String get translation_manualUrlLabel => 'Ссылка на руководство';

  @override
  String get translation_downloadModel => 'Скачать модель';

  @override
  String get translation_downloading => 'Загрузка...';

  @override
  String get translation_working => 'Работа...';

  @override
  String get translation_stop => 'Прекратите';

  @override
  String get translation_mergingChunks =>
      'Объединение скачанных фрагментов в один финальный файл...';

  @override
  String get translation_downloadedModels => 'Загруженные модели';

  @override
  String get translation_deleteModel => 'Удалить модель';

  @override
  String get translation_modelDownloaded => 'Модель перевода загружена.';

  @override
  String get translation_downloadStopped => 'Процесс загрузки был прерван.';

  @override
  String translation_downloadFailed(String error) {
    return 'Не удалось скачать: $error';
  }

  @override
  String get translation_enterUrlFirst => 'Сначала введите URL модели.';

  @override
  String get scanner_linuxPairingShowPin => 'Показать PIN';

  @override
  String get scanner_linuxPairingHidePin => 'Скрыть PIN';

  @override
  String get scanner_linuxPairingPinTitle => 'PIN‑код сопряжения Bluetooth';

  @override
  String scanner_linuxPairingPinPrompt(String deviceName) {
    return 'Введите PIN‑код для $deviceName (оставьте пустым, если нет).';
  }

  @override
  String get translation_messageTranslation => 'Перевод сообщения';

  @override
  String get translation_translateBeforeSending => 'Перевести перед отправкой';

  @override
  String get translation_composerEnabledHint =>
      'Сообщения будут переведены перед отправкой.';

  @override
  String get translation_composerDisabledHint =>
      'Отправляйте сообщения на языке, в котором они были изначально набраны.';

  @override
  String translation_translateTo(String language) {
    return 'Перевести на $language';
  }

  @override
  String get translation_translationOptions => 'Варианты перевода';

  @override
  String get translation_systemLanguage => 'Язык системы';

  @override
  String get background_serviceTitle => 'MeshCore работает';

  @override
  String get background_serviceText => 'Поддерживаем соединение с нодой';

  @override
  String appSettings_translationModelDeleted(String name) {
    return 'Удалено $name';
  }

  @override
  String appSettings_translationModelDeleteFailed(String error) {
    return 'Не удалось удалить: $error';
  }

  @override
  String channels_channelUpdateFailed(String error) {
    return 'Не удалось обновить канал: $error';
  }

  @override
  String get channels_mcmpCompression => 'Сжатие MCMP';

  @override
  String get channels_mcmpCompressionDescription =>
      'Используется метод и модель mesh-compressor';

  @override
  String get channels_copyPath => 'Скопировать путь сообщения';

  @override
  String get channels_copyPathExtended =>
      'Скопировать путь сообщения (расширенно)';

  @override
  String get channels_copiedPath => 'Путь сообщения скопирован';

  @override
  String get channels_copyPathFailed => 'Не удалось скопировать путь сообщения';

  @override
  String get settings_copyMsgPathTitle =>
      'Настройка копирования пути сообщения';

  @override
  String get settings_copyMsgPathDscr =>
      'Редактировать шаблон сборки информации о пути сообщения из канала';

  @override
  String get settings_copyMsgPathEditTemplateTitle => 'Редактирование шаблона';

  @override
  String get settings_copyMsgPathEditTemplateDscr =>
      'Используйте подстановочные шаблоны:\n%hopInd% - порядок хопа\n%hopKey% - ключ хопа\n%hopName% - имя хопа\n%collisionMarker% - отметка коллизии репитеров\n%div% - разделитель (пропускается для последнего хопа)\n%hops% - количество хопов\n\\n - перенос строки';

  @override
  String get settings_copyMsgPathEditFinalTitle => 'Итоговое сообщение';

  @override
  String get settings_copyMsgPathEditFinalDscr =>
      'Доступные шаблоны:\n%senderName% - имя отправителя\n%path% - сформированный путь\n%hops% - количество хопов\n\\n - перенос строки';

  @override
  String get settings_channelsSendAsBinary =>
      'Отправлять расширенные форматы в бинарном виде (каналы)';

  @override
  String get settings_dmSendAsBinary =>
      'Отправлять расширенные форматы в бинарном виде (личные сообщения)';

  @override
  String get contact_typeChat => 'Пользователь';

  @override
  String get contact_typeRepeater => 'Репитер';

  @override
  String get contact_typeRoom => 'Комната';

  @override
  String get contact_typeSensor => 'Датчик';

  @override
  String get contact_typeUnknown => 'Неизвестно';

  @override
  String get map_zoomIn => 'Увеличить масштаб';

  @override
  String get map_zoomOut => 'Увеличить масштаб';

  @override
  String get map_centerMap => 'Карта центра';

  @override
  String get chrome_bluetoothRequiresChromium =>
      'Для работы Web Bluetooth требуется браузер на основе Chromium.';

  @override
  String channels_communityShortId(String id) {
    return 'Идентификатор: $id...';
  }

  @override
  String get pathTrace_legendGpsConfirmed => 'GPS подтверждено';

  @override
  String get pathTrace_legendInferred => 'Выведенная позиция';

  @override
  String get pathMap_viewSingle => 'Одиночный';

  @override
  String get pathMap_viewCombined => 'Объединённые';

  @override
  String get pathMap_play => 'Воспроизвести';

  @override
  String get pathMap_pause => 'Пауза';

  @override
  String get pathMap_replay => 'Повтор';

  @override
  String get pathMap_stepBack => 'Предыдущий хоп';

  @override
  String get pathMap_stepForward => 'Следующий хоп';

  @override
  String get pathMap_animationOn => 'Показать анимацию пакета';

  @override
  String get pathMap_animationOff => 'Скрыть анимацию пакета';

  @override
  String pathMap_hopOf(int current, int total) {
    return 'Хоп $current из $total';
  }

  @override
  String pathMap_observedPaths(int count) {
    return 'Наблюдаемые маршруты: $count';
  }

  @override
  String get pathMap_primary => 'Основной';

  @override
  String pathMap_alternate(int index) {
    return 'Альт $index';
  }

  @override
  String pathMap_hopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хопов',
      many: '$count хопов',
      few: '$count хопа',
      one: '$count хоп',
    );
    return '$_temp0';
  }

  @override
  String pathMap_gpsCount(int confirmed, int total) {
    return '$confirmed/$total GPS';
  }

  @override
  String get pathMap_legendShared => 'Общий сегмент';

  @override
  String get pathMap_legendEstimated => 'Расчётный сегмент';

  @override
  String pathMap_sharedNodeCount(int count) {
    return 'Используется в $count маршрутах';
  }

  @override
  String pathMap_partialAnimation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хопов не имеют координат — показанный путь неполный',
      many: '$count хопов не имеют координат — показанный путь неполный',
      few: '$count хопа не имеют координат — показанный путь неполный',
      one: '$count хоп не имеет координат — показанный путь неполный',
    );
    return '$_temp0';
  }

  @override
  String get pathMap_showAllPaths => 'Показать всё';

  @override
  String get pathMap_hidePath => 'Скрыть путь';

  @override
  String get pathMap_showPath => 'Показать маршрут';

  @override
  String get pathMap_collapsePanel => 'Скрыть панель';

  @override
  String get pathMap_expandPanel => 'Расширить панель';

  @override
  String get pathMap_noLocation => 'Нет координат';

  @override
  String get pathMap_followPacket => 'Следить за пакетом';

  @override
  String get pathMap_unfollowPacket => 'Не следить за пакетом';

  @override
  String get chat_canvas => 'Холст MCOimg';

  @override
  String get chat_canvasCrop => 'Обрезать/расширить';

  @override
  String get chat_canvasResize => 'Сжать/растянуть';

  @override
  String get chat_canvasUnlockSize => 'Разблокировать размер холста';

  @override
  String get chat_canvasFormatVer => 'Версия кодека';

  @override
  String get chat_canvasPalette => 'Палитра';

  @override
  String get chat_canvasPaletteShow => 'Показать палитру';

  @override
  String get chat_canvasPaletteMode => 'Профиль палитры';

  @override
  String get chat_canvasPaletteDynamic => 'Динамическая';

  @override
  String get chat_canvasPaletteDynamicProfile =>
      'Базовый набор для динамической палитры';

  @override
  String get chat_canvasPaletteDynamicUsed => 'Реально используемые цвета';

  @override
  String get chat_canvasPaletteDynamicDscr =>
      'Внимание! Используйте динамическую палитру с умом! В первую очередь она предназначена для рисунков с градиентами, чтобы строить меньшую палитру, и использовать цвета, не входящие в одну и ту же базовую. Для справки: меньшая базовая палитра даёт меньшую стоимость кодирования информации об использованных оттенках, а меньшее итоговое количество цветов снижает стоимость каждого пикселя холста.';

  @override
  String get chat_canvasPaletteAlpha => 'Цвет прозрачности';

  @override
  String get chat_canvasChangeSize => 'Изменить размер холста';

  @override
  String get chat_canvasTrim => 'Обрезать пустое';

  @override
  String get chat_canvasWidth => 'Ширина';

  @override
  String get chat_canvasHeight => 'Высота';

  @override
  String get chat_canvasGridShow => 'Отображать сетку';

  @override
  String get chat_canvasRulerShow => 'Отображать линейку';

  @override
  String get chat_canvasGridColor => 'Цвет сетки';

  @override
  String get chat_canvasSave => 'Сохранить в файл';

  @override
  String get chat_canvasLoad => 'Загрузить из файла';

  @override
  String chat_canvasSendPayloadExceed(int count) {
    return 'Не удалось отправить - превышен payload на $count байт. Уменьшите количество деталей или размер холста.';
  }

  @override
  String chat_canvasCurrentPayload(int payload) {
    return 'Текущий payload: $payload';
  }

  @override
  String get chat_canvasActive => 'Отображать холст';

  @override
  String get chat_canvasShowLockBtn => 'Отображать кнопку блокировки холста';

  @override
  String get chat_canvasSendToEdit => 'Отправить в холст';

  @override
  String get chat_canvasSendToGallery => 'Сохранить в галерею';

  @override
  String get chat_canvasGalleryShowPNG => 'Показать исходник (PNG)';

  @override
  String get chat_canvasGalleryShowBIN => 'Показать Bin';

  @override
  String get chat_canvasGalleryRemove => 'Удалить';

  @override
  String get chat_canvasGalleryRemoveConfirm =>
      'Удалить изображение из галереи?';

  @override
  String chat_canvasFormatNotSupported(int received, int current) {
    return 'Версия MCOimg: $received, текущий кодек поддерживает до $current';
  }

  @override
  String get chat_canvasSaveBinary => 'Сохранить в бинарный файл';

  @override
  String chat_canvasCannotSend(int count) {
    return 'Не удалось отправить - превышен payload на $count байт. Отредактируйте изображение и попробуйте снова.';
  }

  @override
  String get chat_canvasCompressionLevel => 'Уровень сжатия';

  @override
  String get chat_canvasCompressionLevelNormal => 'Обычный';

  @override
  String get chat_canvasCompressionLevelHigh => 'Высокий';

  @override
  String get chat_canvasCompressionLevelExtreme => 'Экстремальный';

  @override
  String get chat_showHops => 'Отображать хопы';

  @override
  String get settings_modSettings => 'Настройки модификации';

  @override
  String get settings_modSettingsSubtitle =>
      'В разделе собраны опции, отсутствующие в оригинальном meshcore_open';

  @override
  String get settings_modSettingsVisual => 'Визуал';

  @override
  String get settings_modSettingsMessaging => 'Обмен сообщениями';

  @override
  String get settings_modSettingsMCMP => 'MCMP';

  @override
  String get settings_mcmp_version => 'Версия';

  @override
  String get settings_mcmp_useSign => 'Проверка подписи';

  @override
  String get settings_mcmp_signed => 'С проверкой подписи';

  @override
  String get settings_mcmp_noSign => 'Без проверки подписи';

  @override
  String get settings_mcmp_senderNameCollision =>
      'Имя отправителя не уникально!';

  @override
  String get chat_mcmpSignatureValid => 'Подпись действительна';

  @override
  String get chat_mcmpSignatureInvalid => 'Недействительная подпись!';

  @override
  String get chat_mcmpSignatureUnverifiable =>
      'Подпись нельзя проверить — отправителя нет в контактах';

  @override
  String get chat_mcmpSignatureTransport =>
      'Подтверждено шифрованием транспорта';

  @override
  String get chat_mcmpManualRecheckSign => 'Перепроверить подпись';

  @override
  String get chat_mcmpSignatureCheckStatus => 'Проверка подписи';

  @override
  String get chat_mcmpSigningFailed => 'Не удалось подписать сообщение';

  @override
  String get chat_mcmpAnswerTo => 'MCMPv3 ответ на';

  @override
  String get chat_timestampPacket => 'Timestamp пакета';

  @override
  String get settings_modSettingsMCOimg => 'MCOimg';

  @override
  String get settings_modSettingsVisualShowMCOimgFormat =>
      'MCOimg: отображать бейдж версии формата';

  @override
  String get settings_modSettingsVisualShowMCOimgAlgo =>
      'MCOimg: отображать бейдж алгоритма кодирования';

  @override
  String get settings_modSettingsVisualShowMCOimgBytes =>
      'MCOimg: отображать информационный вес картинки (байт)';

  @override
  String get settings_modSettingsVisualShowMCOimgResolution =>
      'MCOimg: отображать разрешение';

  @override
  String get settings_modSettingsMCOimg_showReplacements =>
      'Отображать оригиналы картинок вместо LoRa-версий';

  @override
  String get settings_modSettingsMCOimg_replacementsScale =>
      'Масштабировать оригиналы в чатах';

  @override
  String get settings_modSettingsMCOimg_replacementsLottieScale =>
      'Ограничение размеров lottie-замен';

  @override
  String get settings_modSettingsMCOimg_scaleNearestNeighbor =>
      'Масштабировать как Nearest Neighbor';

  @override
  String get settings_modSettingsMCOimg_replacementsSharp =>
      'Повысить резкость оригиналов в чатах';

  @override
  String get settings_modSettingsMCOimg_replacementsSharpDscr =>
      'Внимание! Отключает анимирование GIF!';

  @override
  String get settings_modSettingsHideChInd => 'Скрыть индекс канала';

  @override
  String get settings_modSettingsHideRadioStats =>
      'Скрыть статистику радиовещания в шапке';

  @override
  String get settings_modSettingsSNRindicatorAllRepActivity =>
      'Индикатор SNR: срабатывать на все ответы репитеров, не только advert';

  @override
  String get settings_modSettingsIncomingQuoteAsMentions =>
      'Отображать цитаты во входящих сообщениях как упоминания';

  @override
  String get settings_modSettingsSimplifiedMentions =>
      'Упрощённый стиль упоминаний в сообщениях';

  @override
  String get settings_modSettingsSharedMsgHistory => 'Общая история сообщений';

  @override
  String get settings_modSettingsSharedMsgHistoryDscr =>
      'Объединение истории сообщений, полученной от разных устройств; итоговая история хранится только в приложении';

  @override
  String get settings_modSettingsSharedMsgHistoryDisabled => 'Отключено';

  @override
  String get settings_modSettingsSharedMsgHistoryChannels => 'Только каналы';

  @override
  String get settings_modSettingsSharedMsgHistoryContacts => 'Только контакты';

  @override
  String get settings_modSettingsSharedMsgHistoryAll => 'Все чаты';

  @override
  String get settings_modSettingsMessagingShowCompressionRatio =>
      'Отображать степень сжатия';

  @override
  String get settings_modSettingsMessagingCompressionRatioWithSendername =>
      'При подсчёте учитывать имя ноды';

  @override
  String get settings_modSettingsVisualHideMapZoomControls =>
      'Скрыть на карте панель зума';

  @override
  String get settings_modSettingsVisualShowMsgRegion =>
      'Отображать регион сообщения';

  @override
  String channels_messageRegion(String region) {
    return 'Регион: $region';
  }

  @override
  String get channels_messageRegionUnknown => 'неизвестно';

  @override
  String get channels_messageRegionNotMatchesWithKnown => 'не знаком';

  @override
  String get channels_messageRegionEmpty => 'отсутствует';

  @override
  String get settings_defaultRegionScope => 'Регион ноды по умолчанию';

  @override
  String get settings_defaultRegionScopeChanged =>
      'Регион по умолчанию изменён';

  @override
  String get settings_defaultRegionScopeChangeFailed =>
      'Не удалось изменить регион';

  @override
  String get settings_defaultRegionScopeEmpty => 'Не задано';

  @override
  String get settings_defaultRegionScopeWaitForSync =>
      'Дождитесь конца синхронизации';

  @override
  String get common_reset => 'Сбросить';

  @override
  String get connection_autoconnect => 'Автоподключение';

  @override
  String settings_modSettingsNoRetraInfo(int time) {
    return 'Не услышано ретрансляций за $time сек.';
  }

  @override
  String get settings_modSettingsNoRetraHeading =>
      'Отмечать сообщения неотправленными, если не услышано ретрансляций за секунд:';

  @override
  String get settings_modSettingsNoRetraDscr =>
      'Внимание! Из-за механизма в прошивке ноды, сообщения для каналов весом более ~133 байт физически не могут получать подтверждения, и они всегда будут отмечены, как сбойные! Используйте эту опцию совместно с ограничением payload в настройках приложения!';

  @override
  String get settings_selfTelemetryShow => 'Просмотр датчиков';

  @override
  String get settings_modSettingsVisualChannelsUnreadSorting =>
      'Сортировка каналов по непрочитанным сообщениям';

  @override
  String get settings_modSettingsMessagingBackgroundTCP =>
      'Удерживать TCP-соединение в фоне';

  @override
  String get settings_modSettingsDPIchange => 'Регулировка DPI';

  @override
  String get settings_modSettingsDPIchangeToIcons => 'Применять к иконкам';

  @override
  String get chat_MCOimgOpenGallery => 'Открыть галерею MCOimg';

  @override
  String get chat_additionalActions => 'Меню действий';

  @override
  String get mcogallery_common => 'Общее';

  @override
  String get mcogallery_addPack => 'Добавить пакет';

  @override
  String get mcogallery_removePack => 'Удалить пакет';

  @override
  String mcogallery_removePackConfirm(String name) {
    return 'Подтвердите удаление пакета «$name»';
  }

  @override
  String get mcogallery_addGroup => 'Добавить группу';

  @override
  String get mcogallery_removeGroup => 'Удалить группу';

  @override
  String get mcogallery_showLora => 'Отобразить LoRa-вариант';

  @override
  String get mcogallery_showPacked => 'Отобразить улучшенный вариант';

  @override
  String get chat_sendSelfContact => 'Отправить свой контакт';

  @override
  String get chat_sendContact => 'Поделиться контактом';

  @override
  String get chat_addContact => 'Добавить контакт';

  @override
  String get chat_sureToReplaceContact => 'Контакт уже существует, заменить?';

  @override
  String get contacts_addContactByPubkey => 'Добавить контакт по ключу';

  @override
  String get contacts_addContactByPubkey_contactType => 'Тип контакта';

  @override
  String get chat_contactIsYou => 'Это ваш собственный контакт';

  @override
  String chat_contactType(String contacttype) {
    return 'Тип контакта: $contacttype';
  }

  @override
  String get chat_contactTypeNode => 'Нода';

  @override
  String get chat_contactTypeRepeater => 'Репитер';

  @override
  String get chat_contactTypeRoom => 'Рум-сервер';

  @override
  String get chat_contactTypeSensor => 'Сенсор';

  @override
  String get chat_myLocation => 'Отправить моё местоположение';

  @override
  String get chat_locationFromMap => 'Отправить координаты с карты';

  @override
  String get settings_modSettingsRoomServer => 'Room-серверы и контакты';

  @override
  String get settings_modSettingsRoomServerShowNotemptyOnChatscreen =>
      'Отображать серверы с историей в одном экране с каналами';

  @override
  String get settings_modSettingsRoomServerShowNotemptyContactsOnChatscreen =>
      'Отображать контакты с историей в одном экране с каналами';

  @override
  String get settings_modSettingsRoomServerDisableRoomAndContactsSorting =>
      'Оставить прежнюю механику drag-n-drop: смена порядка каналов меняет их порядок на ноде, и нельзя сортировать контакты/сервера';

  @override
  String get settings_appSettingsCustomChemistry => 'Своя';

  @override
  String get map_clearDiscoveredContactsCache => 'Очистить локальный кэш узлов';

  @override
  String get map_clearDiscoveredContactsCacheDisclaimer =>
      'Вы уверены, что хотите удалить кэш обнаруженных контактов? Это не затронет контакты на самой ноде.';

  @override
  String get snrIndicator_v2_nearByRepeaters => 'Активность репитеров';

  @override
  String get app_connectionLostReconnect =>
      'Потеряно соединение с нодой, выполняется переподключение...';

  @override
  String get app_connectionLostReconnected =>
      'Соединение с нодой восстановлено';

  @override
  String get contacts_batchOperations => 'Массовые операции';

  @override
  String get contacts_batchOperations_notSelected =>
      'Вы не выбрали контакты для обработки!';

  @override
  String get contacts_batchOperations_removeConfirm =>
      'Удалить выбранные контакты из памяти ноды?';

  @override
  String get contacts_batchOperations_removeSuccess =>
      'Выбранные контакты удалены';

  @override
  String get contacts_batchOperations_removeFail =>
      'Не удалось удалить контакты - проверьте их список снова';

  @override
  String get contacts_batchOperations_commonSuccess =>
      'Операция прошла успешно';

  @override
  String get contacts_batchOperations_commonFail =>
      'Не удалось завершить операцию';

  @override
  String get contacts_batchOperations_selectFiltered =>
      'Выбрать отфильтрованные';

  @override
  String get chat_searchMessages => 'Поиск сообщений';

  @override
  String get chat_searchMessages_placeholder =>
      'От 3 символов, регистронезависимо';

  @override
  String get chat_searchMessages_results => 'Результаты поиска';

  @override
  String chat_searchMessages_results_found(int count) {
    return 'Найдено $count сообщений';
  }

  @override
  String chat_searchMessages_results_channel(String name) {
    return 'Канал $name';
  }

  @override
  String chat_searchMessages_results_room(String name) {
    return 'Комната $name';
  }

  @override
  String chat_searchMessages_results_contact(String name) {
    return 'Диалог с $name';
  }
}
