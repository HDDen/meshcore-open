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
├── storage/         # Per-device-key stores (SharedPreferences; message history in SQLite)
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
| `message_history_database_screen.dart` | Message-history database: statistics, migration quarantine, exports, vacuum |
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
| `SettingsSectionsService` | Public stub/private-module bridge for optional settings sections and device capabilities |
| `TimeoutPredictionService` | ML linear regression for ACK timeout prediction |
| `StorageService` | Path history + delivery observation persistence (`Provider`, not `ChangeNotifier`) |
| `MapTileCacheService` | Raster map tile cache and offline-region downloads |
| `WardriveService` | Coverage-mapping scanner: GPS-tagged SNR/RSSI samples + cloud upload (Advanced mod) |
| `ImageCodecService` | Optional AEIC encoder/decoder backend and model lifecycle |
| `ReceivedImageStore` | Persistent AEIC receive/send state, lazy image bytes and decode queue |

Non-provider singletons wired in `main()`: `NotificationService`, `BackgroundService` (Android foreground-process/Flutter-engine retention for BLE, optional TCP and wardrive keep-alive reasons), `MeshCompressor` (MCMP model init), `MCOImageGalleryStore` (installs bundled image packs). `BackgroundService` does not own BLE or parse frames: the retained engine keeps the existing `MeshCoreConnector` alive.

Screens consume these via `Consumer<T>` (or `context.watch<T>()` / `context.read<T>()`) for reactive UI.

### Storage / Persistence

Most stores in `lib/storage/` use `PrefsManager` (a `SharedPreferences` singleton initialized in `main()`) and **scope keys by the first 10 hex chars of the connected device's public key**, so per-radio data is isolated. **Message history is the exception**: it lives in SQLite (see the next section) while keeping the very same key strings, so the stores above it did not change shape.

| Store | Persists |
|---|---|
| `message_store`, `channel_message_store` | Direct + channel messages (SQLite-backed, see below) |
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

A few states are deliberately **unscoped by node** because they describe this phone rather than any radio's data. The blocked-sender table is managed through `BlockedSenderStore`, the map's node-filter chip row writes its collapsed or expanded state directly under `map_node_filters_expanded_v1`, and whether the battery-optimization exemption has ever been asked for is recorded under `background_battery_exemption_asked_v1` (see the Android section). Anything holding per-radio data belongs in a scoped store instead.

### Message history database

Message history moved out of `SharedPreferences` into SQLite via **drift** (`message_history.sqlite` in `getApplicationSupportDirectory()`). Three decisions shape everything else, and all three exist to keep the change to a storage backend rather than a rewrite:

- **One table for both kinds.** `HistoryMessages` carries a `kind` discriminator (`0` = direct, `1` = channel) instead of two parallel tables, which would have doubled every query for nothing.
- **The key space is unchanged.** `storageKey` *is* the former preferences key (`messages_<10hex><contactKey>`, `channel_messages_<10hex>name_<…>`), so `MessageStore` / `ChannelMessageStore` still speak the same strings and all the legacy-key handling — scoped vs unscoped, name-keyed channels — keeps working untouched.
- **The message stays JSON.** `messageJson` holds the whole serialized message; the other columns are denormalized projections of it, added only for the queries that actually run. `MessageHistoryStorage` hands callers back a JSON array string, so `_messageToJson` / `decodeStoredMessage` never had to change.

`MessageHistoryStorage` is the only door to the database. Every method has a `kIsWeb` branch that falls back to `SharedPreferences`, because the web build never creates the database at all — `initializeAndMigrate` returns before constructing it, which is why `web/` carries no `sqlite3.wasm` or `drift_worker.js` despite the `DriftWebOptions` in the constructor.

**Indexes** (`schemaVersion = 1`, `auto_vacuum = INCREMENTAL` set in `onCreate` *before* `createAll()` — the only moment that pragma takes effect):

| Index | Serves |
|---|---|
| `history_message_timeline` (kind, storageKey, timelineAtMs, messageId) | cursor pagination |
| `history_message_identity` (kind, storageKey, messageId) UNIQUE | upsert by message id |
| `history_message_summary` (kind, storageKey, isCli, timelineAtMs, messageId) | contact-list previews, covers the `ORDER BY` too |
| `history_message_marker` (kind, storageKey, containsMarker) | the map's marker sweep |
| `legacy_rejected_location` (kind, storageKey, messageIndex) | quarantine listing |

**`timelineAtMs` repeats the domain rules rather than inventing its own.** It is `receivedAt ?? timestamp` for channel rows and for room messages (detected by a non-empty `fourByteRoomContactKey`), and plain `timestamp` for ordinary direct messages — so SQL order matches `ChannelMessageTimelineHelper.compare` / `RoomMessageTimelineHelper.compare` instead of drifting from them. Contact-list summaries sort by the same column, which is why a room contact's `lastMessageAt` is its local receive time and not the timestamp the room server stamped.

**Reads are windowed and cursor-paginated.** Opening a conversation asks for `_initialContactHistorySize` / `_initialChannelHistorySize` (300 each); offline shared mode merges up to `_offlineSharedHistoryWindowSize` (1000) per scope. Older pages come from `loadMessagesBefore` / `loadChannelMessagesBefore`, anchored on the pair `(timelineAtMs, messageId)` — the second half of the key is what keeps ordering stable when several messages share a millisecond. `loadNewerMessages` / `loadNewerChannelMessages` are the forward half of the same cursor and are implemented but not yet called by any screen.

**Writes are per row.** Receiving a message upserts one row (`saveMessage` / `saveChannelMessage`); before, every incoming message re-serialized the whole conversation and rewrote the entire preferences file. `saveMessages` / `saveChannelMessages` still exist but their meaning changed from *replace* to *upsert*, so the four remaining call sites are all blocked-sender sweeps that genuinely touch several rows. Deleting is `deleteMessage`, clearing a conversation is `clearMessages` / `clearChannelMessages` — passing a shortened list no longer removes anything.

**Two in-memory caches** are filled by one `SELECT DISTINCT` each at startup and maintained on write: the set of known `storageKey`s per kind, and the keys whose history contains a marker. The marker cache is deliberately **add-only** on point upserts — a stale positive costs one wasted history read, while `replaceString` and `deleteMessage` recompute it exactly. That asymmetry is intentional and commented in place; it keeps `mayContainMarker` synchronous, which the map's sweep over every contact depends on.

**Corrupt records never take the whole read down.** `_messagesFromJson` / `_channelMessagesFromJson` decode element by element and skip a bad one with a log line instead of returning an empty list, so one unreadable message costs one message rather than the entire conversation.

### Migrating the legacy history

The move from preferences is **one-way, one-time and irreversible**, and it will meet years of accumulated real data on every device exactly once. Everything below exists because of that.

`MessageHistoryStorage.initializeAndMigrate()` runs from `main()` before any service exists. It finds legacy keys with strict regexes, imports them, and only then removes them from preferences. The import, the skip counters and the `legacy_migration_complete` flag all commit **in one transaction, before cleanup**, so an interrupted cleanup resumes on the next launch without importing anything twice.

The import walks one `storageKey` at a time in chunks of 200, yielding to the event loop between chunks, and reports through `migrationProgress` — a `ValueListenable` the `MessageHistoryMigrationApp` screen renders as "conversation N of M". Without the chunking the indicator would freeze, because `_companionsFor` runs `MessageTextCodec.tryDecodeKnownCompression` on legacy rows that predate `rawText`, and that is the MCMP arithmetic decoder. On desktop the app restarts itself afterwards (`restartAfterMigration`).

**Damage is skipped at two levels.** A container that will not `jsonDecode` costs that conversation; a single element that is not an object, or whose field has the wrong type, costs that message. The `catch` deliberately takes everything except `OutOfMemoryError` and `StackOverflowError` — a `TypeError` from `as int?` on a JSON double is the common case and is not an `Exception` — but it is drawn tightly around the pure conversion, with `batch()` outside it, so a database failure can never be mistaken for bad data.

**Validation runs the real parser.** `main()` passes `MessageStore.decodeStoredMessage` / `ChannelMessageStore.decodeStoredMessage` as `validateMessage`, so a message is only imported if the code that will later read it can read it. Checking only the ten fields `_companionsFor` touches would let a broken value ride along inside `messageJson` and fail at display time instead.

### Migration quarantine

Whatever the import skips is written to `LegacyRejectedMessages` **in the same transaction** — which is what makes it safe to wipe the preferences afterwards. A rejected element is stored as itself; a rejected container is stored whole, since there is nothing smaller to keep. Rows carry `rawValue`, `errorType`, `errorText` (capped at 1000 chars) and `messageIndex`; the write is kept deliberately primitive so the safety net cannot itself fail the migration.

`retryLegacyRejected` re-runs the quarantine through the current parser. A container is re-split, and whatever still fails comes back as *per-element* rows with an index — so every attempt makes the quarantine finer rather than repeating itself. `resolvedMessageId` is preserved so a recovered message lands under the id it would have had originally. This is the path that matters when the defect was in *our* parser rather than in the data: a later build simply recovers what an earlier one rejected.

Two exports, deliberately separate:

- **diagnostic** — schema version, error *types*, indexes and SHA-256 hashes of `storageKey`. No message text: `errorText` is excluded because `FormatException` from `jsonDecode` quotes the source around the failure, which would put conversation text into a file meant to be safe to send.
- **recovery** — the rejected entries with their original content, behind a confirmation that says so.

Both go through `file_selector.getSaveLocation` on desktop and `SharePlus` on mobile (falling back to share if the save dialog fails), because `getApplicationSupportDirectory()` is unreachable for a user on Android and iOS. The three outcomes are distinguished: a path means saved, an empty string means handed to the share sheet, `null` means the user cancelled — and a cancelled export must not be followed by the "delete the quarantine now?" prompt.

Counters live in `HistoryMetadata` (`legacy_migration_skipped_histories`, `…_skipped_messages`, `…_warning_pending`) and drive a one-time dialog shown from a post-frame callback after normal startup, with a button into the management screen. Migration logging uses `developer.log` rather than `appLogger` on purpose: `appLogger.initialize` happens far later in `main()` than the migration does.

