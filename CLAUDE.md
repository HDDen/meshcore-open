# MeshCore Open - Flutter Client (Advanced mod)

Open-source Flutter client for MeshCore LoRa mesh networking devices. Connects to MeshCore-compatible radios over **BLE, TCP, or USB serial** and provides direct/channel chat, contact and channel management, on-map node tracking, and repeater administration.

This checkout is the **"Advanced mod"** fork (app title `MeshCore Open (Advanced mod)`). On top of a vanilla MeshCore client it adds: selectable text compression (MCMP arithmetic coder / SMAZ / cyr2lat), app-side Ed25519 verification of MCMP v3 signatures, emoji reactions, tiny image/GIF-over-LoRa (MCO image codec), wardriving/coverage mapping with cloud upload, and region/flood-scope routing. See **Advanced mod features** below.

> On-device LLM translation is **scaffolded but disabled in this build** — `TranslationService` is a no-op stub (`downloadModel()` throws `StateError('LLM translation is disabled in this build.')`) and the `llamadart` / `flutter_langdetect` dependencies have been removed. The translate UI still lets users pick a target language for settings, but no translation is performed.

## Build Commands

```bash
# Install dependencies
~/flutter/bin/flutter pub get

# Run in debug mode
~/flutter/bin/flutter run

# Build Android APK
~/flutter/bin/flutter build apk

# Build iOS
~/flutter/bin/flutter build ios

# Build versioned web release (uses build_pipe)
~/flutter/bin/dart run build_pipe

# Run static analysis
~/flutter/bin/flutter analyze

# Run tests
~/flutter/bin/flutter test
```

## Project Structure

```
lib/
├── main.dart        # Entry point: MultiProvider wiring, locale + theme, initial route
├── connector/       # Unified BLE/TCP/USB transport layer
│   ├── meshcore_connector.dart       # Central state holder + ChangeNotifier (all transports)
│   ├── meshcore_connector_tcp.dart   # TCP transport helper
│   ├── meshcore_connector_usb.dart   # USB serial transport helper
│   ├── meshcore_protocol.dart        # Frame size + version constants
│   └── meshcore_uuids.dart           # Nordic UART UUIDs + scan name prefixes
├── models/          # Plain data classes (Contact, Channel, Message, Community, …)
├── services/        # ChangeNotifier services + IO services (retry, wardrive, ML, …)
├── storage/         # SharedPreferences-backed stores, scoped per device key
├── helpers/         # Pure utilities (MCMP/Smaz/cyr2lat compression, MCO image codec, GIF parsing, path hop resolution)
├── utils/           # Platform / IO / UX utilities (logger, GPX export, dialogs)
├── theme/           # MeshTheme — warm-dark MeshPalette, wired in main.dart
├── l10n/            # ARB localization for 18 locales
├── icons/           # Custom icon widgets
├── widgets/         # Reusable widgets (AppBar, BatteryUi, QR, jump-to-bottom, …)
└── screens/         # ~30 screens — see Screens section below
```

## Screens

All screens are fully implemented (no remaining placeholders).

### Connection / Scanning
| Screen | Purpose |
|---|---|
| `scanner_screen.dart` | BLE device scan and connect — main entry point |
| `tcp_screen.dart` | Connect to a MeshCore device over TCP/IP |
| `usb_screen.dart` | Connect to a MeshCore device over USB serial |
| `discovery_screen.dart` | Browse all discovered (non-contact) mesh nodes |
| `chrome_required_screen.dart` | Web gate for non-Chrome browsers (BLE unavailable) |

### Chat / Messaging
| Screen | Purpose |
|---|---|
| `chat_screen.dart` | Direct (private) messaging with a contact |
| `channel_chat_screen.dart` | Group messaging inside a named channel |
| `channels_screen.dart` | List and manage channels (add/edit/delete) |
| `channel_message_path_screen.dart` | Hop-by-hop route a channel message took, with map overlay |

### Contacts / Neighbors
| Screen | Purpose |
|---|---|
| `contacts_screen.dart` | Full contacts list with previews and management |
| `neighbors_screen.dart` | Nodes directly heard by the connected radio (one-hop) |

