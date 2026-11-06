# Settings

## How to Access

- From the Device Screen: tap the tune/sliders icon in the app bar
- From Contacts or Channels: overflow menu (three-dot) → Settings

Settings are only accessible while a device is connected.

## Settings Screen Layout

The settings screen is a scrollable list of cards:

1. [Device Info](#device-info)
2. [Node Settings](#node-settings)
3. [Location](#location)
4. [App Settings](#app-settings) (link to sub-screen)
5. [Actions](#actions)
6. [Export](#export)
7. [Debug](#debug)
8. [About](#about)

---

## Device Info

A collapsible card showing read-only device information. **Collapsed by default** — tap the header to expand with an animated chevron indicator:

| Field | Description |
|---|---|
| Name | Connected device's display name |
| ID | Device identifier |
| Status | Connected / Disconnected |
| Battery | Percentage or voltage (tap to toggle) |
| Node Name | The node's mesh identity name |
| Public Key | First 16 hex characters + "..." |
| Contacts Count | Number of known contacts |
| Channel Count | Number of configured channels |

Battery shows an alert icon and orange text when at 15% or below. The toggle only works when millivolt data is available from the firmware.

---

## Node Settings

These settings are sent directly to the connected device firmware.

### Node Name
- Opens a dialog with a text field (max 31 characters)
- Sends the new name to the device
- Confirmed via snackbar

### Radio Settings
Opens a dialog pre-populated with the device's current radio settings. Contains:
- **Preset dropdown**: Regional presets — selecting a preset immediately fills all fields below. Includes presets for Australia, Australia (Narrow), Australia (Mid), Australia SA WA QLD, Czech Republic, EU 433MHz, EU/UK (Long Range), EU/UK (Medium Range), EU/UK (Narrow), New Zealand, New Zealand (Narrow), Portugal 433, Portugal 869, numerous Russia city presets, Switzerland, USA Arizona, USA/Canada, and Vietnam
- **Frequency** (MHz): Free text, validated 300–2500 MHz
- **Bandwidth**: Dropdown (7.8 / 10.4 / 15.6 / 20.8 / 31.25 / 41.7 / 62.5 / 125 / 250 / 500 kHz)
- **Spreading Factor**: SF5–SF12
- **Coding Rate**: 4/5, 4/6, 4/7, 4/8
- **TX Power** (dBm): Validated 0 to device max (typically 22 dBm)
- **Client Repeat** toggle: Only shown on firmware v9+; requires frequency to be exactly 433.000, 869.000, or 918.000 MHz (the Off-Grid presets). Save is blocked with a warning if enabled on other frequencies

### Regions

Open region management to add/fetch names and select a default flood scope. Channel chat can override it; clearing an override inherits the default. See [Regions](regions.md), including message labels and temporary reply-region choices.

### Radio stats
Opens the radio statistics screen for the paired radio: noise floor, last RSSI, last SNR, and total TX/RX airtime. Only enabled when connected to a device that supports companion radio stats (firmware code 8+). See the [radio-statistics guide](radio-statistics.md).

---

## Location

### Location
Opens a dialog pre-populated with the device's current coordinates (if known):
- Latitude and longitude fields (decimal, 6 decimal places). If only one field is provided, the other uses the device's current value
- If GPS-capable hardware (detected via `gps` custom variable):
  - GPS Update Interval (seconds, 60–86399, default 900 = 15 minutes). Validated and sent separately before lat/lon
  - Enable GPS toggle (takes effect immediately, not deferred to Save)
- Validation: lat ±90, lon ±180

### Contact Settings
Contact Settings opens a dialog titled Contacts Settings, containing:
- Auto-add Chat Users
- Auto-add Repeaters
- Auto-add Room Servers
- Auto-add Sensors
- Overwrite Oldest (when contact list is full)
- **Multi-Ack**: delivery confirmations, immediately after Overwrite Oldest

Multi-Ack takes effect on Save; Cancel leaves it unchanged. Its firmware command
also contains privacy settings, so the app preserves their current values when
saving Multi-Ack. An unchanged setting is not rewritten, including firmware mode 2.

### Privacy
Opens a dialog with controls for how the node shares telemetry and location data:
- **Advert Location**: Toggle whether the node broadcasts its location in advertisements
Privacy saves preserve the current Multi-Ack value configured in Contact Settings.
- **Telemetry Base Mode**: Deny All / Allow by Contact / Allow All
- **Telemetry Location Mode**: Deny All / Allow by Contact / Allow All
- **Telemetry Environment Mode**: Deny All / Allow by Contact / Allow All

Settings take effect when saved. A snackbar confirms the update.

---

## App Settings

A dedicated sub-screen for app-level preferences (nothing here is sent to the device). All settings persist locally via SharedPreferences.

Language, map time-filter and unit choices remain scrollable on short screens
and with large text; their labels are shown in full. The language list shrinks
to the available height while its heading and Close button stay visible.
The Stadia map API-key dialog also scrolls when the keyboard is open. Saving
its unchanged masked value keeps the stored key; Cancel discards edits.

### Appearance
- **Theme**: System / Light / Dark
- Status-chip labels use the theme's normal text color. Status marks and avatar icons/initials retain their accent hue, adjusted for contrast against the standard tinted card background (target 3:1 for marks, 4.5:1 for text). Tint, border and type icons remain unchanged. Color correction uses a bounded cache; it adds no status animation or network request
- **Language**: System default or one of 18 languages (English, French, Spanish, German, Polish, Slovenian, Portuguese, Italian, Chinese, Swedish, Dutch, Slovak, Bulgarian, Russian, Ukrainian, Hungarian, Japanese, Korean)

### Notifications
- **Master enable/disable**: Requests OS permission when enabling
- **Message notifications**: New direct message alerts
- **Channel message notifications**: New channel message alerts
- **Advertisement notifications**: New node discovery alerts

Individual channels can be muted from the channel chat bell icon, the channel list, or the channel notification. Replying from notifications, watches, and Android Auto is described in [Notifications](notifications.md).

### Messaging
- **Clear Path on Max Retry**: Erases the stored routing path after all retries fail
- **Jump to Oldest Unread**: When opening a chat, scrolls to the oldest unread message instead of the newest
- **Auto Route Rotation**: Enables weighted routing algorithm. When enabled, expands to show five slider sub-settings (hidden when off):
  - Max Route Weight (1–10, default 5, integer steps)
  - Initial Route Weight (0.5–5.0, default 3.0)
  - Success Increment (0.1–2.0, default 0.5, 0.1 steps)
  - Failure Decrement (0.1–2.0, default 0.2, 0.1 steps)
  - Max Message Retries (2–10, default 5)
- **Enable Message Tracing**: Shows path trace overlays and extra metadata on messages
- **Region next to hop count** (default off): Shows a channel message's region chip on the same line as its hop count instead of below it
- **Resend channel messages until they travel far enough** (default off): If your channel message isn't heard coming back through enough repeaters, it's sent again. Uses more airtime. When on, it shows:
  - Required hops (1–8, default 2)
  - Resend up to (1–5 times, default 1)
  - **Also count different nearby repeaters** (default off): Also treats the message as sent once enough *different* first-hop repeaters have repeated it, even if you can't hear it travel further. Useful where only nearby repeaters are audible. See [Channels](channels.md#channel-auto-resend)
  - **Required nearby repeaters** (2–10, step 1, default 2): Visible when the nearby-repeater toggle is on. This target is independent of **Required hops**. Either target can stop resending. Existing saved settings without this field inherit their previous required-hop value, limited to 2–10; later changes to either slider leave the other unchanged.

  Если после всех канальных попыток не выполнен ни один порог, одно эхо не снимает предупреждение о недостаточном покрытии. В трассировке появляется предупреждающий значок; текст о числе попыток зависит от mod-опции предупреждения о ретрансляциях и её таймаута 5–15 с от последней отправки. Позднее эхо снимает признак недостаточного покрытия только при выполнении одного из порогов. Счётчик разных репитеров не увеличивается от повторного эхо того же префикса. Подробнее — [канальные повторы](channels.md#channel-auto-resend).

### Энергосбережение

Отдельный переключатель «Приостанавливать скрытые GIF» останавливает показ кадров GIF-ссылок вне видимой области, под другим экраном или при неактивном приложении. Возврат сохраняет выбор ручной паузы. Переключатель включён в готовых энергопрофилях, выключен по умолчанию в своих настройках; подробности — в [руководстве по энергосбережению](power-saving.md#показ-gif).

Пункт «Энергосбережение» открывает выбор профиля: «Выключено», «Сбалансированный», «Экономный», «Максимальная экономия» или «Свои настройки». Сейчас регулируются интервал скрытого экрана радиостатистики (1–60 с), приостановка опроса невидимого радиоиндикатора, интервалы батареи ноды (120–600 с) и GPS ноды (60–600 с), приостановка очистки изображений в простое и скрытых GIF, интервал обычных обновлений интерфейса (50–1000 мс, шаг 50 мс). Интервалы задаются слайдерами, приостановки — отдельными переключателями. Для интерфейса готовые профили задают 100/250/500 мс; изменения подключения сохраняют прежнее окно до 50 мс, обработка пакетов не задерживается. Батарея/GPS используют выбранные периоды и на экране, и в фоне; увеличение периода батареи увеличивает порог обнаружения молчащего соединения. Таймер изображений при включённой опции работает только при наличии незавершённых потоков или временного кэша завершённых; период и сроки ожидания сохраняются. «Выключено» сохраняет прежнее поведение; параметры готовых профилей фиксированы, свои значения сохраняются при переключении. Подробности и ограничения платформ — в [руководстве по энергосбережению](power-saving.md).

Опция **«Откладывать описание кадров журнала»** формирует текст новой записи при первом обращении для показа или копирования. Данные кадра, время записи и маскирование приватного ответа сохраняются сразу. В готовых энергопрофилях опция включена, в «Выключено» и исходных своих настройках — выключена. Переключение не очищает и не перестраивает накопленный журнал.

Опция **«Меньше служебных BLE-логов»** на Android/iOS/macOS запрашивает у Bluetooth-плагина только предупреждения и ошибки. В готовых энергопрофилях включена; исходный профиль и выключенная опция сохраняют `debug`. На Windows/Linux/в браузере не применяется. Собственный журнал кадров не меняется; на iOS настройка не управляет отдельным native BLE central. Подробности — в [руководстве](power-saving.md#служебные-ble-логи).

Два независимых переключателя **«Приостанавливать скрытые статусные анимации»** и **«Статичные индикаторы статуса»** управляют точками отправки и плавной пульсацией. Первый приостанавливает невидимые/неактивные индикаторы, второй делает их статичными также на экране. «Сбалансированный» включает только паузу, «Экономный» и «Максимальная экономия» — оба флага; «Выключено» сохраняет исходное поведение. Подписи, подтверждения и счётчики обновляются независимо от анимации. Подробности — в [руководстве](power-saving.md#статусные-анимации).

Переключатель **«Кэшировать параметры каналов»** сокращает повторные вычисления при поиске канала входящего пакета. В трёх готовых энергопрофилях включён, в исходном выключен; в «Своих настройках» задаётся отдельно. Изменившийся ключ пересчитывается, проверка и расшифровка сообщений сохраняются. Подробнее — в [руководстве](power-saving.md#кэш-параметров-каналов).

Переключатель **«Разбирать прогресс только при отправке»** пропускает дополнительный разбор радиокадров для прогресса личной доставки при отсутствии direct-трекеров. Активное отслеживание, приём сообщений и ACK сохраняются. В трёх энергопрофилях включён, в исходном выключен; свой выбор сохраняется отдельно. Подробнее — в [руководстве](power-saving.md#разбор-прогресса-доставки).

Слайдер **«Пауза переподключений в фоне»** задаёт 30–600 секунд с шагом 30. Первые шесть пауз BLE/TCP остаются 1/2/4/8/16/30 секунд; увеличенная пауза применяется с седьмого планирования только при неактивном приложении. Готовые профили выбирают 60/180/600 секунд. «Выключено» и минимум своих настроек сохраняют прежний предел 30 секунд. Возврат в приложение пересчитывает оставшееся ожидание по обычному расписанию; свой выбор сохраняется отдельно. Подробности — в [руководстве](power-saving.md#переподключения-в-фоне).

### Battery
- **Battery Chemistry**: NMC / LiFePO4 / LiPo (per device, used to calibrate percentage from voltage)

### Map Display
- **Show Repeaters**: Toggle repeater markers on map
- **Show Chat Nodes**: Toggle chat node markers
- **Show Other Nodes**: Toggle room/sensor markers
- **Time Filter**: All time / Last 1h / Last 6h / Last 24h / Last week
- **Units**: Metric / Imperial
- **Raster Tile Source**: Sets the MAP theme and with that from where to get the map tile data:
  - OpenStreetMap (Auto/Standard/Dark) is provided by the free OpenStreetMap tile server. (Can only be used for live view or already cached.)
  - Stamen Terrain / AlidadeSmooth Dark / Outdoors / OSM Bright are [StadiaMaps.com raster tile maps](https://stadiamaps.com/products/maps/interactive-basemaps/) for which you can choose an Hosted Endpoint (Worldwide / Europe hosted) and have to provide the API key to your subscription. (You can cache these maps for offline Map usage.)
  There will be no account provided by meshcore-open. You will have to get you own subscription. Check [current Stadia Maps plans and terms](https://stadiamaps.com/pricing/) for quotas and offline-use permissions.
- **Offline Map Cache**: Navigate to tile download screen

### Translation
Not shown on web. Controls on-device message translation powered by a locally-downloaded ML model:
- **Enable translation**: Enables message translation controls
- **Auto-translate incoming messages**: Automatically translates incoming messages for chat/channel display and notifications
- **Translate before sending**: Sets the default state of the composer's translate icon (on means messages are translated before sending)
- **Target language**: Language to translate into (searchable list; defaults to the app language)
- **Downloaded model**: Dropdown to select among already-downloaded translation models
- **Preset Hugging Face model**: Download a curated preset model with one tap
- **Manual model URL**: Enter a URL to download a custom GGUF-format model; shows download progress and a cancel button

The auto-translate and composer toggles are disabled until **Enable translation** is on.

### Images from Links

- **Load images from links** is the master switch, disabled by default. Turning
  it off blocks new sharing-page and image downloads in chats and notifications.
  Per-chat controls become disabled but keep their saved values.
- **Show link images in all chats by default** starts off. When enabled, it
  applies only to chats without a saved choice. Explicit on/off values keep
  priority; channel aliases and inherited settings from other nodes also remain
  effective. Merely opening/saving the channel editor does not create a choice.

Changing the master switch does not clear the default or individual choices.
A request that already started may finish, but its obsolete result is ignored.
Image/file uploads explicitly requested through IPFS and mesh AEIC/MCOimg are
independent of these download switches.

### IPFS Provider Configuration

Open **App Settings → IPFS provider configuration** to configure IPFS uploads and previews:

- **Public IPFS gateway**: New settings default to Filebase (`https://ipfs.filebase.io/ipfs/`). You can still select ipfs.io, Pinata, Filebase, a custom gateway, or deactivate it. Existing saved choices, including an empty value for deactivation, are preserved. This gateway lets the app load bare IPFS content IDs in image links. Existing full gateway URLs retain their original host. Changing the default does not enable link-image loading, which remains off until you enable it.
- **Upload provider**: Select Pinata, Filebase, a custom provider, or deactivate uploads. Presets fill in the provider’s upload endpoint and upload gateway; custom setups can edit both.
- **API key**: Enter the credential required by the selected provider. The value is masked in the settings dialog. Pinata and Filebase presets require provider credentials.

For a self-hosted Kubo node, choose **Custom (Kubo)** and configure its RPC upload endpoint and HTTP gateway. The preset defaults use `http://127.0.0.1:5001/api/v0/add` and `http://127.0.0.1:8080/ipfs/`; replace these with addresses reachable from the device running MeshCore Open. Do not expose Kubo’s unauthenticated RPC API to the public internet.

When an **upload gateway** is configured, uploaded content is added to the draft as an HTTP(S) gateway URL in the form `http://gateway/ipfs/CID`. If it is blank, the app uses `ipfs://CID`. The public gateway setting is separate and is used to retrieve bare IPFS content IDs in incoming links.

Save the settings before sharing. The upload action is shown in the chat composer only when an upload endpoint is configured. Provider accounts, credentials, limits, and terms are managed by the provider, not MeshCore Open. See [sharing images via IPFS](additional-features.md#share-an-image-via-ipfs) for the chat workflow.

### Image Messages

Image message controls live in App Settings → Messaging. Turn on **Enable image messages** first; **Process images automatically** and the image model download/cancel/removal controls then appear. Automatic processing reconstructs every image as it arrives and uses about 2 GB of memory for a second each time; leave it off to reconstruct with a tap. See [Image Messages](image-messages.md) for firmware, native-runtime, storage, and memory requirements.

### Cyrillic-to-Latin (Cyr2Lat)
Controls character substitution profiles used to render Cyrillic text in Latin characters. A dropdown selects the active profile; Add, Edit, and Delete buttons manage the profile list (the last remaining profile cannot be deleted). Each profile stores a JSON character map.

### Debug
- **App Debug Logging**: Enable the in-app debug log

---

## Actions

One-tap device operations:

| Action | Description |
|---|---|
| Sync Time | Sends current Unix timestamp to the device |
| Refresh Contacts | Re-requests the full contact list |
| Reboot Device | Confirmation dialog → reboots the device (shown in warning color) |
| Delete All Paths | Confirmation dialog → clears all stored routing paths (shown in alert color) |

---

## Export

Three GPX export options (not available on web):

| Option | Exports |
|---|---|
| Export Repeaters | Repeaters and Rooms with GPS coordinates |
| Export Contacts | Chat contacts with GPS coordinates |
| Export All | All contacts with GPS coordinates |

Each creates a `.gpx` file and opens the OS share sheet. Feedback via snackbar for four outcomes: success, no contacts with coordinates, feature not available (web), or error.

---

## Debug

Two log viewers accessible via list tiles:

### BLE Debug Log
Two views (togglable via segmented button):
- **Frames view**: Direction icon, description, hex preview, timestamp per frame. Long-press to copy hex.
- **Raw Log RX view**: Decoded LoRa packets with route type, payload type, path, and summary.
- Copy-all and Clear buttons in the app bar.

### App Debug Log
Structured log entries (Info / Warning / Error), with tag, message, and timestamp.
- Must be enabled first in App Settings → Debug
- Copy-all and Clear buttons

---

## About

Shows the standard Flutter about dialog with app name, version, and legal notice.