`message_history_database_screen.dart` (UI) and `message_history_maintenance.dart` (statistics, exports, quarantine, vacuum) hold all of this, keeping `mod_settings_screen.dart` down to one section and a route. `PRAGMA incremental_vacuum` only works when `auto_vacuum = 2`, so the screen disables that action and swaps its description when `autoVacuumMode` says otherwise — databases created before the pragma was added need a full `VACUUM` first, which also switches the mode over.

### Offline history mode

The BLE, USB and TCP connection screens expose the same `OfflineHistoryButton`. A user can open one saved node scope or choose the shared mode, which merges every known node scope without connecting to a radio. `MeshCoreConnector.enterOfflineHistory()` binds stores to the selected synthetic scope and uses read-only loading paths with legacy migration disabled; `exitOfflineHistory()` clears the offline state before a real connection begins. Shared offline mode builds a merged contact/channel/message view up front, while single-node mode keeps that node's settings, order and unread data.

Offline mode is deliberately read-only for radio/device state: chat composers and send buttons are disabled, contact/channel management, repeater/room login, wardrive, discovery, tracing and device/app-setting routes that require a live session are blocked. Local-only viewing tools remain available, including the map, message search, MCOimg gallery and canvas. `connect`, `connectUsb` and `connectTcp` reject calls while the offline session is active so incoming frames can never be written under the synthetic scope.

### Stored-message search

`widgets/message_search_sheet.dart` is shared by contacts, channels and individual chat screens. It searches decoded human-readable text across the requested channel/contact/room scope, includes the configured shared-history scopes, debounces input for 1500 ms and processes bounded batches through `helpers/message_search_worker.dart` so parsing does not block the UI isolate. Results are ordered newest first, deduplicated across node scopes using the same content identity used by shared channel history, and retain enough source/message identity to open the conversation and materialize/scroll to the stored message. Desktop chat/list screens expose the same action through Ctrl+F.

### Deleting a shared-history message

Shared history is read out of the *other* node scopes in the same database and merged into the open chat on the fly (`_sharedChannelSecondaryMessages` / `_sharedContactSecondaryMessages`), so deleting one of those messages has to reach the store it actually lives in. `deleteChannelMessage` / `deleteMessage` drop it from the merged-in list and then `SharedMessageHistoryHelper.deleteSecondary*Message` rewrites the other scope without it; dropping it in memory alone would bring it back on the next merge. Matching is by `messageId` (persisted in both stores), which also removes the copy the merge hid when the same message exists in two scopes — otherwise deleting the local one just uncovers the shared duplicate. `deleteChannelMessage` takes the `Channel` rather than reading `message.channelIndex`, because a shared message carries the *other* node's channel index.

Clearing a whole conversation deliberately works the other way: `clearMessagesForContact` / `clearMessagesForChannel` only hide the shared scope for the session (`_hiddenSharedContactKeys` / `_hiddenSharedChannelIdentityKeys`) and leave the other node's data alone.

### Contact message summaries and channel-screen visibility

`Contact.hasMessages` means that an actual direct-message history exists for the contact in either the current node's store or an enabled shared-history scope. Channel posts, adverts, and discovery activity must not set this flag. Missing `hasMessages` values in legacy `contact_store` / `contact_discovery_store` records are treated as `false`; `_refreshContactMessageSummaries()` rebuilds the flag from real local/shared message summaries and clears stale values. When summaries are merged, `lastMessageAt` remains monotonic and keeps the newest known timestamp.

Incoming channel activity may still advance a known contact's `lastMessageAt` for activity sorting, but `_updateContactLastMessageAtByName()` calls `_setContactLastMessageAt(..., markHasMessages: false)`, so this never makes an empty direct conversation appear on the channels screen. Channel-author attribution follows this order:

1. A valid MCMP v3 signature uses the verified full public key for an exact contact match.
2. Otherwise, the sender name is used only when it matches exactly one chat contact.
3. With no name match, the packet path may be used only when the negotiated path-hash width is at least two bytes and exactly one contact matches.

`verifiedSenderKeyHex` is populated only when the signature is valid. Callers must still require
`mcmpSignatureStatus == McmpSignatureStatus.valid` whenever they use it as authenticated identity;
the badge follows the same rule and never shows a fingerprint for invalid or unverifiable results.

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
MCMP v2 and SMAZ use their `encodeIfSmaller` paths. MCMP v3 always uses its metadata container
when selected for an eligible message, whether signed or unsigned; structured payloads that have
their own format stay outside the normal text-compression path.

The MCMP version and the sign flag are per channel and per contact (`channel_settings_store` /
`contact_settings_store`, each mirrored by a `MeshCoreConnector` getter for the window before the
stored value is read back). **The defaults are v3, unsigned**, and each of the two lives in four
places at once — two stores, two getters — so keep them in step. There is deliberately no migration:
a default reaches every channel and contact whose value was never written, not only new ones, and
only entries set by hand stay where they were put.

Unsigned is the deliberate half of that. The v3 container is taken for its structure — timestamp,
precise reply anchor, compression — while a signature costs 64 body bytes plus a `CMD_SIGN_*` round
trip, which firmware without those commands answers only by timing out (`_signAttempts` ×
`_signAttemptTimeout`, 5 × 3 s per message, before the send falls back to unsigned). Signing is
opted into per conversation instead.

Two consequences worth knowing. A plain chat contact never signs whatever the flag says —
`contactMcmpUseSign` is read only inside `contact.type == advTypeRoom` branches, a direct message
being authenticated by its own transport. And shared map markers on a channel travel as **plain
text** under this default: `allowMarkerPayload` is fed from the same flag, and an unsigned envelope
would cost bytes while proving nothing. A channel whose pins matter has to turn signing on, which is
what makes a `del:` command attributable.