### Repeater Management
| Screen | Purpose |
|---|---|
| `repeater_hub_screen.dart` | Top-level repeater hub; navigates to sub-screens |
| `repeater_status_screen.dart` | Live status of a managed repeater node |
| `repeater_cli_screen.dart` | Raw command-line interface to a repeater |
| `repeater_settings_screen.dart` | Full radio/node settings editor for a repeater |

### Map / Location
| Screen | Purpose |
|---|---|
| `map_screen.dart` | Main map view of contacts/nodes with live GPS positions |
| `line_of_sight_map_screen.dart` | Terrain LOS analysis between configurable endpoints |
| `path_trace_map.dart` | Animates the hop path a direct message traveled |
| `map_cache_screen.dart` | Download/clear offline map tile cache |
| `community_qr_scanner_screen.dart` | Scan QR to join a mesh community/channel |

### Settings / Debug / Diagnostics
| Screen | Purpose |
|---|---|
| `settings_screen.dart` | Connected device settings: radio params, identity, GPS |
| `app_settings_screen.dart` | App preferences: theme, units, map source, notifications |
| `mod_settings_screen.dart` | Advanced-mod preferences: compression, reactions, wardrive, images |
| `region_management_screen.dart` | Manage named regions / flood scopes for channel routing |
| `app_debug_log_screen.dart` | In-app log viewer (app-layer messages) |
| `ble_debug_log_screen.dart` | In-app log viewer (raw BLE frame traffic) |
| `companion_radio_stats_screen.dart` | RF stats (RSSI, SNR, packet counts) for paired radio |
| `telemetry_screen.dart` | Battery / sensor / environmental telemetry for a contact |

### Images (Advanced mod)
| Screen | Purpose |
|---|---|
| `canvas_editor_screen.dart` | Draw/compose a tiny image and send it over the mesh (MCO image codec) |
| `mco_image_gallery_screen.dart` | On-device gallery of MCO images + bundled `.mcoimg.pack` sets |

## Architecture

### State Management

`Provider` with `ChangeNotifier`. `main.dart` wires a `MultiProvider` with the following:

| Provider | Role |
|---|---|
| `MeshCoreConnector` | Active transport (BLE/TCP/USB), connection state, frame I/O |
| `MessageRetryService` | ACK tracking and retry scheduling with backoff |
| `PathHistoryService` | Per-contact routing history (LRU cache, 50 contacts) |
| `AppSettingsService` | App preferences (theme, units, locale, notifications) |
| `BleDebugLogService` | Raw BLE frame log buffer |
| `AppDebugLogService` | Structured app log buffer |
| `ChatTextScaleService` | Pinch-to-zoom text scale for chat screens |
| `TranslationService` | On-device LLM translation — **disabled stub** in this build (see intro) |
| `UiViewStateService` | Contacts/channels sort/filter/search state |
| `TimeoutPredictionService` | ML linear regression for ACK timeout prediction |
| `StorageService` | Path history + delivery observation persistence (`Provider`, not `ChangeNotifier`) |
| `MapTileCacheService` | OSM tile pre-cache |
| `WardriveService` | Coverage-mapping scanner: GPS-tagged SNR/RSSI samples + cloud upload (Advanced mod) |

Non-provider singletons wired in `main()`: `NotificationService`, `BackgroundService` (background BLE/USB keep-alive + TCP sync), `MeshCompressor` (MCMP model init), `MCOImageGalleryStore` (installs bundled image packs).

Screens consume these via `Consumer<T>` (or `context.watch<T>()` / `context.read<T>()`) for reactive UI.

### Storage / Persistence

All stores in `lib/storage/` use `PrefsManager` (a `SharedPreferences` singleton initialized in `main()`). Most stores **scope keys by the first 10 hex chars of the connected device's public key**, so per-radio data is isolated.

