# MeshCore Open - Flutter Client

Open-source Flutter client for MeshCore LoRa mesh networking devices. Connects to MeshCore-compatible radios over **BLE, TCP, or USB serial** and provides direct/channel chat, contact and channel management, on-map node tracking, repeater administration, and on-device message translation.

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
├── services/        # ChangeNotifier services + IO services (retry, translation, ML, …)
├── storage/         # SharedPreferences-backed stores, scoped per device key
├── helpers/         # Pure utilities (Smaz compression, GIF parsing, scroll helpers, path hop resolution)
├── utils/           # Platform / IO / UX utilities (logger, GPX export, dialogs)
├── theme/           # MeshPalette (defined, not yet wired in main.dart)
├── l10n/            # ARB localization for 18 locales
├── icons/           # Custom icon widgets
├── widgets/         # Reusable widgets (AppBar, BatteryUi, QR, jump-to-bottom, …)
└── screens/         # ~26 screens — see Screens section below
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
| `app_debug_log_screen.dart` | In-app log viewer (app-layer messages) |
| `ble_debug_log_screen.dart` | In-app log viewer (raw BLE frame traffic) |
| `companion_radio_stats_screen.dart` | RF stats (RSSI, SNR, packet counts) for paired radio |
| `telemetry_screen.dart` | Battery / sensor / environmental telemetry for a contact |

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
| `TranslationService` | On-device LLM translation (llamadart) |
| `UiViewStateService` | Contacts/channels sort/filter/search state |
| `TimeoutPredictionService` | ML linear regression for ACK timeout prediction |
| `StorageService` | Path history + delivery observation persistence |
| `MapTileCacheService` | OSM tile pre-cache |

Screens consume these via `Consumer<T>` (or `context.watch<T>()` / `context.read<T>()`) for reactive UI.

### Storage / Persistence

All stores in `lib/storage/` use `PrefsManager` (a `SharedPreferences` singleton initialized in `main()`). Most stores **scope keys by the first 10 hex chars of the connected device's public key**, so per-radio data is isolated.

| Store | Persists |
|---|---|
| `message_store`, `channel_message_store` | Direct + channel messages |
| `contact_store`, `contact_discovery_store` | Known + discovered contacts |
| `channel_store`, `channel_order_store`, `channel_settings_store` | Channels, display order, per-channel Smaz toggle |
| `community_store` | Communities (32-byte shared secrets) |
| `contact_group_store`, `contact_settings_store` | Groups, per-contact Smaz toggle |
| `unread_store` | Per-contact unread counts (debounced writes) |

GGUF translation models are stored as files (not SharedPreferences) via `translation_file_store`.

### Theming
- Material 3 design (`useMaterial3: true`)
- System-based dark/light mode (`ThemeMode.system`)
- Blue color scheme seed
- `lib/theme/mesh_theme.dart` defines a warm-dark `MeshPalette` (phosphor-green accents) but is **not currently wired** in `main.dart` — available for a future redesign

### Localization

18 locales supported via Flutter's standard ARB pipeline (`lib/l10n/`): en, de, es, fr, it, pt, ru, uk, bg, hu, ja, ko, nl, pl, sk, sl, sv, zh. Language override comes from `AppSettingsService.settings.languageOverride`. Use the `context.l10n` extension (`lib/l10n/l10n.dart`) for translated strings; contact-type names live in `contact_localization.dart`.

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
- **Protocol constants** (`meshcore_protocol.dart`): `maxFrameSize = 172`, `maxTextPayloadBytes = 160`, `appProtocolVersion = 4`

### BLE — Nordic UART Service (NUS)
- **Service UUID**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- **RX Characteristic** (write to device): `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- **TX Characteristic** (notify from device): `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
- **Discovery**: scans for devices whose name starts with `MeshCore-`, `Whisper-`, `WisCore-`, `Seeed`, `Lilygo`, `HT-`, or `LowMesh_MC_` (filters on both `platformName` and `advertisementData.advName`)
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

App version: `9.5.0+13` — Dart SDK constraint: `^3.9.2`

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
| crypto | ^3.0.3 | SHA/HMAC hashing used in message authentication |
| pointycastle | ^4.0.0 | AES encryption/decryption for channel and direct messages |
| uuid | ^4.3.3 | Generates UUIDs for message and contact identity |

**Maps & Location**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_map | ^8.2.2 | Interactive tile map for node positions and path traces |
| latlong2 | ^0.9.1 | LatLng coordinate type used throughout map and GPS code |
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

**ML / AI**

| Package | Version | Purpose |
|---------|---------|---------|
| ml_algo | ^16.0.0 | OLS regression used in `timeout_prediction_service.dart` to predict message ACK timeouts |
| ml_dataframe | ^1.0.0 | DataFrame input format required by ml_algo |
| llamadart | ^0.8.0 | On-device LLM inference used in `translation_service.dart` for message translation |
| flutter_langdetect | ^0.0.1 | Detects a message's source language in `translation_service.dart` before translating |

**Misc**

| Package | Version | Purpose |
|---------|---------|---------|
| http | ^1.2.0 | Fetches tile URLs and any remote API calls |
| url_launcher | ^6.3.0 | Opens URLs in the system browser from linkified chat text |
| share_plus | ^13.1.0 | Shares files (e.g. exported GPX tracks) via the system share sheet |
| package_info_plus | ^10.1.0 | Reads app version/build number displayed in settings |
| web | ^1.1.1 | Web-platform APIs for USB serial and browser detection on Flutter Web |
| intl | any | Internationalization and locale formatting (required by flutter_localizations) |
| build_pipe | ^0.3.1 | CI/CD build pipeline configuration (web release builds with versioned assets) |

## Platform Configuration

### Android (`android/app/src/main/AndroidManifest.xml`)
- `INTERNET` (map tiles, translation model downloads)
- `BLUETOOTH`, `BLUETOOTH_ADMIN` (API ≤ 30)
- `BLUETOOTH_SCAN` (with `neverForLocation`), `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` (API 31+)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (BLE scanning on API ≤ 30)
- `POST_NOTIFICATIONS` (API 33+)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` (background BLE/USB connection)
- `WAKE_LOCK`
- `CAMERA` (QR scanning, declared as optional feature)
- USB host hardware feature (optional)

`flutter_foreground_task` registers a `ForegroundService` with `foregroundServiceType="connectedDevice"` and `stopWithTask="false"`.

**Build config (`android/app/build.gradle.kts`)**: `applicationId = com.meshcore.meshcore_open`, NDK `29.0.14206865`, Java 8 core-library desugaring (`desugar_jdk_libs:2.1.4`), release signing via `key.properties` (debug fallback).

### iOS (`ios/Runner/Info.plist`)
- `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`
- `NSCameraUsageDescription` (QR scanning to join communities)
- Background modes: `bluetooth-central`
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
| `lib/services/translation_service.dart` | On-device LLM translation (llamadart) |
| `lib/storage/prefs_manager.dart` | SharedPreferences singleton initialized in `main()` |
| `lib/screens/scanner_screen.dart` | Home screen — BLE scan and connect |
| `pubspec.yaml` | Dependencies and project metadata (current version `9.5.0+13`) |