### MCMP v3 signatures (Ed25519, verified app-side)
The node signs canonical message bytes via `CMD_SIGN_START/DATA/FINISH` (single global sign buffer
→ serialize sessions). The canonical data contains the v3 signing domain, channel/room context,
the destination binding (HMAC-SHA256 derived from the channel PSK, or the room's full public key),
sender name, MCMP timestamp, wire flags, optional reply author/timestamp, and decoded message text.
The 64-byte Ed25519 signature is stored inside the MCMP body.

**Verification is done entirely in the app** (`helpers/mcmp_signature_verifier.dart`,
`cryptography` package) against known contacts; firmware never verifies. A normal channel body
keeps its sender name in the outer GROUP_TEXT or GROUP_DATA envelope, and an embedded channel name
is accepted only when it matches that displayed name. A room body embeds the signed name and the
room post supplies the original author's four-byte public-key prefix; verification resolves that
prefix to full contact keys and also requires the signed name to match the contact. Direct-contact
MCMP v3 messages are not Ed25519-signed and use the authenticated contact transport status.

`McmpSignatureStatus`, the verbatim container metadata, the MCMP-only signature fields
(`mcmpIsSigned`, `mcmpSignature`), the verified full key and the name-collision flag are persisted
on `Message` / `ChannelMessage`. The container metadata is the four `container*` fields —
`containerTimestamp`, `containerSenderName`, `containerReplyAuthorName`,
`containerReplyTimestamp` — and they are deliberately shared by MCMP v3 and MCOtxt v1: both
codecs carry a timestamp, an optional embedded sender name and a reply anchor, and everything
that consumes an anchor (reply resolution, exact quotes, the clock-mismatch warning) reads these
fields without asking which codec filled them; `compressionType` already says that.
`containerSenderName` holds only a name embedded in the body (room posts, the binary channel
envelope): the channel text transport leaves the name in the outer `Name: text` layer, so both
codecs report `null` there. The stores write the `container*` JSON keys and still read the legacy
`mcmp*` keys, so history written before the rename needs no migration. The badge shows a
fingerprint only for `valid` results.
Incoming messages also compare the container timestamp with `message.timestamp` through
`helpers/mcmp_timestamp_warning.dart`: a difference greater than
`mcmpTimestampWarningThreshold` (30 minutes) adds the red clock indicator, while the details screen
shows the distinct container timestamp whenever the two second values differ. That helper detects a
clock mismatch and nothing more — it neither establishes freshness nor proves that a replay
occurred — and signature status and timestamp comparison stay separate UI fields.

The wire format itself — body layout, flags, both transports, the canonical signing bytes, the
destination bindings and the `CMD_SIGN_*` exchange — is specified in
[`docs/MCMP_V3_PROTOCOL.md`](docs/MCMP_V3_PROTOCOL.md) (Russian: `docs/MCMP_V3_PROTOCOL_RU.md`).
That document is written for other implementations, so keep it in step with the codec whenever the
container changes.

### Reactions
Emoji reactions ride the normal text channel as a compact `r:<4hex-targetHash>:<2hex-emojiIndex>` string (`helpers/reaction_helper.dart`) — no protocol extension. Target hash = `computeReactionHash(timestampSecs, senderName?, textPrefix)`; sender name omitted for 1:1. Processed in the connector's reactions region.

### Channel message timeline

`ChannelMessage` deliberately carries three clocks. `timestamp` is the time shown in message
bubbles: incoming GROUP_TEXT takes it from the outer packet, while incoming MCMP GROUP_DATA uses
the MCMP body timestamp because that transport has no independent packet timestamp. Outgoing rows
are aligned to the first transmission attempt. `receivedAt` is the app-local timeline used by
history ordering, pagination, shared-history insertion and channel-list previews.
`sentByRadioAt` is the first outgoing transmission-attempt anchor. Central rules live in
`helpers/channel_message_timeline_helper.dart`; connector receive/dedup paths and
`ChannelMessageStore` must use that helper rather than sorting channel messages by `timestamp`.

Live incoming messages are stamped before asynchronous verification. Repeated incoming copies keep
the earliest physical receipt, which also repairs reversed async completion; self echoes preserve the
outgoing message's first `receivedAt` and `sentByRadioAt`. Outgoing time is assigned after the send
delay and radio-quiet wait, immediately before the transport write, and retries do not move it. This
is intentionally the first attempt time: a transport exception does not cause a later replay to
rewrite history.

The companion backlog frame has only the sender's packet timestamp. Firmware replays the queue FIFO,
so the initial post-connect drain assigns local monotonic `receivedAt` values in frame order (`now`,
or previous + one millisecond when the local clock did not advance). Legacy stored rows without
`receivedAt` fall back to `timestamp` because their real receive time cannot be reconstructed. When
shared history has the same packet in current and secondary scopes, the current-scope copy wins.

Room-server conversations use the same separation of clocks: `timestamp`, assigned by the room
server when it stores the post, is displayed in the bubble, while `receivedAt` controls stored order.
Initial queued room posts receive monotonic local
positions in companion FIFO order with a one-millisecond minimum step, and outgoing room posts are
positioned at their first transmission. Legacy rows without `receivedAt` fall back to `timestamp`.
The rules live in `helpers/room_message_timeline_helper.dart`.

### Direct and room message de-duplication

The node replays its offline queue on connect and can hand the same direct or room post over more
than once, so `_handleIncomingMessage` drops an incoming message that already sits in the
conversation. Identity is the packet timestamp in milliseconds plus the exact text, and the scan
covers the whole loaded conversation rather than only its last entry — a duplicate need not arrive
adjacent to its twin, since other senders' posts can be interleaved between the two copies.

For a room server that pair is not enough: two participants can post identical text in the same
second, and collapsing them would delete somebody's message. When the contact is `advTypeRoom` the
comparison therefore also requires an equal `fourByteRoomContactKey`, the author prefix the room
server stamps on every post. Only incoming messages are considered, and the check runs before the
message is stored, so nothing has to be undone afterwards.

### Blocked senders

A sender muted from a message's long-press menu keeps arriving — nothing is dropped on receipt or
removed from history — but their messages are neither shown nor acted on. It covers **channel
posts and room-server posts**; a one-to-one conversation has nothing to mute, being the contact
itself, which is deleted instead. The behaviour lives in two files:
`storage/blocked_sender_store.dart` (rules and JSON) and `helpers/blocked_senders.dart`
(`BlockedSenders.instance`, a singleton rather than a provider because the connector consults it
while parsing a frame). Two widgets carry the UI — `blocked_message_body.dart` for the
placeholder and `blocked_senders_sheet.dart` for the list.

**The table** is one app-wide JSON blob, **not** scoped by node public key like most stores here:
a sender worth muting is worth muting from every radio this phone connects to. A row's key is the
identity the mute is aimed at — a channel sender's name, or a room author's 4-byte public-key
prefix as uppercase hex. Rooms are keyed by the prefix because it is the stronger identity of the
two: a channel post carries whatever name its author typed, while the prefix is stamped on every
post by the room server itself, so a participant cannot wear somebody else's. The two key spaces
share one map and could in principle collide, on a channel sender literally named `AB12CD34`;
blocking one would then block the other, and that is the whole cost of not keeping a second
table.

A row carries three things.

- **`keyHex`** — the full public key behind a verified MCMP v3 signature, and an *exemption, not
  a requirement*. The row mutes the identity it is keyed by, and the only message it lets through
  is one that provably verified to a **different** key. That is the reasoning blocking itself
  follows — an unsigned message proves nothing about who sent it — applied to the arriving side.
  Requiring the key instead would let a muted sender walk out of the rule by not signing and,
  worse, by being deleted from contacts: with nobody left bearing that name a signature verifies
  as `unverifiable`, which reports no key at all, and muting somebody then removing them from
  contacts is the natural pair of actions. Never read `verifiedSenderKeyHex` without
  `mcmpSignatureStatus == valid` — `verifiedKeyOf` and `verifiedRoomKeyOf` are the only places
  that pairing is made.
- **`channels`** — always `["*"]` today; it exists so a per-channel block can be added later
  without migrating stored rules. Note that names are matched as the caller spells them, so the
  day a row stops being a wildcard, callers have to agree on what an unnamed channel is called;
  `MeshCoreConnector.channelDisplayName` is that one answer.
- **`blockedAt`** — where the rule starts, and it only ever travels backwards.

**The moment a rule starts at** is the message it was ordered from, not the tap: by the time
somebody long-presses a post, that sender has usually put several more on the screen above it,
and those are what the user is reacting to. It is clamped to now because `receivedAt` is our own
clock: live channel messages are stamped on first physical receipt, while the post-connect
backlog receives local monotonic times in the firmware's FIFO replay order. The sender-controlled
packet `timestamp` is stored separately and cannot push the boundary into the future. Blocking an
identity again takes the **earlier** of the stored moment and the new anchor (`_blockedAtFor`):
pointing further back strengthens the rule, pointing forward must not weaken it. A row written
before blocks carried a moment is stamped with the load time and written straight back, so the
stamp is decided once instead of drifting with every launch; the epoch would be the wrong default
there, since the date arm would then reach over the whole conversation and hide everything that
sender ever wrote.

Re-blocking never narrows the identity either: a second, different key under one row widens it to
the bare identity, the most a single-key record can express, and a row that already has no key
stays that way. Narrowing is a deliberate act, done by deleting the row and blocking again.
Because a re-block can still move `blockedAt` backwards, `block` bails out only when neither the
key nor the moment would change.

**Two questions, and the difference is only which clock the moment is compared against.**

- `isSenderBlocked` / `isRoomAuthorBlocked` — *is this sender muted right now?* — is the
  receive-time question, asked by `_addChannelMessage` and `_handleIncomingMessage`, and it
  compares no dates at all. A row that exists was created in the past, so a message arriving now
  is always after it; comparing our clock with our clock would add nothing and would misfire if
  the device clock stepped backwards. The answer is stamped onto the message as `wasBlocked`, and
  that flag keeps the receive-time decision independent from packet time. The backlog drain is
  covered too: its
  `receivedAt` is assigned locally before the message reaches this check, and its wire timestamp
  remains metadata only.
- `hidesStoredMessage` — *should this stored message be hidden?* — is the display-time question,
  and it does compare: `ChannelMessage.receivedAt` at or after `blockedAt`. It exists for messages
  the receive path never stamped, above all copies merged in from another node's shared history,
  which that node stored without ever seeing our rules. The packet's own `timestamp` is never
  consulted — the sender chooses it, and the moment of blocking is known only to us.

Everything that draws or interprets a channel message asks both and hides on either. Room posts
use the stamped `wasBlocked` flag; their `receivedAt` is the local conversation position rather
than sender-controlled packet metadata.

**Reaching the history already on screen.** `markChannelMessageBlocked` and
`markContactMessageBlocked` walk the loaded conversation from the newest message backwards and
stop at the one the block was ordered from, flagging what they pass. That costs only what the
user actually saw, never the whole conversation, and everything older than the anchor is left
alone — a block does not rewrite history the reader had already gone past. The anchor itself is
flagged whatever the rule says, since the user pointed at it; the messages above it only if the
rule really covers them, so a namesake exempted by a verified key stays visible. Both write to
the node's own store and to any shared scope holding the same message id, for the same reason
`_deleteSharedChannelMessage` does — flagging only the local copy lets the next merge uncover the
unflagged twin.

`applyBlockedSenderRules` is the other writer: it stamps the flag onto every loaded channel
message the date arm hides and saves the channels that changed. It runs on every change to the
table and once after a channel's history is read from storage, which is what makes that answer
permanent — lifting the block does not bring those messages, or the commands they carry, back.
Only this node's own store is swept; a copy merged in from another node is hidden by the
display-time check instead of being rewritten, since the flag it wants is the answer *our* rules
give, which is exactly what the check computes on the fly.

**Outgoing messages are never blocked.** `ruleFor` and `roomRuleFor` refuse them on their first
line, and the menu entry exists only for incoming messages. Without that, somebody adopting the
user's own callsign — which a channel post allows, the name being whatever its author typed —
could get him to mute himself. Any new display site must go through the helper rather than
inlining a lookup of its own, or it loses the guard.

**What the flag reaches.** Both chat screens compute `bodyText` once — the message text, or an
empty string when hidden — and every parser below reads that, so a hidden body produces no pin,
image, shared contact, coordinate link or quote. The placeholder takes the whole body and a tap
reveals the stored text, but revealing is a display choice: `bodyText` stays empty, so a revealed
marker still puts nothing on the map, and the revealed set is dropped whenever the table changes.
`_collectSharedMarkers` skips hidden messages **before** `SharedMarkerDeletions.absorb`, in the
contact loop as well as the channel one, or a muted troll's `del:` commands would still erase
everyone else's pins. The channels list shows the placeholder instead of the last-message
preview. Notifications and unread counts are gated on the rule directly at receive time: a
notification would put the hidden text straight back on screen, and a badge fed by a muted
flooder never stops climbing and reaches the OS app icon through `getTotalUnreadCount`. Reactions
are decided by the rule too and dropped in `_addChannelMessage` — a reaction has no body to hide,
lands in a `Map<emoji,count>` carrying no author, and is never stored, so there would be nothing
to re-evaluate later.

`wasBlocked` is persisted by `channel_message_store` and `message_store` and defaults to `false`
for older records. Repeats merge through `existing.copyWith(...)` without touching it, so the
first arrival decides. It also rides in `markerSignature`, next to `BlockedSenders.revision`:
flagging a message changes nothing else about it, and the map's marker cache would otherwise keep
drawing its pin. Revealing or hiding a body changes bubble heights, and without a guard the
post-frame snap that follows every list rebuild drags a reader sitting near the bottom down to the
newest message. Two guards cover that, for the two shapes the change takes. `_toggleBlockedBody`
is synchronous and sets `_channelSkipNextBottomSnap`, which the next snap consumes and clears.
`_toggleSenderBlock` and `_toggleRoomAuthorBlock` are not: blocking rewrites stored history and
the connector notifies more than once along the way, so both run their work inside
`ChatBottomSnapGuard.run` (`helpers/chat_scroll_controller.dart`), which holds the suppression
until the end of the frame that applies the final heights. Its generation counter is what keeps a
second toggle started mid-flight from letting the first one lift the guard early.

**Redrawing.** `BlockedSenders` is a `ChangeNotifier` and bumps `revision` on every write; the
connector re-emits that signal, so the chat, the channels list and the map redraw from the one
hook all three already watch. `revision` is a value rather than a bare notification because the
map's pin list is cached against a signature — a redraw alone would serve the cache.

**Unblocking** removes the row and clears no flags, the anchor's included. What arrived during a
block stays hidden for good; what arrives after the row is gone is shown and acted on as normal.

**The list.** `BlockedSendersSheet` opens from two overflow menus — inside a channel, below
`channels_editChannel`, and on the channels screen, below `chat_searchMessages`. It reads and
writes `BlockedSenders.instance` straight, since the table is app-wide and synchronous — nothing
is passed in and nothing handed back, which is what makes a second entry point free. Neither is
gated on offline mode, the list being local data. The channels screen hangs its handlers off
`PopupMenuItem.onTap`, which runs after the menu route has popped, so the sheet is opened from
the screen's context and `menuContext` is only used for the label.

Its **Add** dialog takes a name and nothing else, so `blockName` writes the widest row a name can
carry — no key, `["*"]` — which replaces a keyed row and, having no message to point at, cannot
move an existing moment backwards either. The dialog's controller is a `State` field because
`showDialog` completes on pop, while the dialog is still animating out and still reading it.

**Quotes of a hidden message.** A reply carries a snapshot of what it answers, taken when the
reply arrived, so a muted sender's words used to come back on screen through somebody else's quote.
`hidesQuotedMessage` is the question that keeps them off it, asked by `_buildReplyPreview` — the
only place a quote is drawn, since one-to-one and room conversations render no preview at all.

It answers from the original message when that is still in the loaded conversation, so the quote
mirrors the bubble a few rows up: nothing is hidden here that stays readable there, and nothing
stays readable here that was hidden there. With the original out of memory only the name is left,
and a name under a rule is hidden — a quote is text arriving now, not history the reader already
scrolled past, so the `blockedAt` boundary that spares old messages does not apply to it. Our own
name is refused on the first line, as `ruleFor` refuses outgoing messages.

Hiding runs through the same funnel as a bubble body: the local `replyText` becomes empty, so the
gif, marker and AEIC parsers below it see nothing and a hidden quote can no more draw an image or
a pin than a hidden message can. The author line stays — the block hides what was said, not that a
reply happened — and so does the tap, which scrolls to the quoted message as before.
`BlockedQuoteBody` (`widgets/blocked_message_body.dart`) draws the placeholder without
`BlockedMessageBody`'s reveal-on-tap, because that tap belongs to the preview.

**Not covered, deliberately**: one-to-one conversations, where the contact is deleted rather than
muted; the message search, which runs in a real isolate the table cannot be reached from; and
AEIC images, which never become a message object and carry no author name at all.

### Mentions
`@[name]` is the wire form for naming someone — replies have always used it, and it is typed directly too. Both ends live outside the screens: `helpers/mention_autocomplete.dart` for composing, `MentionText.split` (same file) for rendering.

**Composing.** `queryAt` reads the mention under the caret: it walks back to an `@`, bailing on whitespace or a bracket, and requires the `@` to open a word. `suggestionsFor` then matches the typed fragment against `MeshCoreConnector.allContacts` — the node's own contacts plus the app's discovery cache, so somebody heard advertising can be addressed before being added to the radio — and sorts alphabetically. Wired into the channel composer and — via a `type == advTypeRoom` check — the room-server one; a one-to-one chat has nobody to disambiguate. Picking inserts `@[name]` followed by a space and leaves the caret past it, ready for the next word; the space is skipped when the text already continues with whitespace, so a mention picked mid-sentence does not leave a double one, and either way the caret ends up after exactly one whitespace character. That also closes the panel — `queryAt` walks back from the caret and stops at whitespace — as the closing bracket alone already did.

The search is debounced by `MentionSearchDebounce` (750 ms, same file): it runs from a bare `TextEditingController` listener, which fires on every value change — selection included, so an Android selection drag notifies continuously — and it walks a discovery cache of up to 500 entries. **Only the search waits, and only while a name is being typed.** `schedule` sends an empty filter — the bare `@`, with nothing filtered yet — straight through, so the trigger character brings the full list up at once; the delay starts with the first letter after it. `_mentionQuery`, the range a pick replaces, is assigned before anything else and tracks the caret on every keystroke, and an ended mention cancels the timer and clears the list on the spot: a panel lingering after the user typed a space, or a replacement range pointing at text already moved past, would be wrong rather than merely late. While the timer runs the previous list stays on screen, and picking from it still replaces the current range, which is what makes a stale row harmless. Picking also closes the panel immediately — the inserted `@[name]` ends in a bracket, so `queryAt` returns null on the very next notification.

Two filters shape that list, and both matter more than they look. A name is offered **once**: the two sets overlap, a mention carries nothing but a name, and duplicate rows would be visually identical with nothing to choose between them. The first occurrence wins, which keeps a real contact ahead of a discovery entry and — because the screens compare suggestion lists by public key — keeps the surviving row the same one on every rebuild; an unstable pick would rebuild the picker under the user's finger. `excludeKeyHex` then drops this node itself, which `allContacts` filters out of the discovery half but not out of the node's own contacts. Names are compared trimmed and case-insensitively, which also leaves the sort with no ties to break.

Two non-obvious bits in `widgets/mention_suggestions_panel.dart` and its callers. Rows fire on `onPointerDown`, not `onTap`: touching the panel pulls focus out of the composer, the focus listener hides the panel, and a pending tap would be cancelled with it. And the `MentionQuery` is kept in screen state rather than recomputed on selection — by the time a row is picked the caret may already be gone.

**Rendering.** `MentionText.split` cuts message text into plain and mention runs; `widgets/mention_chip.dart` draws the chip in either the bordered or the plain look, per `AppSettings.simplifiedMentions`. This happens for every `@[name]` in the body, regardless of that setting and of `incomingQuoteAsMentions` — those two only govern the *reply* chip. Tapping an inline mention opens the contacts list filtered by that name (`ContactsScreen.openWithSearch`), while the reply chip scrolls to the quoted message: same look, deliberately different destinations.

### Exact quotes (plain-text replies)
Plain-text replies carry only `@[sender]`, which the receiver resolves to that sender's *newest* message. `helpers/exact_quote_helper.dart` adds a quote fragment so the reply anchors to the message it was actually written for. Wire form is `@[sender] >fragment\ntext`; the whole mechanism (both directions) lives in that one file, exposed as `formatReply` / `resolveReply` — everything else is call sites.

**Outbound** (`_applyReplyMention` → `_formatReply` in `channel_chat_screen.dart`, channels only). Budget is `AppSettings.exactQuoteLimit` (3–100, default 20) counted in **wire bytes**: the fragment is cut from the readable original, but each character is weighed after cyr2lat substitution, using the table `MeshCoreConnector.channelCyr2LatCharMap()` returns for that channel. Trailing `[\s.+,-]` is trimmed (a question mark is deliberately kept) and an ellipsis is appended only when the fragment is shorter than its source. No fragment is spent when the toggle is off, when the target is the sender's newest message, or when `MeshCoreConnector.channelReplyCarriesMcmpAnchor()` is true — MCMP v3 and MCOtxt v1 already ship an exact author+timestamp anchor.

**Inbound** (`_addChannelMessage`). Three predicates in the helper own the policy, so the connector and the chat screen cannot drift apart on it. `parsesFragment` refuses outright when `containerReplyTimestamp != null`: an MCMP or MCOtxt body never carries a fragment — it has an author+timestamp anchor and needs none — so a leading `>` line there is the author's own writing and stays in the message as ordinary text. Otherwise the fragment is parsed, except when replies are drawn as mentions *and* `AppSettings.exactQuote` is off. It is then cut off the body and matched backwards through history against messages from that author: prefix match first, then the candidate re-encoded through `extendedCharMap` → `defaultCharMap` → `transliterationCharMap` → the user's own cyr2lat profiles. Encoding the candidate rather than decoding the fragment is deliberate — several Cyrillic letters share one Latin look-alike, so the reverse is ambiguous. `stripsFragment` decides whether the line actually leaves the stored body, and it only does when something will display it back: with no bubble in front of the message and nothing matched, removing it would swallow the only excerpt the sender paid payload for.

**Quote or mention** (`rendersAsQuote`, read by `channel_chat_screen.dart`). `AppSettings.incomingQuoteAsMentions` draws an incoming reply as a plain mention chip instead of a quote bubble, because a bare `@[sender]` resolves to that sender's *newest* message and a bubble around a guess claims more than the message actually says. A reply that named its target keeps the bubble. Two anchors qualify and both require a message that was really found: a container anchor (MCMP v3 or MCOtxt v1) — `containerReplyTimestamp` together with the `replyToMessageId` it resolved to — and `ChannelMessage.replyIsExact`, set on receipt when the text fragment matched. An anchor that resolved to nothing falls back to the mention, since there is no message to show inside the bubble and none to scroll to. The two are governed separately: a container anchor rides inside the compressed body, costs no payload and is never something the author typed, so it always counts, while the fragment is the feature `exactQuote` switches on and off — consulted once at receipt rather than a second time at display.

`replyIsExact` is persisted by `channel_message_store` and defaults to `false` for older records, which leaves them rendering the way they already did. It exists because a resolved fragment and the `_findMessageBySender` guess both leave a non-null `replyToMessageId`, so nothing else tells them apart afterwards. A container anchor needs no flag of its own — `containerReplyTimestamp` already says which kind of anchor the message carries — which is also why the places that attach an MCMP or MCOtxt anchor to a channel message were left untouched.

Both sides normalise identically before cutting or comparing: leading scaffolding (a quote line or a mention the quoted message itself began with) is stripped, whitespace collapsed, ends trimmed. A miss stores the received fragment as `replyToText` with no `replyToMessageId`, so the quote stays visible but untappable; `_findReplyFallbackMessageId` in the screen may still resolve it later by substring after older messages load. Parsing happens once on receipt and the processed text is what gets persisted — toggling the settings does not replay old messages.

### Inline text markup
Chat-style formatting parsed by `helpers/message_markup.dart`: `**bold**`, `__italic__`, `_underline_`, `~~strike~~`, a monospace block fenced by triple backticks, and colour tags like `[r]red[/r]`. `parse()` returns styled runs and drops the markers; `parse(keepMarkers: true)` keeps them as their own segments, which the composer needs so caret offsets still line up with the raw text.

Colour is the second axis: ten tags — `[r]` `[g]` `[b]` `[y]` `[o]` `[lb]` `[p]` `[w]` `[bk]` `[gr]` — each closed by `[/key]`. Note `[b]` is **blue** and black is `[bk]` — the original spec used `[b]` for both, and blue won because it came first. Keys live in `MessageMarkup.colorKeys` (longest first, so `[b]` cannot shadow `[bk]`) while the pigments live in `MarkupPalette` (`theme/mesh_theme.dart`) — parser owns the syntax, theme owns the colour. `MarkupStyles.color` carries the innermost key, so nesting replaces rather than blends.

Rules that matter when touching it: a span only opens when its closer exists later (so a lone `*` or an unclosed `[r]` stays literal), markers built from `_` refuse to open inside a word (snake_case, URLs), a monospace block is literal all the way to its closer, and spans may cross line breaks. Only the ten known colour keys are markup, which is what keeps `@[name]` mentions out of the parser's way. `has()` short-circuits on a codeunit scan for `*_~[` and backtick before parsing, because message lists render mostly plain text.

Three call sites. **Rendering**: `widgets/formatted_message_text.dart` treats markup as the outer layer and resolves mentions and links inside each run, so a bold sentence keeps its mention chip and tappable URL; that widget is reached from `TranslatedMessageContent`, which falls back to plain `Linkify` when neither markup nor a mention is present. **Composing**: `widgets/markup_text_editing_controller.dart` overrides `buildTextSpan` to dim the markers and style the run between them — characters are never hidden, since a Flutter field cannot hide them without the caret drifting, and that visibility is what makes deleting a marker an obvious way to strip formatting. **Toolbar and keyboard**: `ByteCountedTextField.contextMenuBuilder` appends five wrap actions plus a **Text colour** entry (`chat_format*` keys) that opens `showMarkupColorPicker` (`widgets/markup_color_picker.dart`) — ten swatches are too many for the toolbar itself. `_formattingShortcuts` binds the same wraps to Ctrl/⌘ combos on desktop only; macOS swaps in `⌘⇧U` for underline and `⌘⇧K` for monospace, and has no clear-formatting combo. Colours have no shortcuts.

The edits themselves are pure transforms in `helpers/markup_editing.dart` (`wrap`, `stripFormatting`), shared by all three entry points so they cannot drift apart; each caller applies the UTF-8 limiter afterwards, so a tag can never push a message past the payload budget. Wrapping an empty selection leaves the caret between a fresh pair. `stripFormatting` removes markers inside the selection or, failing that, the pair immediately around it — colour tags included, via `_surroundingPairs`.

### Last-hop signal in the hop list

The tracing row of a channel bubble ends its hop list with the SNR and RSSI our own radio measured
for that reception, and the packet-path screen repeats them under every route it lists.

Three frames can report a reading and only one reports both. `PUSH_CODE_LOG_RX_DATA` (0x88)
carries `[snr*4 int8][rssi int8]` in its header — `_handleLogRxData` reads those three bytes
instead of skipping them — while `CHANNEL_MSG_RECV_V3` (byte 1) and `CHANNEL_DATA_RECV`
(`ChannelDataReceivedFrame.snr`) carry SNR alone. A missing RSSI is therefore normal, not a fault.

A reading describes **one** reception, so it belongs to the route it was heard on rather than to
the message. `ChannelMessage.pathObservations` is a list of `ChannelPathObservation`
(`helpers/channel_path_signal_helper.dart`) — path bytes plus an optional SNR and RSSI — and
`channel_message_store` persists it with each path base64-encoded. The constructor still takes bare
`snr` / `rssi` arguments and folds them into that list under the message's own `pathBytes`, so a
receive path only has to hand over what its frame reported and never builds an observation itself.
`snr` and `rssi` are getters that look up `pathBytes`, the route the bubble is currently showing.

`ChannelPathSignalHelper` owns every rule about the list. `includeReading` matches by exact path
bytes and fills only the gaps of the entry it finds, so the same packet arriving twice — once as a
channel message carrying SNR alone, once through the RX log carrying both — completes one
observation instead of creating two. `merge`, which `_addChannelMessage`'s repeat merge calls,
folds an incoming list into a stored one the same way. A copy that travelled a different route adds
its own entry and never lends its numbers to another: mixing an SNR from one reception with an RSSI
from another would describe a link nobody heard. Nothing is overwritten either, so a route keeps
the first real reading it got.

Rendering lives in `helpers/signal_reading_text.dart` (`signalReadingSpans`, plus the RSSI colour
scale) rather than in `channel_chat_screen.dart`, which is a merge hot spot. The spans are appended
to the hop list's own `Text` instead of becoming another chip in the meta row's `Wrap`, so they
inherit its font and only colour sets them apart — the same five-step scale the app-bar SNR
indicator paints, SNR against the current spreading factor through `snrUiFromSNR`, RSSI against its
own dBm thresholds. Each reading is glued on with a non-breaking space: a plain space is a break
opportunity, and a reading must never be stranded on a line without the hop it belongs to. With no
hop list in front of them the first reading takes no glue, or it would sit a space further from the
route chip than every other row does.

A message heard with no repeater in between has no hop list but still has a reading, so the row
appears for it too and the route chip reads `DIRECT`. `channel_message_path_screen.dart` asks
`ChannelPathSignalHelper.find` for each path variant it draws, so a packet heard over several
routes shows what each one measured, and a variant with no observation simply shows none. All of it
is gated on `AppSettings.showLastHopSignal` (default on, in mod settings) on top of the existing
tracing and `showHops` gates.

### Overhearing our own packets

Two features read the same thing out of `PUSH_CODE_LOG_RX_DATA` (0x88): a repeater within our
radio range retransmits a packet we sent, our radio logs that retransmission, and the packet
itself says how far it has already travelled. Both are **passive** — nothing extra is
transmitted, and neither delays the send it is watching. Both live in their own helper, because
the parsing is fiddly and the matching rules are what break first.

**Live path tracing** (`helpers/path_trace_progress_helper.dart`, driven from
`path_trace_map.dart`). `PathTraceProgressTracker.parse` accepts a frame only after proving it
belongs to *this* request: the four-byte trace tag matches, the flags encode the same hash width
we asked for, and the route bytes are byte-for-byte ours. Everything else — a TRACE from another
app, our own earlier trace, a packet on a different route — is rejected. It also insists the path
entry width is 1, because TRACE stores exactly one signed SNR byte per completed stage, and that
is what the accumulated readings are read from.

A `PathTraceObservation` deliberately carries **two unrelated measurements**, and the UI must
keep them apart: `routeSnr` is what the relay recorded when it received the packet from the
previous hop — the number the trace exists to collect — while `localSnr`/`localRssi` describe a
different link entirely, namely how *our* radio heard that relay's retransmission. Collapsing
them into one number would describe a hop nobody measured.

Observations are appended as they arrive, so the hop list fills in before any reply comes back.
`_failTrace` does not clear them, and the observation list renders on `completed > 0` rather than
on the success flag — which is what makes a timed-out trace still show how far the packet got.
They are cleared only when a new trace starts. A stage with no observation is drawn with a hollow
check and the `pathTrace_hopConfirmedNoDirectEchoTooltip`: confirmed by the reply, never heard
directly, because that hop is out of our range.

**Direct-message delivery progress** (`helpers/direct_message_progress_helper.dart`, driven from
`MessageRetryService.handleRxLogFrame`). The echo of a `TXTMSG` carries the *remaining* route, so
completed hops follow from `hopCount - remainingHopCount`, and the progress bar under an outgoing
bubble advances as the message moves away.

Matching here is stricter than it looks, and the strictness is the feature: the packet only
carries **one-byte** source and destination hashes, so several conversations collide on them
routinely. A candidate has to agree on both hashes, on the hash width and on the exact remaining
route suffix — and if more than one pending message still matches, the echo is **discarded**
rather than credited to a guess (`if (matches.length != 1) return;`). Once an echo is accepted the
tracker binds to that packet's exact payload, and a retry's tracker is armed with the previous
attempt's payload in `rejectedPayloads`, so the echo of an older attempt can never be counted as
progress of the current one. Any new call site must go through `matchingStage` rather than
comparing hashes itself, or it loses all of this.

`deliveryProgressTotalSteps` is `pathLength + 1` — the hops plus the final leg to the recipient —
and is reset together with `deliveryProgressCompletedSteps` on every attempt, so a retry starts
the bar over instead of continuing a stale one. A flood-routed message carries `-1` as its path
length, so it gets `0` total steps and shows no bar at all — there is no known route to measure
against, and `_armProgressTracker` refuses to arm for it on the same test.
Delivery fills the bar to `totalSteps`, and `chat_screen.dart` hides it once the status reaches
`delivered`. Both fields are persisted by `message_store` and default to `0` for older records.

### Map raster sources

Sources live in `MapRasterSourceCatalog` (`services/map_tile_cache_service.dart`) and are picked in app settings. Two carry an API key: Stadia (`mapTileApiKey`, with a shared demo key as fallback) and **Yandex** (`mapYandexApiKey`, no demo — the map silently falls back to OpenStreetMap until the user pastes their own key from the Yandex developer dashboard).

Tile resolution is user-picked: `mapYandexTileScale` (1.0 by default, options in `AppSettings.mapYandexTileScaleOptions`) becomes the `scale` parameter, so a value above 1.0 fetches the same tile at a multiple of 256 px for dense screens. It is part of the cache key, so changing it orphans previously downloaded tiles.

Yandex ships as two sources, `yandex` and `yandex_dark`, differing only by `theme=dark` on the request. They are separate catalog entries rather than one entry with a flag, because the theme travels in the URL and therefore in the cache key: light and dark are different files on disk and have to be counted, downloaded and cleared apart. That also means `_parseCachedTile` cannot attribute a cached Yandex tile by host alone — both share `tiles.api-maps.yandex.ru` — so it reads `theme` back out of the key, which survives because `tileCacheKey()` strips only `apikey` and `signature`. Get that wrong and the dark source reports the light one's tiles as its own. Everything else follows automatically: the API-key field, the signing secret, the tile scale and the terms link are all gated on `isYandex`, and the picker walks `MapRasterSourcePreset.values`.

Yandex needs `projection=web_mercator` on every request. Its default is elliptical Mercator (EPSG:3395), which flutter_map does not model — it ships `Epsg3857`, `Epsg4326` and `Proj4Crs` only — and rendering those tiles on the 3857 grid would put every node marker kilometres off. Tile coordinates ride in the query string rather than the path, so `_parseCachedTile` reads `x`/`y`/`z` from `queryParameters` for that host, and `tileCacheKey()` strips `apikey` from the cache key: reissuing a key must not orphan an already-downloaded offline region.

Requests are signed when a signing secret is set (`mapYandexSigningSecret`, entered in settings next to the key). `signYandexUrl()` implements the *simple signature*: `HMAC-SHA256` over the path and query with the host stripped, keyed with the Base64UrlSafe-decoded secret, digest appended Base64UrlSafe as the last `signature` parameter. Because the signature covers the finished URL, it can only be computed per tile — hence `CachedNetworkTileProvider.urlSigner`, applied after flutter_map substitutes the coordinates, and the same call in `downloadRegion`. `tileCacheKey()` strips `apikey` **and** `signature`, so a tile survives a reissued key, a rotated secret, and signing being switched on or off. An undecodable secret yields an unsigned URL rather than a broken one, which the console's "optional" signature mode still accepts.

Two deliberate departures from the provider's terms, decided by the project owner:

- **Cache lifetime.** Yandex permits caching for at most 30 days; the shared cache keeps tiles for `MapTileCacheService.cacheLifetime` (365 days). `PinnedFreshnessFileService` also overrides the `Cache-Control` Yandex sends, pinning freshness to that same period — otherwise stored tiles re-validate, which spends rate-limit slots on files already on disk and lets an offline region expire far from any network. The app is meant for mountains and emergencies where there may be no network for far longer than a month, no commercial harm is done to the provider, and a permission request has been sent to Yandex. Do not "fix" this back to 30 days without asking.
- **Bulk pre-download** stays enabled for Yandex, capped at `yandexMaxRequestsPerSecond` (25) against the published 30 rps limit. Pacing lives in `RateLimitedTileCacheManager` so rendering and pre-download share one counter; it claims a slot *before* awaiting, because tile requests arrive in parallel and reserving afterwards lets a zoom or fast pan fire them all in one burst.

Their terms also ask for two attribution elements. The **About dialog link** is in place: `settings_screen.dart` shows `settings_aboutYandexMapsTerms` — pointing at <https://yandex.ru/legal/maps_termsofuse/> — but only while a Yandex source is selected, since the requirement applies to apps actually using the tiles. The **logo overlay on the map itself is not implemented yet** and is tracked as separate work; until then the on-screen attribution is the `© Яндекс` in the source description shown when picking the source.

`buildTileLayer` sets `evictErrorTileStrategy: EvictErrorTileStrategy.notVisible`. The flutter_map default is `none`, and since Flutter caches failed image loads as well as successful ones, a tile lost to a rate limit or a dropped connection stayed a grey square for the whole session. Evicting error tiles once they leave the viewport is what makes returning to the area re-request them.

Tile requests carry a per-host `User-Agent` (`headersForUrl`): `MCO (+…)` everywhere, since the OpenStreetMap tile policy blocks library defaults like `flutter_map (…)`, and a desktop-browser string for Yandex, whose tile endpoint is built for web clients. The provider is seeded with the app agent so `TileLayer`'s `putIfAbsent` cannot overwrite it.

### Opening the map on a node

`widgets/contact_map_button.dart` is the icon button that jumps to the map centred on a
contact's own position — used from the repeater login dialog. It renders nothing at all when
`Contact.hasLocation` is false (an advert carries 0,0 until its node has a fix), so a caller
drops it into a row unconditionally. It opens at zoom 15 because the map draws node labels only
from `_labelZoomThreshold` (14.0) up, and reading the name is the point of going there.

`MapScreen.highlightPosition` does two jobs — it centres the map *and* draws the red highlight
pin — so `showHighlightPin` (default true, every existing call site unchanged) turns the pin off
for a position that only names something the map already draws itself.

### Map notifications

Notifications initiated by `MapScreen` use its local `_showMapSnackBar` overlay rather than
`ScaffoldMessenger`, `showDismissibleSnackBar`, or a snackbar placed in the map's layout. The
`OverlayEntry` is positioned 20 px from either side and 72 px above the bottom safe area, so it
overlays the map without shifting the filter, wardrive, zero-hop, or other floating controls.
Only one entry is kept: a new notification replaces the previous one, tapping dismisses it, and
the four-second timer removes it automatically. Pass `colorScheme.error` as `backgroundColor`
for failures; informational messages use `surfaceContainerHigh`. `_removeMapSnackBarOverlay`
must remain in `dispose`, and future notifications owned by the main map should use this helper.
The path-trace cancellation notice and offline-action rejection follow the same path.

### Shared markers on the map

A marker shared into a chat is the text `m:<lat>,<lon>|<label>|<flags>`, parsed by
`parseMarkerText`. `_collectSharedMarkers` in `map_screen.dart` turns every such message into a
pin, grouping repeats of the same marker so the older positions become its history trail.

**Where markers come from.** `getLoadedChannelMessagesWithShared` /
`getLoadedMessagesWithShared` merge in shared history, so pins from another node appear too.
Those getters never start a load, so the map warms both sides from `build`:
`ensureSharedChannelHistoryLoaded()` for channels, `ensureContactHistoryLoaded()` for contacts.
The contact one exists because a conversation, unlike a channel's messages, is read from storage
only when something asks for it — without it a contact's pins appeared on the map only after that
chat had been opened. It skips repeaters, whose history is CLI traffic. Contact pins are never
filtered by the channel picker: that gate is `_channelMarkerStyles.isVisible(marker.channelName)`,
and a contact marker has no channel name.

`ensureContactHistoryLoaded` cannot simply warm everything in one go: a conversation is stored as
a single JSON blob, so doing them back to back decodes the whole message store inside one frame,
which is plainly visible as a stall — and at a few hundred contacts with shared history on, three
separate costs pile up. The sweep answers each one:

- **Decoding.** Most conversations are never decoded. `MessageStore.mayContainMarker` reads the
  raw string and rejects it with a substring scan, and `secondaryMayContainMarker` does the same
  across every other node's copy, so the cost stops depending on how much history exists. That
  peek deliberately avoids `_loadMessagesJson`, whose legacy-key migration would fire a
  preferences *write* per contact, and it is synchronous so a sweep pays no async hop per look.
- **Scope discovery.** `SharedMessageHistoryHelper.knownScopes()` walks every preferences key
  with three regexes, so it is read once for the whole sweep and passed down. Asking it per
  contact was the single largest cost.
- **Frame time.** The sweep runs in the background under `_warmingContactHistory` and yields to
  the event loop after anything it decodes, and every 25 contacts regardless.

A conversation the peek rejects is left *unloaded* rather than marked loaded, so opening its chat
still reads it as before; a marker arriving later loads the conversation on the receive path
anyway. `_markerScannedContactKeys` records that a contact was examined at all, so a later sweep
skips it in one lookup — that set, not the loaded one, is what keeps the steady state cheap, and
it is cleared wherever `_loadedConversationKeys` is.

The pass only calls `notifyListeners` when it actually opened something — otherwise the notify
would drive a rebuild that starts another pass. It reports that itself rather than trusting the
loaders, because an empty conversation is stored and loaded without notifying at all.

The same getters feed `_MapConnectorSnapshot.markerSignature` — the marker list is cached
against that signature, so anything that should change the pins has to be visible to it.

**Per-channel styling.** Each channel decides whether its markers show at all, in what colour
and with which icon — the map's overflow menu → `map_showMarksFromChannels`. The feature is kept
out of `map_screen.dart` on purpose: it is fork-only and the map screen is a merge hot spot.
Four files own it — `models/channel_marker_style.dart` (style and palette),
`storage/channel_marker_style_store.dart` (persistence), `helpers/channel_marker_styles.dart`
(load/lookup/update, channel ordering) and `widgets/channel_marker_settings_sheet.dart` (all
UI). The map screen keeps one field, `syncTo` and `trackChannels` in `build`, `isVisible` in the
marker filter, `styleFor` in the marker builder, one menu entry and `channelName` on
`_SharedMarker`.

Styles are one JSON blob per node, **keyed by channel name**: indexes shift when channels are
added or removed, and the name is what shared history matches across nodes. Reads are
synchronous because a style is looked up while building every marker. Colours and icons are
stored as keys into `ChannelMarkerPalette`, never as an ARGB int and a code point — building
`IconData` from a stored code point at runtime defeats the icon tree-shaker and pulls the whole
Material font into the build.

Untouched channels store nothing: `ChannelMarkerStyle.defaultsFor(order)` derives their look
from the channel's place in the picker, walking the palette in order and wrapping around. Public
sorts first and so keeps green; the default icon is `place`. Anything the user edits is written
out and from then on wins. The visibility toggle filters in `build`, next to the hidden/removed
marker sets, rather than inside `_collectSharedMarkers` — that one is cached against a signature
which knows nothing about style changes.

**"Remove for everyone".** `helpers/shared_marker_deletions.dart` (no imports of its own) holds
the convention: the command is the marker's own text behind a `del:` prefix, sent back where the
pin came from — its channel, or the contact or room server that shared it — so a client that does
not know the convention just shows the line as text. `_SharedMarker` carries `channelIndex` or
`contactKeyHex`, exactly one of the two, and `_sendMarkerDeletion` picks the route from that.
Nothing is stored — `_collectSharedMarkers` reads the commands back out of the conversation,
which gives two rules for free: a command only hides markers **older than itself**, so re-sharing
the pin later brings it back, and deleting the command from the chat undoes it. `del:` lines
therefore have to count towards `markerSignature`, in the contact loop as well as the channel
one. In the chat the command renders as the POI badge with `chat_poiRemoved` and a struck-through
pin icon — in both chat screens, since `parseMarkerText` is unanchored and matches `del:m:...` as
readily as `m:...`. That same unanchored match is why the contact loop has to `absorb` before it
parses: without it a `del:` line drew a second pin of its own.

A command of ours hides nothing until the mesh confirms it, on the same evidence the spinner
uses: `absorb(..., pending: ...)` files it under `_pendingByTarget` instead of
`_confirmedByTarget`, so `hides` stays false while `pendingHides` turns true and fades the pin to
0.4 opacity. Dropping the pin outright would claim a removal nobody else has seen, and the send
may still fail. A command that is never confirmed leaves the pin faded, which is the truth;
deleting the command message undoes it. The two maps are independent, so a second command that
*is* confirmed removes the pin without waiting on the first.

**Wire form — the part that is easy to break.** A command must repeat the marker's label byte
for byte, or it matches nothing. Hence:

- `SharedMarkerDeletion.isMarkerPayload` (marker *or* command) keeps both out of MCMP and SMAZ
  in `prepareChannelOutboundText` / `prepareContactOutboundText`, which are also the
  normalisation and byte-estimation path — those must hand back a readable marker, not a
  container. On the **contact** side that is the whole story: neither `prepareContactOutboundText`
  nor `prepareContactOutboundTextAsync` will wrap a marker in anything, v3, v2 or SMAZ, and
  contacts have no binary transport to slip into either. Only the **channel** send path has an
  exception, the signed envelope described below.
- `SharedMarkerDeletion.isMarker` (marker only) gates cyr2lat, applied through
  `encodeLabel` to the **label alone**: coordinates and flags are structure, and a profile
  reaching them would make the message unparseable.
- A `del:` command takes **no** transform at all. Whoever sends it may not be the marker's
  author, and a different cyr2lat profile — or one that also maps Latin letters — would rewrite
  an already-transliterated label.
- Both chat screens transliterate composer text themselves before handing it to the connector;
  markers and commands are excluded there too, or a hand-typed `del:m:...|ттт|poi` would be
  rewritten whole.
- `sendMessage` / `sendChannelMessage` and both `schedule*Message` normalise a marker **before
  storing it**, not only before transmitting — otherwise the sender sees the typed Cyrillic
  label while receivers see the transliterated one, and a queued message would change shape when
  it finally goes out. Normalisation runs only for a first send (`pendingMessageId == null`):
  committing a queued or retried message re-uses text that was already normalised, and running
  the profile over it twice is exactly the rewrite described above.

**The signed envelope.** On a channel with MCMP v3 *and* signing on, a marker and its `del:`
command travel inside the v3 container instead of as plain text. Compression is incidental; the
signature is the point, since a channel post carries nothing but a display name and a plain
`del:` there lets anyone erase anyone's pin. `_isMcmpSignableText` takes `allowMarkerPayload`,
set from `channelMcmpUseSign`, and `ChannelBinaryDataHelper.tryEncodeOutbound` takes the same
flag — its default `false` also keeps a `del:` out of the *unsigned* binary MCMP
path it used to slip into, since its structured-payload guard only knew the bare `m:` prefix.

Two fallbacks keep it safe, both landing on plain text, which every client reads, and both live
in `sendChannelMessage`. A node that refuses to sign sends the marker plain rather than wrapping
it unsigned: an unsigned envelope costs bytes and proves nothing, while hiding the payload from
clients that cannot decode MCMP. And a wrapped marker that no longer fits its frame — Base91
gives back most of what the compressor won, and the signature costs 64 bytes on top — also goes
plain, instead of being refused by the length guard further down. `mcmpV3Sent` (not
`mcmpV3Applies`) is therefore what the stored message's MCMP metadata is keyed on, so a marker
that fell back cannot claim an envelope it lost.

The pin's info dialog repeats that provenance: `_MarkerSignature` carries the source message's
status onto `_SharedMarker`, `_buildInfoRow` gained a trailing slot, and the same
`McmpSignatureBadge` the bubble draws sits next to the author. It is keyed on the message rather
than on the marker, so a plain-text pin shows nothing at all, and `mcmpSignatureStatus` rides in
`markerSignature` so a manual re-check reaches the cached pin.

Contacts are excluded on purpose, both kinds. A direct message is authenticated by its ECDH
transport, and a room post carries the author's 4-byte key prefix (`fourByteRoomContactKey`,
attached by the server itself and shown beside the name in the chat), so an envelope there would
cost bytes and prove nothing the reader does not already have — only a channel post arrives with
nothing but a display name behind it. `allowMarkerPayload` therefore has exactly two call sites,
both in `sendChannelMessage`. Queued previews
(`schedule*Message`) are excluded too — they sign nothing, and a preview should not promise a
badge that only materialises at commit time.