| Store | Persists |
|---|---|
| `message_store`, `channel_message_store` | Direct + channel messages |
| `contact_store`, `contact_discovery_store` | Known + discovered contacts |
| `channel_store`, `channel_order_store`, `channel_settings_store`, `channel_group_store` | Channels, display order, per-channel compression/sign toggles, channel groups |
| `channel_region_store`, `region_store` | Per-channel region tag + known regions / flood scopes (Advanced mod) |
| `community_store` | Communities (32-byte shared secrets) |
| `contact_group_store`, `contact_settings_store` | Groups; per-contact compression (MCMP/Smaz/cyr2lat), sign, sending-delay, quick-answer, widget-color settings |
| `node_identity_store` | Cached self/node identity metadata |
| `connection_transport_preference_store` | Last-used transport (BLE/USB/TCP) per device |
| `mco_image_gallery_store` | On-device MCO image gallery + bundled `.mcoimg.pack` index (Advanced mod) |
| `unread_store` | Per-contact unread counts (debounced writes) |

Wardrive data (samples, sessions, per-endpoint uploaded IDs, ignore list) is persisted in SharedPreferences via `wardrive_sample_store` / `wardrive_ignore_store`. The disabled translation subsystem still exposes a `translation_file_store` file path for model removal only.

### Contact message summaries and channel-screen visibility

`Contact.hasMessages` means that an actual direct-message history exists for the contact in either the current node's store or an enabled shared-history scope. Channel posts, adverts, and discovery activity must not set this flag. Missing `hasMessages` values in legacy `contact_store` / `contact_discovery_store` records are treated as `false`; `_refreshContactMessageSummaries()` rebuilds the flag from real local/shared message summaries and clears stale values. When summaries are merged, `lastMessageAt` remains monotonic and keeps the newest known timestamp.

Incoming channel activity may still advance a known contact's `lastMessageAt` for activity sorting, but `_updateContactLastMessageAtByName()` calls `_setContactLastMessageAt(..., markHasMessages: false)`, so this never makes an empty direct conversation appear on the channels screen. Channel-author attribution follows this order:

1. A valid MCMP v3 signature uses the verified full public key for an exact contact match.
2. Otherwise, the sender name is used only when it matches exactly one chat contact.
3. With no name match, the packet path may be used only when the negotiated path-hash width is at least two bytes and exactly one contact matches.

Never trust `ChannelMessage.verifiedSenderKeyHex` without also requiring `mcmpSignatureStatus == McmpSignatureStatus.valid`: failed verification may expose the single candidate key that was checked, which is diagnostic information rather than authenticated identity.

### Theming
- Material 3 design (`useMaterial3: true`)
- Light/dark selected via `AppSettings.themeMode` (`system` / `light` / `dark`)
- `lib/theme/mesh_theme.dart` defines the warm-dark `MeshPalette` (phosphor-green accents) and **is wired** in `main.dart` via `MeshTheme.light()` / `MeshTheme.dark()`
- Global UI scale (`AppSettings.uiScale`, optionally applied to icons) is layered on top of the system text scaler in the `MaterialApp.builder`
- Bundled `Inter` and `JetBrains Mono` fonts (see `pubspec.yaml`)

### Localization

18 locales supported via Flutter's standard ARB pipeline (`lib/l10n/`): en, de, es, fr, it, pt, ru, uk, bg, hu, ja, ko, nl, pl, sk, sl, sv, zh. Language override comes from `AppSettingsService.settings.languageOverride`. Use the `context.l10n` extension (`lib/l10n/l10n.dart`) for translated strings; contact-type names live in `contact_localization.dart`.

Every non-template locale carries ~37 keys that `app_en.arb` no longer has — the whole `path_*` / `chat_path*` group (`chat_pathManagement`, `path_currentPath`, `path_setPath`, `path_routeWeight`, `chat_score`, …), `settings_bleDebugLog` and its subtitle, plus a few per-locale leftovers (`repeater_refreshLocationSettings` and the malformed `neighbors_heardA ago` in ru/uk, the `settings_preset*Mhz` radio presets in zh). None of them are referenced from Dart and `gen-l10n` ignores anything absent from the template, so they are harmless. **Do not delete them**: merges from the upstream `meshcore_open` dev branch reintroduce the same keys, so a cleanup only produces churn.

`untranslated.json` is a snapshot written by the last `gen-l10n` run, not a live view — check missing keys against `app_en.arb` directly before concluding a locale is incomplete.