**Waiting for the mesh.** `_SharedMarker.pendingDelivery` marks a pin of ours the mesh has not
confirmed, and draws an indeterminate `CircularProgressIndicator` around the circle. The evidence
differs by route and that is the only difference: a channel post waits for a repeat
(`repeatCount == 0`), a direct message or room post waits for its delivery receipt
(`status != MessageStatus.delivered`), because nobody acknowledges a broadcast. `failedDelivery`
is the third state and looks different rather than merely stopping — a send that gave up is
struck through with a rotated bar in `MapPalette.markerOutline`, the one shade already picked to
read against every colour in the pin palette. `repeatCount` and both `status` fields ride in
`markerSignature`: a repeat, a receipt and giving up change nothing else about a message, so
without them the cached pins would keep spinning.

Neither overlay may cost the pin any layout. Both are `Positioned` inside a
`Stack(clipBehavior: Clip.none)` whose only sizing child is the 36×36 circle — `Positioned`
never contributes to a `Stack`'s size — so the marker keeps exactly the footprint it had, and
the ring is free to reach 6px outside it. Painting outside the marker's own box is safe:
flutter_map puts each marker in a `Positioned` inside one viewport-wide `Stack`, which clips at
the viewport rather than per marker. Growing `Marker.height` or wrapping the circle in a larger
box instead is what broke marker rendering once already — the pin's own box is the thing to
leave alone.

**Hidden and removed locally.** `_hiddenMarkerIds` (session) and `_removedMarkerIds` (persisted
by `MapMarkerService`) are `Map<String, DateTime>`, not sets, and `_isLocallyDropped` compares
that moment against the marker's own. The reason is the same one that makes markers group into a
trail: `buildSharedMarkerKey` carries no position, so the same caption shared to the same place
later is the same id. As plain sets, removing one pin captioned `map_pointOfInterest` — the
default the share dialog offers — silently swallowed every future pin under that caption, with
no way back, since an invisible marker cannot be tapped to restore it. Bounding by time is the
rule `del:` commands already follow. Stored entries are `"<millis>|<id>"`; a bare id from before
this is **dropped** on load. Those were written under the old meaning — "hide this caption for
good" — and nothing records which pin was actually meant, so guessing a time would keep hiding
pins the user never chose to remove. Dropping them brings everything back, and removing one again
now behaves properly.

**Label budget.** `_maxMarkerLabelBytes` limits the pin caption at entry time: the channel
budget for this node (which already accounts for `"<name>: "`), capped by the user's outgoing
byte limit (which counts that prefix, so it is subtracted), less the marker scaffold, less
`SharedMarkerDeletion.prefix.length` — those four bytes are reserved so the author can later
send the same text back as a delete command without overflowing.