## Advanced mod features

Everything below is fork-specific and lives on top of the vanilla protocol. Most is threaded through `MeshCoreConnector` on the send/receive paths; toggles are per-contact / per-channel in `contact_settings_store` / `channel_settings_store` and edited in `mod_settings_screen.dart`.

### Text compression (3 selectable schemes)
`MessageCompressionType { mcmp, smaz, cyr2lat }` (`models/message_compression.dart`). Applied outbound in `MeshCoreConnector.prepareContactOutboundText()` / `prepareChannelOutboundText()`; decoded inbound via `helpers/message_text_codec.dart` by prefix.
- **MCMP** (`helpers/mesh_compressor.dart`) — context-mixing + arithmetic coder driven by the bundled `assets/models/model-en-ru.json` (EN/RU), Base91 output, prefix `mcmp2:` (legacy `mcmp:` gated off). A v3 signed/metadata container is handled by `helpers/mcmp_app_codec.dart`.
- **SMAZ** (`helpers/smaz.dart`) — classic short-string dictionary coder.
- **cyr2lat** (`helpers/cyr2lat.dart`) — not real compression; maps look-alike Cyrillic letters to ASCII so Cyrillic text fits the cheaper wire encoding.
All schemes fall back to plaintext if they don't shrink the payload (`encodeIfSmaller`).

### MCMP v3 signatures (Ed25519, verified app-side)
The node signs message bodies via `CMD_SIGN_START/DATA/FINISH` (single global sign buffer → serialize sessions). **Verification is done entirely in the app** (`helpers/mcmp_signature_verifier.dart`, `cryptography` package) against known contacts; firmware never verifies. `McmpSignatureStatus` propagates onto `Message` and is shown by `widgets/mcmp_signature_badge.dart`. Handles sender-name collisions.

### Reactions
Emoji reactions ride the normal text channel as a compact `r:<4hex-targetHash>:<2hex-emojiIndex>` string (`helpers/reaction_helper.dart`) — no protocol extension. Target hash = `computeReactionHash(timestampSecs, senderName?, textPrefix)`; sender name omitted for 1:1. Processed in the connector's reactions region.

### Exact quotes (plain-text replies)
Plain-text replies carry only `@[sender]`, which the receiver resolves to that sender's *newest* message. `helpers/exact_quote_helper.dart` adds a quote fragment so the reply anchors to the message it was actually written for. Wire form is `@[sender] >fragment\ntext`; the whole mechanism (both directions) lives in that one file, exposed as `formatReply` / `resolveReply` — everything else is call sites.

**Outbound** (`_applyReplyMention` → `_formatReply` in `channel_chat_screen.dart`, channels only). Budget is `AppSettings.exactQuoteLimit` (3–100, default 15) counted in **wire bytes**: the fragment is cut from the readable original, but each character is weighed after cyr2lat substitution, using the table `MeshCoreConnector.channelCyr2LatCharMap()` returns for that channel. Trailing `[\s.+,-]` is trimmed (a question mark is deliberately kept) and an ellipsis is appended only when the fragment is shorter than its source. No fragment is spent when the toggle is off, when the target is the sender's newest message, or when `MeshCoreConnector.channelReplyCarriesMcmpAnchor()` is true — MCMP v3 already ships an exact author+timestamp anchor.