### Coordinates in message text

A message that is *only* `lat,lon` is still handled by `parseCoordinateText` (in `map_screen.dart`), which turns the whole bubble into one link. A pair written inside a sentence — "I'm at 45.0,38.9, see you" — is found by `helpers/coordinate_text.dart` instead and linked on its own, leaving the rest of the text alone. `CoordinateText.split` runs inside `widgets/formatted_message_text.dart`, on plain runs only, so a pair sitting in a URL query stays part of that link; `TranslatedMessageContent` routes text to that widget when `CoordinateText.has` is true, the same way it already does for mentions and markup.

The pattern is deliberately stricter than the whole-message one: both halves must carry a decimal point, or "1,5" written as a price and "steps 1,2" would read as coordinates. Out-of-range values are dropped after parsing, not by the pattern.

### Composer rebuilds
Anything in a chat composer that reacts to the text controller must go through `widgets/composer_text_builder.dart`, never a bare `ValueListenableBuilder`. A `TextEditingController` notifies on every value change, **selection included**, and dragging an Android selection handle changes the selection continuously — rebuilding the text field underneath the gesture makes the handle stutter badly enough to be unusable. `ComposerTextBuilder` rebuilds only when the text actually changes; `ByteCountedTextField` keeps its own listener with the same guard, plus a byte-count cache, because its encoder runs full MCMP compression over the message and that is far too expensive to repeat per pointer move. `MarkupTextEditingController` caches its span tree for the same reason — `buildTextSpan` fires on every repaint, not just on rebuilds.

### MCO image codec (image/GIF over LoRa)
Bespoke ultra-compressed raster format so tiny images fit LoRa text/binary messages. `helpers/mcoimg_codec.dart` (v1/v2, text prefix `im:`) and `helpers/mcoimg_v3_codec.dart` (binary container) quantize to fixed/dynamic palettes (`mcoimg_palette.dart`, `mcoimg_dynamic_palettes.dart`, up to 512 colors) and brute-force many encoders, keeping the smallest. Because the transmitted image is degraded, `services/mco_image_pack_originals.dart` keeps a hash→ordered-candidate index of installed `.mcoimg.pack` sets and renders a matching high-quality original in priority order: `.lottie.json`, `.lottie`, `.webp`, `.png`, `.gif`, `.jpg`, `.jpeg`. Invalid candidates fall through to the next format and finally to decoded MCOimg. Lottie and animated raster originals pause outside the viewport. Compose/send in `canvas_editor_screen.dart`; manage in `mco_image_gallery_screen.dart`. Channel image payloads go through `helpers/channel_binary_data_helper.dart` (`ChannelBinaryDataKind { mcoImage, mcoImageV3, mcmp }`).

### AEIC image store: pictures are paged in lazily

`ReceivedImageStore.load()` deliberately restores sizes, not bytes — reattaching a few hundred
images must not read tens of MB of PNG on the startup path — so an entry comes back with
`pngStored` / `receiverPreviewStored` re-derived from the files actually on disk and both byte
slots null. `ensurePng` and `ensureReceiverPreview` read them back on demand.

An outgoing entry has **two** pictures: the sender's own 512×512 crop in the PNG slot (written
by `registerOutgoing`; it is the backdrop of the placeholder and what a tap on the
reconstruction opens) and its own decode in `receiverPreviewPng`. It stays in `reassembled`
rather than `decoded` — `decoded` would name the wrong picture — and the renderer keys off the
preview's presence.