**Inbound** (`_addChannelMessage`). `skipExactQuote` suppresses parsing entirely when `mcmpReplyTimestamp != null` (a leading `>` line there is the author's own text) or, for incoming messages, when `AppSettings.incomingQuoteAsMentions` is on (no quote bubble is drawn there, so stripping the fragment would swallow it). Otherwise the fragment is cut off the body and matched backwards through history against messages from that author: prefix match first, then the candidate re-encoded through `extendedCharMap` → `defaultCharMap` → `transliterationCharMap` → the user's own cyr2lat profiles. Encoding the candidate rather than decoding the fragment is deliberate — several Cyrillic letters share one Latin look-alike, so the reverse is ambiguous.

Both sides normalise identically before cutting or comparing: leading scaffolding (a quote line or a mention the quoted message itself began with) is stripped, whitespace collapsed, ends trimmed. A miss stores the received fragment as `replyToText` with no `replyToMessageId`, so the quote stays visible but untappable; `_findReplyFallbackMessageId` in the screen may still resolve it later by substring after older messages load. Parsing happens once on receipt and the processed text is what gets persisted — toggling the settings does not replay old messages.

### Inline text markup
Chat-style formatting parsed by `helpers/message_markup.dart`: `**bold**`, `__italic__`, `_underline_`, `~~strike~~` and a monospace block fenced by triple backticks. `parse()` returns styled runs and drops the markers; `parse(keepMarkers: true)` keeps them as their own segments, which the composer needs so caret offsets still line up with the raw text.

Rules that matter when touching it: a marker only opens a run when a matching closer exists later (so a lone `*` stays literal), markers built from `_` refuse to open inside a word (snake_case, URLs), a monospace block is literal all the way to its closer, and runs may span line breaks. `has()` short-circuits on a codeunit scan for `*_~` and backtick before parsing, because message lists render mostly plain text.

Three call sites. **Rendering**: `widgets/formatted_message_text.dart` treats markup as the outer layer and resolves mentions and links inside each run, so a bold sentence keeps its mention chip and tappable URL; that widget is reached from `TranslatedMessageContent`, which falls back to plain `Linkify` when neither markup nor a mention is present. **Composing**: `widgets/markup_text_editing_controller.dart` overrides `buildTextSpan` to dim the markers and style the run between them — characters are never hidden, since a Flutter field cannot hide them without the caret drifting, and that visibility is what makes deleting a marker an obvious way to strip formatting. **Toolbar**: `ByteCountedTextField.contextMenuBuilder` appends five wrap actions (`chat_format*` keys) that run the result through the same UTF-8 limiter as typed input.

### MCO image codec (image/GIF over LoRa)
Bespoke ultra-compressed raster format so tiny images fit LoRa text/binary messages. `helpers/mcoimg_codec.dart` (v1/v2, text prefix `im:`) and `helpers/mcoimg_v3_codec.dart` (binary container) quantize to fixed/dynamic palettes (`mcoimg_palette.dart`, `mcoimg_dynamic_palettes.dart`, up to 512 colors) and brute-force many encoders, keeping the smallest. Because the transmitted image is degraded, `services/mco_image_pack_originals.dart` keeps a hash→file index of installed `.mcoimg.pack` sets and renders the **original PNG/JPG/animated GIF** when a received image's identity hash matches (`widgets/gif_message.dart`, `widgets/mco_image_message.dart`). Compose/send in `canvas_editor_screen.dart`; manage in `mco_image_gallery_screen.dart`. Channel image payloads go through `helpers/channel_binary_data_helper.dart` (`ChannelBinaryDataKind { mcoImage, mcoImageV3, mcmp }`).

### Wardriving (coverage mapping)
Turns the app into a mesh coverage scanner (`services/wardrive_service.dart`, driven from `map_screen.dart` / `widgets/wardrive_status_panel.dart`). Each cycle (default 25 s, 5–300 s configurable) takes a GPS fix, sends a self-advert + zero-hop discovery request, and listens ~10 s for `DiscoverResp` frames; each responder → a GPS-tagged `WardriveSample` (SNR/RSSI/node key/response time), plus `pingSuccess=false` "dead zone" samples when nobody answers. `wardrive_upload_service.dart` POSTs sample batches as JSON to configurable sites (default `https://meshwar-map.pages.dev/api/samples`), de-duping per endpoint. `wardrive_foreground_service.dart` runs an Android **location** foreground service (MethodChannel `mco_advanced/wardrive_foreground`), gated in Dart so ordinary BLE users don't inherit location FGS.

### Region / flood-scope routing
Channels can be tagged with a named region; `cmdSetFloodScope` (54) / `cmdSetDefaultFloodScope` (63) hash `#<name>` (SHA-256, first 16 bytes) into a scope. Managed in `region_management_screen.dart`; persisted in `region_store` / `channel_region_store`.

### DirectRepeater last-hop path selection
`DirectRepeater` (top of `meshcore_connector.dart`) tracks the ≤5 best last-hop repeaters ranked by SNR + recency (stale after 30 min), built from advert path tails and repeater-ACK trip-times (fed to `PathHistoryService`). Feeds auto route-rotation in `preparePathForContactSend()`. Related: **path-hash mode** (`cmdSetPathHashMode`, variable 1–4 byte per-hop hash width).

### Other UX
Per-conversation **sending delay** (schedule/commit/cancel a queued send), **quick answers** (canned composer replies, `helpers/quick_answers_helper.dart`), per-channel **widget color**, and a **translate UI shell** (`widgets/message_translation_button.dart`) that only writes the target-language setting (translation itself is disabled).

## Transports

`MeshCoreConnector` unifies all three transports under one `ChangeNotifier`. There is **no shared base class** — selection is via the `MeshCoreTransportType { bluetooth, usb, tcp }` enum, and BLE/TCP/USB share the same connection-state enum, send/receive API, and frame protocol.

### Connection State
```dart
enum MeshCoreConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
}
```

### Frame I/O (all transports)
- **Send**: `MeshCoreConnector.sendFrame(Uint8List data, {String? channelSendQueueId, bool expectsGenericAck})`
- **Receive**: `Stream<Uint8List> get receivedFrames`
- **Protocol constants** (`meshcore_protocol.dart`): `maxFrameSize = 176`, `maxTextPayloadBytes = 160`, `maxChannelDataLength = 165`, `appProtocolVersion = 4`. Command codes are top-level `cmd*` consts (app→device, 1…64), responses `respCode*` (with v3 variants `…RecvV3`), async pushes `pushCode*` (`0x80`…`0x8E`), mesh-layer `payloadType*`. Frames are built/parsed with `BufferWriter` / `BufferReader` and `build*Frame` / `parse*` helpers.

### BLE — Nordic UART Service (NUS)
- **Service UUID**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- **RX Characteristic** (write to device): `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- **TX Characteristic** (notify from device): `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
- **Discovery**: filters on the **NUS service UUID** (not the device name) so community forks with custom names are still found. `MeshCoreUuids.deviceNamePrefixes` (`MeshCore-`, `Whisper-`, `WisCore-`, `Seeed`, `Lilygo`, `HT-`, `LowMesh_MC_`, `NRF52`) is kept only for reference/display heuristics.
- **Linux**: `linux_ble_pairing_service.dart` falls back to `bluetoothctl` when BlueZ agent prompts fail

### TCP
- Manual host/port entry, persisted via `AppSettingsService` (`tcpServerAddress`, `tcpServerPort`)
- UI hint: `192.168.40.10` / port `5000`
- Disabled on web (`PlatformInfo.isWeb`)
- API: `MeshCoreConnector.connectTcp(host: ..., port: ...)`

### USB Serial (flserial)
- Default baud rate: `115200`
- Port enumeration: `MeshCoreConnector.listUsbPorts()`
- COBS-framed packets via `usb_serial_frame_codec.dart`
- macOS device-name resolution via `ioreg` (`utils/macos_usb_device_names.dart`)
- API: `MeshCoreConnector.connectUsb(portName: ..., baudRate: 115200)`

## Dependencies

App version: `9.5.0-mcoa.1.8.2+39` — Dart SDK constraint: `^3.9.2`

**Connectivity**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | ^2.1.0 | BLE scanning, connecting, and UART data transfer |
| flutter_blue_plus_platform_interface | ^9.0.2 | Platform-interface layer required by flutter_blue_plus |
| flserial | git (MeshEnvy fork) | USB serial transport for wired device connections (TODO: upstream pending) |

**State / Storage**

| Package | Version | Purpose |
|---------|---------|---------|
| provider | ^6.1.5+1 | ChangeNotifier-based state management across screens |
| shared_preferences | ^2.2.2 | Persistent key-value storage for user settings |
| path_provider | ^2.1.5 | Locates platform-appropriate directories for file I/O |

**Crypto**

| Package | Version | Purpose |
|---------|---------|---------|
| crypto | ^3.0.3 | SHA/HMAC hashing used in message authentication + flood-scope hashing |
| pointycastle | ^4.0.0 | AES encryption/decryption for channel and direct messages |
| cryptography | ^2.9.0 | Ed25519 verification of MCMP v3 message signatures (signing happens on the node via CMD_SIGN_*) |
| cryptography_flutter | ^2.3.4 | Native crypto acceleration for the `cryptography` package |
| convert | ^3.1.2 | Hex/base codec helpers used across protocol + image codecs |
| uuid | ^4.3.3 | Generates UUIDs for message and contact identity |

**Maps & Location**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_map | ^8.2.2 | Interactive tile map for node positions and path traces |
| latlong2 | ^0.9.1 | LatLng coordinate type used throughout map and GPS code |
| geolocator | ^13.0.2 | Phone GPS fixes for own-position advert and wardrive sampling |
| gpx | ^2.3.0 | Export node paths as GPX track files |

**UI**

| Package | Version | Purpose |
|---------|---------|---------|
| material_symbols_icons | ^4.2928.1 | Extended Material Symbols icon set (line-of-sight, etc.) |
| flutter_svg | ^2.0.10+1 | Renders SVG assets (custom icons such as LoS indicator) |
| cached_network_image | ^3.4.1 | Caches map tile images downloaded over the network |
| flutter_cache_manager | ^3.4.1 | Underlying cache manager used by cached_network_image |
| flutter_linkify | ^6.0.0 | Auto-detects and makes URLs tappable in chat messages |
| mobile_scanner | ^7.1.4 | QR/barcode scanning for contact and channel import |
| qr_flutter | ^4.1.0 | Generates QR codes for sharing contacts and channels |
| cupertino_icons | ^1.0.8 | iOS-style icon font (bundled for completeness) |
| characters | ^1.4.0 | Unicode-aware string operations for message text handling |

**Notifications / Background**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_local_notifications | ^22.0.0 | Shows local push notifications for incoming messages |
| flutter_foreground_task | ^9.2.0 | Keeps the app alive in background to maintain BLE/USB connection |

**ML**

| Package | Version | Purpose |
|---------|---------|---------|
| ml_algo | ^16.0.0 | OLS regression used in `timeout_prediction_service.dart` to predict message ACK timeouts |
| ml_dataframe | ^1.0.0 | DataFrame input format required by ml_algo |

> `llamadart` and `flutter_langdetect` (on-device LLM translation) have been **removed** — translation is disabled in this build.

**Misc**

| Package | Version | Purpose |
|---------|---------|---------|
| http | ^1.2.0 | Fetches tile URLs, remote API calls, and wardrive sample uploads |
| url_launcher | ^6.3.0 | Opens URLs in the system browser from linkified chat text |
| share_plus | ^13.1.0 | Shares files (e.g. exported GPX tracks) via the system share sheet |
| file_selector | ^1.0.3 | Native open/save dialogs for image packs and GPX/exported files |
| archive | ^4.0.9 | Reads/writes `.mcoimg.pack` image-pack archives |
| wakelock_plus | ^1.5.2 | Keeps the screen awake during scanning / wardriving |
| package_info_plus | ^10.1.0 | Reads app version/build number displayed in settings |
| web | ^1.1.1 | Web-platform APIs for USB serial and browser detection on Flutter Web |
| intl | any | Internationalization and locale formatting (required by flutter_localizations) |
| build_pipe | ^0.3.1 | CI/CD build pipeline configuration (web release builds with versioned assets) |

## Platform Configuration

### Android (`android/app/src/main/AndroidManifest.xml`)
- `INTERNET` (map tiles, wardrive sample uploads)
- `BLUETOOTH`, `BLUETOOTH_ADMIN` (API ≤ 30)
- `BLUETOOTH_SCAN` (with `neverForLocation`), `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` (API 31+)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (BLE scanning on API ≤ 30)
- `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION` (optional wardrive background sampling — gated in Dart so ordinary BLE users don't inherit them)
- `POST_NOTIFICATIONS` (API 33+)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` (background BLE/USB connection)
- `WAKE_LOCK`
- `CAMERA` (QR scanning, declared as optional feature)
- USB host hardware feature (optional)

`flutter_foreground_task` registers a connected-device `ForegroundService` (`foregroundServiceType="connectedDevice"`, `stopWithTask="false"`); a separate wardrive `location` foreground service is declared and enabled only via the Android-only wardrive path.

**Build config (`android/app/build.gradle.kts`)**: `applicationId = com.meshcore.meshcore_open`, NDK `29.0.14206865`, Java 8 core-library desugaring (`desugar_jdk_libs:2.1.4`), release signing via `key.properties` (debug fallback).

### iOS (`ios/Runner/Info.plist`)
- Display name `MCO Advanced`
- `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`
- `NSCameraUsageDescription` (QR scanning to join communities)
- `NSLocationWhenInUseUsageDescription` (tag wardrive discovery requests + update own node position)
- Background modes: `bluetooth-central` (no location background mode — iOS wardriving is foreground-only)
- `LSApplicationQueriesSchemes`: `http`, `https`

### Web (`web/`)
PWA scaffold present but boilerplate (`manifest.json` and `index.html` are unmodified Flutter defaults). BLE is unsupported in browsers; TCP and Web Serial USB may work in Chrome only. `ChromeRequiredScreen` gates non-Chrome web users. Versioned releases are produced via `build_pipe` (`?v=<pubspec version>` cache busting, no service worker).

### Desktop
`linux/`, `windows/`, and `macos/` directories are present as Flutter scaffolds. No app-specific native config has been added; BLE on desktop has not been validated.

## Coding Conventions

### Code Philosophy
- **Minimal**: Only write code that is necessary. Avoid over-engineering.
- **Organized**: Keep related code together. One responsibility per file.
- **Maintainable**: Favor readability over cleverness. Simple is better.

### Style
- Use `StatelessWidget` with `Consumer` for state-dependent UI
- Use `const` constructors where possible
- Prefix private methods/fields with `_`
- Center app bar titles (`centerTitle: true`)
- **Material widgets only** - no Cupertino or custom widgets
- Handle disconnection gracefully (auto-navigate back to scanner)

### Avoid
- Premature abstractions - don't create helpers until needed in 3+ places
- Unnecessary comments - code should be self-explanatory
- Feature flags or backwards-compatibility shims
- Over-engineered error handling for impossible scenarios

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App configuration, MultiProvider setup, theme, locale, initial route |
| `lib/connector/meshcore_connector.dart` | Unified BLE/TCP/USB transport state holder |
| `lib/connector/meshcore_protocol.dart` | Frame size limits and protocol version |
| `lib/connector/meshcore_uuids.dart` | NUS UUIDs and BLE scan name prefixes |
| `lib/services/app_settings_service.dart` | App-wide settings (`AppSettings` JSON in SharedPreferences) |
| `lib/services/storage_service.dart` | Path history + delivery observation persistence |
| `lib/services/message_retry_service.dart` | ACK tracking + retry scheduling |
| `lib/services/translation_service.dart` | On-device LLM translation — **disabled stub** in this build |
| `lib/services/wardrive_service.dart` | Coverage-mapping scanner (Advanced mod) |
| `lib/helpers/mesh_compressor.dart` | MCMP arithmetic-coder text compression (`mcmp2:`) |
| `lib/helpers/message_text_codec.dart` | Inbound decode across MCMP/Smaz prefixes |
| `lib/helpers/mcmp_signature_verifier.dart` | App-side Ed25519 verification of MCMP v3 signatures |
| `lib/helpers/exact_quote_helper.dart` | Quote fragments that pin plain-text replies to the message they answer |
| `lib/helpers/message_markup.dart` | Inline `**bold**` / `__italic__` / `~~strike~~` / mono markup parser |
| `lib/helpers/mcoimg_v3_codec.dart` | MCO image-over-LoRa codec (v3 binary container) |
| `lib/storage/prefs_manager.dart` | SharedPreferences singleton initialized in `main()` |
| `lib/screens/scanner_screen.dart` | Home screen — BLE scan and connect |
| `lib/screens/mod_settings_screen.dart` | Advanced-mod feature toggles |
| `pubspec.yaml` | Dependencies and project metadata (current version `9.5.0-mcoa.1.8.2+39`) |