**Never write back a snapshot taken before an await.** `_storeSync` replaces the record whole
rather than merging fields, so a `copyWith` built on a pre-await snapshot silently reverts
whatever landed while it was on disk. The bubble asks for both pictures at once and awaits
neither, so the two loaders overlap on every restart: whichever finished second used to reset
the other's bytes to null, which showed up either as a tap opening the reconstruction instead of
the original or as a bubble stuck on the decoding spinner. Both loaders — and the outgoing
decode branch, around its own preview write — re-read `_entries[streamId]` after the await and
build the update from that. A test in `test/services/received_image_store_test.dart` pins it.

`registerOutgoing` takes the `aspectCode` the send path already computes for the wire. Without
it our own entry defaults to 1:1 and the sender is the one person seeing their own photo
squashed into a square: the stored crop is the stretched square every recipient also gets, so
the bubble has to undo the stretch exactly the way theirs does.

It also takes the region label the send was scoped with (`region` / `regionInfoAvailable`,
resolved by `MeshCoreConnector.outgoingChannelRegionLabel` — the channel's region, else the
node's default scope — exactly as a text message's label is), so an image bubble can carry the
same region line under `showMessageRegion`. An incoming image cannot: its `CHANNEL_DATA_RECV`
chunk frames hold neither a path nor a scope, so it reads as unknown rather than borrowing the
channel's region. The scope on the wire is applied for images identically to text —
`sendImageChunks` wraps the whole burst in `_runScopedChannelSend`, so every chunk of one image
goes out under one scope and no other channel send can slip in between them.

An image is not stored inside the message it arrived with — the message holds only a sentinel — so
clearing a conversation has to reach this store separately, or the bytes stay on disk with nothing
left pointing at them. The connector holds a `_deleteImagesForChannel` callback, wired in `main()`
to `ReceivedImageStore.deleteImagesForChannel` and left null when the build has no image codec, and
calls it from both places a channel's history ends: deleting the channel and clearing its messages.
The store drops every entry whose `channelIndex` matches, files included. Single-message deletion
does not currently invoke AEIC cleanup: `deleteImageForSentinel` can parse the stream id back out of
the message text, but that helper is not wired into the connector's individual-message delete path.

### Wardriving (coverage mapping)
Turns the app into a mesh coverage scanner (`services/wardrive_service.dart`, driven from `map_screen.dart` / `widgets/wardrive_status_panel.dart`). Each cycle (default 25 s, 5–300 s configurable) takes a GPS fix, sends a zero-hop discovery request, and listens ~10 s for `DiscoverResp` frames; each responder → a GPS-tagged `WardriveSample` (SNR/RSSI/node key/response time), plus `pingSuccess=false` "dead zone" samples when nobody answers. `wardrive_upload_service.dart` POSTs sample batches as JSON to configurable sites (default `https://meshwar-map.pages.dev/api/samples`), de-duping per endpoint. `wardrive_foreground_service.dart` runs an Android **location** foreground service (MethodChannel `mco_advanced/wardrive_foreground`), gated in Dart so ordinary BLE users don't inherit location FGS.

### Region / flood-scope routing
Channels can be tagged with a named region; `cmdSetFloodScope` (54) / `cmdSetDefaultFloodScope` (63) hash `#<name>` (SHA-256, first 16 bytes) into a scope. Managed in `region_management_screen.dart`; persisted in `region_store` / `channel_region_store`.

### DirectRepeater last-hop path selection
`DirectRepeater` (top of `meshcore_connector.dart`) tracks the ≤5 best last-hop repeaters ranked by SNR + recency (stale after 30 min), built from advert path tails and repeater-ACK trip-times (fed to `PathHistoryService`). Feeds auto route-rotation in `preparePathForContactSend()`. Related: **path-hash mode** (`cmdSetPathHashMode`, variable 1–4 byte per-hop hash width).

**A route the user pinned outranks every automatic decision.** `Contact.pathOverride` (null = auto, `-1` = force flood, `>= 0` = manual hop count, with `pathOverrideBytes`) is checked by all four places that can change a path: `resolvePathSelection` returns it before it looks at anything else, including `forceFlood`; `preparePathForContactSend` and `MessageRetryService._selectPathForAttempt` both skip auto-selection while it is set; and the `clearPathOnMaxRetry` cleanup in `_handleTimeout` skips too, because it would otherwise send `CMD_RESET_PATH` (`0x0D`) to the node and drop a hand-picked route to flood behind the user's back. Forcing flood counts as a choice as much as picking hops does, so any non-null override stops all four — none of them distinguish `-1`.

The override survives everything the node says about the contact. `_handleContact` and `_handleContactAdvert` both carry it across when a contact is re-read from the radio, and `clearContactPath` wipes only the device path. That matters because the node changes routes on its own and announces it with `PUSH_CODE_PATH_UPDATED` (`0x81`); `_handlePathUpdated` answers by re-reading that one contact, so `contact.path` follows the node while `pathOverride` stays the user's. The override reaches the radio again at the next send, which is the only moment the app pushes it — between sends the node runs on whatever it decided. Only two paths drop an override, both explicit: `setPathOverride(pathLen: null)` (the "auto" choice) and `deleteAllPaths()` behind its confirm dialog.

Both sides log to `AppDebugLogService` (through `appLogger`, tag `Connector`), because a path that simply vanished says nothing about who dropped it: `clearContactPath` announces the reset the app sends, `_handlePathUpdated` announces the one the node reports, and the `Refreshing contact …` line that follows carries the new device path. Keep the pair symmetric — a reset logged on one side only is worse than neither, since silence then reads as evidence.

### Room servers on the channels screen
Three mod settings decide how much of the contact list the channels screen borrows. `roomServerShowNotemptyOnChatscreen` adds room servers (`advTypeRoom`) and `roomServerShowNotemptyContactsOnChatscreen` adds ordinary chat contacts (`advTypeChat`) — both only where `Contact.hasMessages` is true, so an advert alone never puts a node there. `roomServerDisableRoomAndContactsSorting` (default **on**; the other two default off) keeps them out of the channel sort order, and while it is on `_visibleRoomServers()` returns nothing at all. `widgets/message_search_sheet.dart` reads the same two visibility flags, so search covers exactly what the screen shows.

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

Recoverable BLE loss does not navigate away from the current chat/canvas. The connector shows the reconnecting state, queues pending sends and retries indefinitely with capped exponential delay; successful `SELF_INFO` restores the ready session. Manual disconnects and non-recoverable USB/TCP loss return to their connection flow.

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

App version: `9.5.1-mcoa.1.8.6+43` — Dart SDK constraint: `^3.9.2`

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
| drift | ^2.34.3 | SQLite layer for the message-history database |
| drift_flutter | ^0.3.1 | Platform wiring for drift (native background isolate, file location) |
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
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` (foreground process/engine retention for BLE and optional background TCP)
- `WAKE_LOCK`
- `CAMERA` (QR scanning, declared as optional feature)
- USB host hardware feature (optional)

`BackgroundService.ensureBatteryOptimizationExemption` checks Android's battery-optimization whitelist, which is what lets the foreground service — and with it the BLE or TCP link — survive Doze. It has nothing to do with wardriving, which runs its own location service. The **check** runs on every launch and on the first explicit BLE connection; the **prompt** is spent once per install and recorded in `background_battery_exemption_asked_v1`, because it throws the user out to a system screen and repeating that every launch reads as nagging for something already declined. The record is written before the prompt, so backing out of that screen still counts as the one ask. Settings → Debug has an Android-only tile that asks again on purpose, through `force: true`, which steps past both that record and the once-per-reason guard held for the current run.

`flutter_foreground_task` registers a connected-device `ForegroundService` (`foregroundServiceType="connectedDevice"`, `stopWithTask="false"`); a separate wardrive `location` foreground service is declared and enabled only via the Android-only wardrive path. `MainActivity` caches the main Flutter engine while the service has an active keep-alive reason. The engine sends an in-process heartbeat every 5 seconds; after 20 seconds without one, a surviving/restarted foreground task changes its notification to `app_connectionLostBreaked`. This heartbeat is not a BLE or LoRa packet. If Android kills the whole process, the service cannot reconstruct BLE because it has no connector of its own.

**Build config (`android/app/build.gradle.kts`)**: `applicationId = com.meshcore.mcoadvanced`, NDK `29.0.14206865`, Java/Kotlin 17 with core-library desugaring (`desugar_jdk_libs:2.1.4`), release signing via `key.properties` (debug fallback).

### iOS (`ios/Runner/Info.plist`)
Deployment target is owned by the build profile, not edited by hand: `tool/use_translation_profile.dart` writes it into `ios/Podfile` and all three `IPHONEOS_DEPLOYMENT_TARGET` entries in `project.pbxproj` — 13.0 for **lite**, 16.0 for **lite-aeic** and **full**, where `flutter_onnxruntime` forces it. The two files must agree: CocoaPods fails the build outright when the Podfile platform is lower than a plugin needs. Switching a profile requires dropping `ios/Pods` and `ios/Podfile.lock` before `pod install`. The Podfile also declares `onnxruntime-objc` with `:modular_headers => true`, guarded by a check for `flutter_onnxruntime` in `.flutter-plugins-dependencies`: that pod ships no module map, so CocoaPods refuses to link the Swift plugin statically without one, and the guard keeps the lite profile from pulling a runtime it does not use.
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
| `lib/helpers/mention_autocomplete.dart` | `@[name]` parsing for the composer and for message rendering |
| `lib/helpers/mcoimg_v3_codec.dart` | MCO image-over-LoRa codec (v3 binary container) |
| `lib/helpers/path_trace_progress_helper.dart` | Matches overheard TRACE retransmissions to the running trace |
| `lib/helpers/direct_message_progress_helper.dart` | Matches overheard message retransmissions to a pending direct message |
| `lib/storage/prefs_manager.dart` | SharedPreferences singleton initialized in `main()` |
| `lib/storage/message_history_database.dart` | drift schema, queries, legacy import and quarantine (`.g.dart` is committed, see `.gitignore`) |
| `lib/storage/message_history_storage.dart` | The only door to that database; holds the web fallback and the key caches |
| `lib/storage/message_history_maintenance.dart` | Statistics, diagnostic/recovery export, quarantine retry, vacuum |
| `lib/screens/scanner_screen.dart` | Home screen — BLE scan and connect |
| `lib/screens/mod_settings_screen.dart` | Advanced-mod feature toggles |
| `pubspec.yaml` | Dependencies and project metadata; the `## Dependencies` section above quotes the same version |
